package CIF::Archive;
use base 'CIF::DBI';

require 5.008;
use strict;
use warnings;

# to make jeff teh happies!
use Try::Tiny;

use MIME::Base64;
use Iodef::Pb::Simple qw/iodef_guid/;
require Compress::Snappy;
use Digest::SHA qw/sha1_hex/;
use Data::Dumper;
use POSIX ();

use Module::Pluggable require => 1, except => qr/::Plugin::\S+::/;
use CIF qw/generate_uuid_url generate_uuid_random is_uuid generate_uuid_ns debug/;

__PACKAGE__->table('archive');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(All => qw/id uuid guid data format reporttime created/);
__PACKAGE__->columns(Essential => qw/id uuid guid data created/);
__PACKAGE__->sequence('archive_id_seq');

my @plugins = __PACKAGE__->plugins();

our $root_uuid      = generate_uuid_ns('root');
our $everyone_uuid  = generate_uuid_ns('everyone');

sub insert {
    my $class       = shift;
    my $data        = shift;
    my $isUpdate    = shift;
        
    my $msg = $data->{'data'}; 

    if($data->{'format'} && $data->{'format'} eq 'feed'){
        unless (UNIVERSAL::isa($msg, 'FeedType')) {
          $msg = FeedType->decode($msg);
        }
    } else {
        unless (UNIVERSAL::isa($msg, 'IODEFDocumentType')) {
          $msg = IODEFDocumentType->decode($msg);
        }
        $data->{'uuid'}         = @{$msg->get_Incident}[0]->get_IncidentID->get_content();
        $data->{'reporttime'}   = @{$msg->get_Incident}[0]->get_ReportTime();
        $data->{'guid'}         = iodef_guid(@{$msg->get_Incident}[0]) || $data->{'guid'};
    }
    
    $data->{'uuid'} = generate_uuid_random() unless($data->{'uuid'});
   
    return ('id must be a uuid') unless(is_uuid($data->{'uuid'}));
    
    $data->{'guid'}     = generate_uuid_ns('root')                  unless($data->{'guid'});
    $data->{'created'}  = DateTime->from_epoch(epoch => time())     unless($data->{'created'});
   
    my $encoded = encode_base64(Compress::Snappy::compress($msg->encode()));
    my ($err,$id);
    try {
        $id = $class->SUPER::insert({
            uuid        => $data->{'uuid'},
            guid        => $data->{'guid'},
            format      => $CIF::VERSION,
            data        => $encoded,
            created     => $data->{'created'},
            reporttime  => $data->{'reporttime'},
        });
    }
    catch {
        $err = shift;
    };
    return ($err) if($err);
    
    $data->{'data'} = $msg;
    
    my $ret;
    ($err,$ret) = $class->insert_index($data);
    return($err) if($err);
    return(undef,$data->{'uuid'});
}

sub insert_index {
    my $class   = shift;
    my $args    = shift;

    my $err;
    foreach my $p (@plugins){
        my ($pid,$err);
        try {
            ($err,$pid) = $p->insert($args);
        } catch {
            $err = shift;
        };
        if($err){
            warn $err;
            $class->dbi_rollback() unless($class->db_Main->{'AutoCommit'});
            return $err;
        }
    }
    return(undef,1);
}

sub search {
    my $class = shift;
    my $data = shift;

    $data->{'confidence'}   = 0 unless(defined($data->{'confidence'}));
    $data->{'query'}        = lc($data->{'query'});
 
    my $ret;
    debug('running query: '.$data->{'query'});
    if(is_uuid($data->{'query'})){
        $ret = $class->search_lookup(
            $data->{'query'},
            $data->{'source'},
        );
    } else {
        # log the query first
        unless($data->{'nolog'}){
            debug('logging search');
            my ($err,$ret) = $class->log_search($data);
            return($err) if($err);
        }
        foreach my $p (@plugins){
            my $err;
            try {
                $ret = $p->query($data);
            } catch {
                $err = shift;
            };
            if($err){
                warn $err;
                return($err);
            }
            last if(defined($ret));
        }
    }

    return unless($ret);
    my @recs = (ref($ret) ne 'CIF::Archive') ? reverse($ret->slice(0,$ret->count())) : ($ret);
    my @rr;
    foreach (@recs){
        # protect against orphans
        next unless($_->{'data'});
        push(@rr,Compress::Snappy::decompress(decode_base64($_->{'data'})));
    }
    return(undef,\@rr);
}

