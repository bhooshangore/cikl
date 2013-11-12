package CIF::Router;
use base 'Class::Accessor';

use strict;
use warnings;

use Try::Tiny;
use Config::Simple;
use AnyEvent;
use Coro;
require CIF::Archive;
require CIF::APIKey;
require CIF::APIKeyGroups;
require CIF::APIKeyRestrictions;
use CIF qw/is_uuid generate_uuid_ns generate_uuid_random debug/;
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
    archive_config datatypes 
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
   
    $self->{auth_write_cache} = {};
    $self->{commit_interval} = $self->get_config->{'dbi_commit_size'} || 10000;
    $self->{auth_cache_ageoff} = $self->get_config->{'auth_cache_ageoff'} || 60;
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
    debug("ret: " . $ret);
    return $ret;
}

sub init_feeds {
    my $self = shift;

    my $feeds = $self->get_archive_config->{'feeds'};
    $self->set_feeds($feeds);
    
    my $array;
    foreach (@$feeds){
        my $m = {
            key     => generate_uuid_ns($_),
            value   => $_,
        };
        push(@$array,$m);
    }
    $self->set_feeds_map($array);
}

sub init_archive {
    my $self = shift;
    my $dt = $self->get_archive_config->{'datatypes'} || ['infrastructure','domain','url','email','malware','search'];
    CIF::Archive->load_plugins($dt);
    $self->set_datatypes($dt);
}

sub init_restriction_map {
    my $self = shift;
    
    return unless($self->get_restriction_map());
    my $array;
    foreach (keys %{$self->get_restriction_map()}){
        ## TODO map to the correct Protobuf RestrictionType
        my $m = {
            key => $_,
            value   => $self->get_restriction_map->{$_},
        };
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
        my $m = {
            key     => generate_uuid_ns($_),
            value   => $_,
        };
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
        next unless($rec->inGroup($g->{key}));
        push(@array,$g);
    }

    #debug('groups: '.join(',',map { $_->get_key() } @array)) if($debug > 3);

    $ret->{'group_map'} = \@array;
    
    if(my $m = $self->get_restriction_map()){
        $ret->{'restriction_map'} = $m;
    }

    return(undef,$ret); # all good
}

sub authorized_write_cache_store {
    my $self = shift;
    my $key = shift;
    my $retval = shift;
    $self->{auth_write_cache}->{$key} = {
      'time' => time(),
      'retval' => $retval
    };

    return $retval;
}

sub authorized_write_cache_get {
    my $self = shift;
    my $key = shift;

    if (my $cached_auth = $self->{auth_write_cache}->{$key}) {
      if (time() - $cached_auth->{time} <= 60) {
        return $cached_auth->{retval};
      }
    }
    return undef;
}

sub authorized_write {
    my $self = shift;
    my $key = shift;

    my $retval = $self->authorized_write_cache_get($key);

    if (defined($retval)) {
      return($retval);
    }
    
    my $rec = $self->key_retrieve($key);

    my $ret;
    if (!defined($rec) || 
        !($rec->write()) ||
        $rec->revoked() || 
        $rec->restricted_access() ||
        $rec->expired() ) {
      $ret = 0;
    } else {
      $ret = {
        default_guid    => $rec->default_guid(),
      };
    }
    $self->authorized_write_cache_store($key, $ret);
    return($ret);
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
    my $query = shift;
    #my $msg = shift;

    my $results = [];

    my $restriction_map = $self->get_restriction_map();
    my ($err2, $apikey_info) = $self->authorized_read($query->apikey);
    if(!defined($apikey_info) or defined($err2)){
      die($err2);
    }
    if (!defined($query->guid())) {
      $query->set_guid($apikey_info->{'default_guid'});
    }

    my ($err, $events) = CIF::Archive->search($query);
    if (defined($err)) {
      die($err);
    }


    my $query_results = CIF::Models::QueryResults->new({
        query => $query,
        events => $events,
        reporttime => time(),
        group_map => $apikey_info->{'group_map'},
        restriction_map => $restriction_map,
        guid => $apikey_info->{'default_guid'}
      });
    return $query_results;
}

sub process_submission {
  my $self = shift;
  my $submission = shift;
  my $apikey = $submission->apikey();

  my $auth = $self->authorized_write($submission->apikey());
  my $default_guid = $auth->{'default_guid'} || 'everyone';

  my $guid    = $submission->guid() || $default_guid;
  $guid = generate_uuid_ns($guid) unless(is_uuid($guid));

  debug('inserting...') if($debug > 4);
  my ($err, $id) = $self->insert_event($guid, $submission->event());
  if ($err) { 
    debug("ERR: " . $err);
    return $err;
  }

  return undef;
}

sub flush {
  my $self = shift;
  undef $self->{flush_timer};
  delete $self->{flush_timer};
  return if ($self->{inserts} == 0);
  my $num_inserts = $self->{inserts};
  $self->{inserts} = 0;
  debug("committing $num_inserts inserts...") if ($::debug > 1);
  CIF::Archive->dbi_commit();

}

sub insert_event {
  my $self = shift;
  my $guid = shift;
  my $event = shift;
  $self->{inserts} += 1;
  my ($err, $ret) = (CIF::Archive->insert({
      event       => $event,
      guid        => $guid,
      feeds       => $self->get_feeds(),
      datatypes   => $self->get_datatypes(),
    }));

  if ($self->{inserts} >= $self->{commit_interval}) {
    $self->flush();
  } elsif (!defined($self->{flush_timer})) {
    # Create a timer that will flush two seconds after our first message 
    # comes in.
    my $cb = sub { $self->flush();};
    $self->{flush_timer} = AnyEvent->timer(after => 2, cb => $cb);
  }
  return ($err, $ret);
}

sub send {}

1;
