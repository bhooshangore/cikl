package CIF::Router;
use base 'Class::Accessor';

use strict;
use warnings;

use Try::Tiny;
use Config::Simple;

require CIF::Archive;
require CIF::APIKey;
require CIF::APIKeyGroups;
require CIF::APIKeyRestrictions;
use CIF qw/is_uuid generate_uuid_ns generate_uuid_random debug/;
use CIF::Msg;
use CIF::Msg::Feed;
use Data::Dumper;
use CIF::Models::Event;

# this is artificially low, ipv4/ipv6 queries can grow the result set rather large (exponentially)
# most people just want a quick answer, if they override this (via the client), they'll expect the
# potentially longer query as the database grows
# later on we'll do some partitioning to clean this up a bit
use constant QUERY_DEFAULT_LIMIT => 50;

__PACKAGE__->follow_best_practice();
__PACKAGE__->mk_accessors(qw(
    config db_config
    restriction_map 
    group_map groups feeds feeds_map feeds_config 
    archive_config datatypes query_default_limit
));

our $debug = 0;

sub new {
    my $class = shift;
    my $args = shift;
      
    return('missing config file') unless($args->{'config'});
    
    my $self = {};
    bless($self,$class);
    $self->set_config($args->{'config'}->param(-block => 'router'));
    
    $self->set_db_config(       $args->{'config'}->param(-block => 'db'));
    $self->set_restriction_map( $args->{'config'}->param(-block => 'restriction_map'));
    $self->set_archive_config(  $args->{'config'}->param(-block => 'cif_archive'));
   
    $self->{commit_interval} = $self->get_config->{'dbi_commit_size'} || 10000;
    $self->{inserts} = 0;
    my $ret = $self->init($args);
    return unless($ret);
     
    return(undef,$self);
}

sub init {
    my $self = shift;
    my $args = shift;
    
    my $ret = $self->init_db($args);
    
    $self->init_restriction_map();
    $self->init_group_map();
    $self->init_feeds();
    $self->init_archive();
    
    $debug = $self->get_config->{'debug'} || 0;
    $self->set_query_default_limit($self->get_config->{'query_default_limit'} || QUERY_DEFAULT_LIMIT());
    
    return ($ret);
}

sub init_db {
    my $self = shift;
    my $args = shift;
    
    my $config = $self->get_db_config();
    
    my $db          = $config->{'database'} || 'cif';
    my $user        = $config->{'user'}     || 'postgres';
    my $password    = $config->{'password'} || '';
    my $host        = $config->{'host'}     || '127.0.0.1';
    
    my $dbi = 'DBI:Pg:database='.$db.';host='.$host;
    my $ret = CIF::DBI->connection($dbi,$user,$password,{ AutoCommit => 0});
    return $ret;
}

sub init_feeds {
    my $self = shift;

    my $feeds = $self->get_archive_config->{'feeds'};
    $self->set_feeds($feeds);
    
    my $array;
    foreach (@$feeds){
        my $m = FeedType::MapType->new({
            key     => generate_uuid_ns($_),
            value   => $_,
        });
        push(@$array,$m);
    }
    $self->set_feeds_map($array);
}

sub init_archive {
    my $self = shift;
    my $dt = $self->get_archive_config->{'datatypes'} || ['infrastructure','domain','url','email','malware','search'];
    $self->set_datatypes($dt);
}

sub init_restriction_map {
    my $self = shift;
    
    return unless($self->get_restriction_map());
    my $array;
    foreach (keys %{$self->get_restriction_map()}){
        ## TODO map to the correct Protobuf RestrictionType
        my $m = FeedType::MapType->new({
            key => $_,
            value   => $self->get_restriction_map->{$_},
        });
        push(@$array,$m);
    }
    $self->set_restriction_map($array);
}

sub init_group_map {
    my $self = shift;
    my $g = $self->get_archive_config->{'groups'};
    
    # system wide groups
    push(@$g, qw(everyone root));
    my $array;
    foreach (@$g){
        my $m = FeedType::MapType->new({
            key     => generate_uuid_ns($_),
            value   => $_,
        });
        push(@$array,$m);
    }
    $self->set_group_map($array);
}  

# we abstract this out for the try/catch 
# in case the db restarts on us
sub key_retrieve {
    my $self = shift;
    my $key = shift;
    
    return unless($key);
    $key = lc($key);
    
    my ($rec,$err);
    
    try {
        $rec = CIF::APIKey->retrieve(uuid => $key);
    } catch {
        $err = shift;
    };
    if($err && $err =~ /connect/){
        my $ret = $self->connect_retry();
        $err = undef;
        if($ret){
            try {
               $rec = CIF::APIKey->retrieve(uuid => $key);
            } catch {
                $err = shift;
            };
            debug($err) if($err);
        }
    }
    
    return(0) if($err);
    return($rec);
}