sub log_search {
    my $class = shift;
    my $data = shift;
    
    my $q               = lc($data->{'query'});
    my $source          = $data->{'source'}         || 'unknown';
    my $confidence      = $data->{'confidence'}     || 50;
    my $restriction     = $data->{'restriction'}    || 'private';
    my $guid            = $data->{'guid'}           || $data->{'guid_default'} || $root_uuid;
    my $desc            = $data->{'description'}    || 'search';
    
    my $dt          = DateTime->from_epoch(epoch => time());
    $dt = $dt->ymd().'T'.$dt->hms().'Z';
    
    $source = generate_uuid_ns($source);
    
    my $id;
   
    my ($q_type,$q_thing);
    for(lc($desc)){
        # reg hashes
        if(/^search ([a-f0-9]{40}|[a-f0-9]{32})$/){
            $q_type = 'hash';
            $q_thing = $1;
            last;
        } 
        # asn
        if(/^search as(\d+)$/){
            $q_type = 'hash';
            $q_thing = sha1_hex($1); 
            last;
        } 
        # cc
        if(/^search ([a-z]{2})$/){
            $q_type = 'hash';
            $q_thing = sha1_hex($1);
            last;
        }
        m/^search (\S+)$/;
        $q_type = 'address',
        $q_thing = $1;
    }
   
    # thread friendly to load here
    ## TODO this could go in the client...?
    require Iodef::Pb::Simple;
    my $uuid = generate_uuid_random();
    
    my $doc = Iodef::Pb::Simple->new({
        description => $desc,
        assessment  => AssessmentType->new({
            Impact  => [
                ImpactType->new({
                    lang    => 'EN',
                    content => MLStringType->new({
                        content => 'search',
                        lang    => 'EN',
                    }),
                }),
            ],
            
            ## TODO -- change this to low|med|high
            Confidence  => ConfidenceType->new({
                content => $confidence,
                rating  => ConfidenceType::ConfidenceRating::Confidence_rating_numeric(),
            }),
        }),
        $q_type             => $q_thing,
        IncidentID          => IncidentIDType->new({
            content => $uuid,
            name    => $source,
        }),
        detecttime  => $dt,
        reporttime  => $dt,
        restriction => $restriction,
        guid        => $guid,
        restriction => RestrictionType::restriction_type_private(),
    });
   
    my $err;
    ($err,$id) = $class->insert({
        uuid        => $uuid,
        guid        => $guid,
        data        => $doc,
        created     => $dt,
        feeds       => $data->{'feeds'},
        datatypes   => $data->{'datatypes'},
    });
    return($err) if($err);
    $class->dbi_commit() unless($class->db_Main->{'AutoCommit'});
    return(undef,$id);
}

sub load_page_info {
    my $self = shift;
    my $args = shift;
    
    my $sql = $args->{'sql'};
    my $count = 0;
    if($sql){
        $self->set_sql(count_all => "SELECT COUNT(*) FROM __TABLE__ WHERE ".$sql);
    } else {
        $self->set_sql(count_all => "SELECT COUNT(*) FROM __TABLE__");
    }
    $count = $self->sql_count_all->select_val();
    $self->{'total'} = $count;
}

sub has_next {
    my $self = shift;
    return 1 if($self->{'total'} > $self->{'offset'} + $self->{'limit'});
    return 0;
}

sub has_prev {
    my $self = shift;
    return $self->{'offset'} ? 1 : 0;
}

sub next_offset {
    my $self = shift;
    return ($self->{'offset'} + $self->{'limit'});
}

sub prev_offset {
    my $self = shift;
    return ($self->{'offset'} - $self->{'limit'});
}

sub page_count {
    my $self = shift;
    return POSIX::ceil($self->{'total'} / $self->{'limit'});
}

sub current_page {
    my $self = shift;
    return int($self->{'offset'} / $self->{'limit'}) + 1;
}

__PACKAGE__->set_sql('lookup' => qq{
    SELECT t1.id,t1.uuid,t1.data
    FROM __TABLE__ t1
    LEFT JOIN apikeys_groups ON t1.guid = apikeys_groups.guid
    WHERE
        t1.uuid = ?
        AND apikeys_groups.uuid = ?
});

1;