sub authorized_read {
    my $self = shift;
    my $key = shift;
    
    # test1
    return('invaild apikey',0) unless(is_uuid($key));
    
    my $rec = $self->key_retrieve($key);
    
    return('invaild apikey',0) unless($rec);
    return('apikey revokved',0) if($rec->revoked()); # revoked keys
    return('key expired',0) if($rec->expired());

    my $ret;
    my $args;
    my $guid = $args->{'guid'};
    if($guid){
        $guid = lc($guid);
        $ret->{'guid'} = generate_uuid_ns($guid) unless(is_uuid($guid));
    } else {
        $ret->{'default_guid'} = $rec->default_guid();
    }
    
    ## TODO -- datatype access control?
    
    my @groups = ($self->get_group_map()) ? @{$self->get_group_map()} : undef;
   
    my @array;
    #debug('groups: '.join(',',map { $_->get_key() } @groups));
    
    foreach my $g (@groups){
        next unless($rec->inGroup($g->get_key()));
        push(@array,$g);
    }

    #debug('groups: '.join(',',map { $_->get_key() } @array)) if($debug > 3);

    $ret->{'group_map'} = \@array;
    
    if(my $m = $self->get_restriction_map()){
        $ret->{'restriction_map'} = $m;
    }

    return(undef,$ret); # all good
}

## TODO -- this is probably backwards..
sub authorized_read_query {
    my $self = shift;
    my $args = shift;
    
    my @recs = CIF::APIKeyRestrictions->search(uuid => $args->{'apikey'});
    
    # if there are no restrictions, return 1
    return 1 unless($#recs > -1);
    foreach (@recs){
        # if we've given explicit access to that query (eg: domain/malware, domain/botnet, etc...)
        # return 1
        debug('access: '.$_->access());
        return 1 if($_->access() eq $args->{'query'});
    }
    # fail closed
    return;
}

sub authorized_write {
    my $self = shift;
    my $key = shift;
    
    my $rec = $self->key_retrieve($key);
    
    return(0) unless($rec);
    
    # we must meet all these requirements
    return(0) unless($rec->write());
    return(0) if($rec->revoked() || $rec->restricted_access());
    return(0) if($rec->expired());
    return({
        default_guid    => $rec->default_guid(),
    });
}

sub process {
    my $self = shift;
    my $msg = shift;
    
    $msg = MessageType->decode($msg);
    
    my $reply = MessageType->new({
        version => $CIF::VERSION,
        type    => MessageType::MsgType::REPLY(),
        status  => MessageType::StatusType::FAILED(),
    });
    
  my $pversion = sprintf("%4f",$msg->get_version());
   if($pversion != $CIF::VERSION){
        $reply->set_data('invalid protocol version: '.$pversion.', should be: '.$CIF::VERSION);
        return $reply->encode();
    }
    my $err;
    for($msg->get_type()){
        if($_  == MessageType::MsgType::QUERY()){
            $reply = $self->process_query($msg);
            last;
        }
        if($_ == MessageType::MsgType::SUBMISSION()){
            $reply = $self->process_submissions($msg, $msg->get_apikey());
            last;
        }
    }

    debug($err) if($err);
    
    return $reply->encode();
}

sub connect_retry {
    my $self = shift;
    
    my ($x,$state) = (0,0);
    do {
        debug('retrying connection...');
        $state = $self->init_db();
        unless($state){   
            debug('retry failed... waiting...');
            sleep(3);
        } else {
            debug('success: '.$state);
        }
    } while($x < 3 && !$state);
    return 1 if($state);
    return 0;
}

sub process_query {
    my $self = shift;
    my $msg = shift;
    
    my $results = [];
    
    my $data = $msg->get_data();
    my $apikey_info;
    my $is_feed_query = 0;
    
    my $reply;
    my $authorized = 0;
    
    foreach my $m (@$data){
        $m = MessageType::QueryType->decode($m);
        # we can skip this if the first packet contains a valid apikey
        # later on; as we figure out what we're doing, we may want to
        # turn this off and check each time -- dunno why you'd search
        # with multiple apikeys; but just in case *shrug*
        unless($authorized){
            my $apikey = $m->get_apikey();
            debug('apikey: '.$apikey) if($debug > 3);
            my ($err, $ret) = $self->authorized_read($apikey);
            unless($ret){
                return(
                    MessageType->new({
                        version => $CIF::VERSION,
                        type    => MessageType::MsgType::REPLY(),
                        status  => MessageType::StatusType::UNAUTHORIZED(),
                        data    => $err,
                    })
                );
            }
            $apikey_info = $ret; 
        }
        $authorized = 1;
        debug('authorized stage1') if($debug > 3);
        my @res;
        
        # so we can tell the client how we limited the query
        my $limit = $m->get_limit() || $self->get_query_default_limit();
        foreach my $q (@{$m->get_query()}){
            debug('query: '.$q->get_query()) if($debug > 3);
            ## TODO -- there has got to be a better way to do this...
            unless($self->authorized_read_query({ apikey => $m->get_apikey(), query => $q->get_query})){
                return (
                    MessageType->new({
                        version => $CIF::VERSION,
                        type    => MessageType::MsgType::REPLY(),
                        status  => MessageType::StatusType::UNAUTHORIZED(),
                        data    => 'no access to that type of query',
                    })
                );
            }
            debug('authorized to make this query') if($debug > 3);
            my ($err,$s) = CIF::Archive->search({
                query           => $q->get_query(),
                limit           => $limit,
                confidence      => $m->get_confidence(),
                guid            => $m->get_guid() || $apikey_info->{'default_guid'},
                guid_default    => $apikey_info->{'default_guid'},
                nolog           => $q->get_nolog(),
                source          => $m->get_apikey(),
                description     => $m->get_description(),
                feeds           => $self->get_feeds(),
                datatypes       => $self->get_datatypes(),
            });
            if($err){
                debug($err);
                return(
                    MessageType->new({
                        version => $CIF::VERSION,
                        type    => MessageType::MsgType::REPLY(),
                        status  => MessageType::StatusType::FAILED(),
                        data    => 'query failed, contact system administrator',
                    })
                );
            }
            next unless($s);
            push(@res,@$s);
        }
        if($#res > -1){
            ## TODO: SHIM, gatta be a more elegant way to do this
            unless($m->get_feed()){
                debug('generating feed');
                my $dt = DateTime->from_epoch(epoch => time());
                $dt = $dt->ymd().'T'.$dt->hms().'Z';
                
                my $f = FeedType->new({
                    version         => $CIF::VERSION,
                    confidence      => $m->get_confidence(),
                    description     => $m->get_description(),
                    ReportTime      => $dt,
                    group_map       => $apikey_info->{'group_map'}, # so they can't see other groups they're not in
                    restriction_map => $self->get_restriction_map(),
                    data            => \@res,
                    uuid            => generate_uuid_random(),
                    guid            => $apikey_info->{'default_guid'},
                    query_limit     => $limit,
                    # todo -- make this avail to to libcif
                    # https://github.com/collectiveintel/cif-router/issues/5
                    #feeds_map       => $self->get_feeds_map(),
                });  
                push(@$results,$f->encode());
            } else {
                push(@$results,@res);
            }
        }
    }
    debug('replying...');
                    
    $reply = MessageType->new({
        version => $CIF::VERSION,
        type    => MessageType::MsgType::REPLY(),
        status  => MessageType::StatusType::SUCCESS(),
        data    => $results,
    });

    return $reply;
}

sub process_submissions {
    my $self = shift;
    my $msg = shift;
    my $apikey = shift;

    debug('type: submission...');
    my $auth = $self->authorized_write($apikey);
    my $reply = MessageType->new({
        version => $CIF::VERSION,
        type    => MessageType::MsgType::REPLY(),
        status  => MessageType::StatusType::UNAUTHORIZED(),
    });
    return $reply unless($auth);
    
    my $err;
    my $default_guid = $auth->{'default_guid'} || 'everyone';
    my @ret;
    
    foreach my $submission (@{$msg->get_data()}){
      my ($err, $ids) = $self->process_submission($submission, $default_guid);
      if ($err) {
        return MessageType->new({
            version => $CIF::VERSION,
            type    => MessageType::MsgType::REPLY(),
            status  => MessageType::StatusType::FAILED(),
            data    => 'submission failed: contact system administrator',
          });
      }
      @ret = (@ret, @$ids);
    }
    $self->flush();
    debug('done...');
    return MessageType->new({
        version => $CIF::VERSION,
        type    => MessageType::MsgType::REPLY(),
        status  => MessageType::StatusType::SUCCESS(),
        data    => \@ret
    });
}

sub process_submission {
  my $self = shift;
  my $data = shift;
  my $default_guid = shift;
  my $m = MessageType::SubmissionType->decode($data);

  my $iodefs = $m->get_data();
  my $guid    = $m->get_guid() || $default_guid;
  $guid = generate_uuid_ns($guid) unless(is_uuid($guid));
  ## TODO -- copy foreach loop from SMRT; commit every X objects

  my @ret;
  debug('entries: '.($#{$iodefs} + 1));
  foreach my $iodef (@{$iodefs}) {
    if (!defined($iodef) or $iodef eq '') {
      next;
    }
    debug('inserting...') if($debug > 4);
    my ($err,$id) = $self->insert_iodef($guid, $iodef);

    if($err){
      return($err);
    }
    push(@ret, $id);
  }
  return(undef, \@ret);
}

sub flush {
  my $self = shift;
  return if ($self->{inserts} == 0);
  debug('committing...');
  CIF::Archive->dbi_commit();
}

sub insert_iodef {
  my $self = shift;
  my $guid = shift;
  my $iodef = shift;
  $self->{inserts} += 1;
  my ($err, $ret) = (CIF::Archive->insert({
      data        => $iodef,
      guid        => $guid,
      feeds       => $self->get_feeds(),
      datatypes   => $self->get_datatypes(),
    }));

  if ($self->{inserts} >= $self->{commit_interval} == 0) {
    $self->flush();
    $self->{inserts} = 0;
  }
  return ($err, $ret);
}

sub process_event {
    my $self = shift;
    my $apikey = shift;
    my $event = shift;


}

sub send {}

1;
