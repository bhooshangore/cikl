package CIF::Archive;
use base 'CIF::DBI';

require 5.008;
use strict;
use warnings;

# to make jeff teh happies!
use Try::Tiny;

use Digest::SHA qw/sha1_hex/;
use Data::Dumper;
use POSIX ();
use CIF::Client::Query;
use CIF::APIKeyRestrictions;
use CIF::Codecs::JSON;
use CIF::Models::Query;
use CIF::Models::QueryResults;
use List::MoreUtils qw/any/;
use Carp;
use Module::Pluggable require => 1, sub_name => '__plugins', 
  on_require_error => \&croak;
use CIF qw/generate_uuid_url generate_uuid_random is_uuid generate_uuid_ns debug/;

__PACKAGE__->table('archive');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(All => qw/id uuid guid data format reporttime created/);
__PACKAGE__->columns(Essential => qw/id uuid guid data created/);
__PACKAGE__->sequence('archive_id_seq');

my $db_codec = CIF::Codecs::JSON->new();

our $root_uuid      = generate_uuid_ns('root');
our $everyone_uuid  = generate_uuid_ns('everyone');
our $archive_plugins        = undef; # Not loaded, yet.
our %guid_id_cache;

sub get_guid_id {
    my $class = shift;
    my $guid = lc(shift);
    if (my $existing = $guid_id_cache{$guid}) {
      return $existing;
    }
    # otherwise query it.
    my $cr = $class->sql_get_guid_id;
    if (!$cr->execute($guid)) {
      die($!);
    }
    if (my $data = $cr->fetchrow_hashref()) {
      $cr->finish();
      my $id = $data->{id};
      $guid_id_cache{$guid} = $id;
      return $id;
    }
    $cr->finish();
    # Didn't get anything, insert it, and return the id.
    $cr = $class->sql_insert_guid;
    $cr->execute($guid) or die("Failed to insert into archive_guid_map");
    my $id = $cr->fetchrow_hashref->{'id'};
    $cr->finish();
    $guid_id_cache{$guid} = $id;
    return $id;
}

sub plugins {
    my $class = shift;
    if (!defined($archive_plugins)) {
      die("$class->load_plugins has not been called, yet!");
    }
    return $archive_plugins;
}

sub load_plugins {
    if (defined($archive_plugins)) {
      return 1;
    }
    
    my $class = shift;
    my $datatypes = shift || [];
    my $feeds = shift || [];
    $archive_plugins = [];
    my @all_plugins = $class->__plugins();

    foreach my $plugin (@all_plugins) {
      if (any { $_ eq $plugin->datatype() } @$datatypes) {
        $plugin->init_sql();
        my $feed_enabled = 0;
        if (any { $_ eq $plugin->datatype() } @$feeds) {
          $feed_enabled = 1;
        }
        push(@$archive_plugins, {plugin => $plugin, feed_enabled => $feed_enabled});
      }
    }
    return 1;
}


sub insert {
    my $class       = shift;
    my $event = shift;
   
    my ($err,$id);
    my $guid_id = $class->get_guid_id($event->guid);
    $id = 1;
    try {
        my $cr = $class->sql_insert_into_archive;
        $cr->execute(
#            $event->id,
#            $event->guid,
#            $CIF::VERSION,
            $db_codec->encode_event($event),
            $guid_id,
            $event->detecttime, # Fairly sure this is supposed to be detecttime
            $event->reporttime
        ) or die("Failed to insert into archive");
        $id = $cr->fetchrow_hashref->{'id'};
        $cr->finish();
    }
    catch {
        $err = shift;
    };
    return ($err) if($err);
    
    my $ret;
    ($err,$ret) = $class->insert_index($event, $id);
    return($err) if($err);
    return(undef,$event->id);
}

sub insert_index {
    my $class   = shift;
    my $event = shift;
    my $archive_id = shift;
    my ($err, $p);
    foreach my $address (@{$event->addresses()}) {
      my $cr;
      my $value = $address->value;
      if ($address->type eq 'asn') {
        $cr = $class->sql_insert_into_archive_asn;
      } elsif ($address->type eq 'cidr') {
        $cr = $class->sql_insert_into_archive_cidr;
      } elsif ($address->type eq 'email') {
        $cr = $class->sql_insert_into_archive_email;
      } elsif ($address->type eq 'fqdn') {
        $cr = $class->sql_insert_into_archive_fqdn;
      } elsif ($address->type eq 'ip') {
        $cr = $class->sql_insert_into_archive_ip;
      } elsif ($address->type eq 'url') {
        $cr = $class->sql_insert_into_archive_url;
      }

      if ($cr) {
        $cr->execute(
          $value,
          $archive_id,
          $event->detecttime,
          $event->reporttime
        );
      } else {
        debug("Unknown address type: " . $address->type);
      }
    }

#    foreach my $x (@{$class->plugins}){
#        $p = $x->{plugin};
#        if ($p->match_event($event) == 1) {
#          #debug("Inserting into $p");
#          my ($pid,$err);
#          try {
#              ($err,$pid) = $p->insert($event);
#              if($x->{feed_enabled}) {
#                $p->insert_into_feed($event);
#              }
#          } catch {
#              $err = shift;
#          };
#          if($err){
#              warn $err;
#              $class->dbi_rollback() unless($class->db_Main->{'AutoCommit'});
#              return $err;
#          }
#        }
#
#    }
    return(undef,1);
}

sub normalize_query {
    my $class = shift;
    my $query = shift;
    my $splitup = $query->splitup();
    my @ret;

    foreach my $q (@$splitup) {
      my @new_queries; 
      foreach my $plugin (CIF::Client::Query->plugins()){
        my ($err,$r) = $plugin->process($q->to_hash);
        return($err) if($err);
        next unless($r);
        $r = [$r] unless ref($r) eq "ARRAY";

        foreach my $x (@$r) {
          push(@new_queries, CIF::Models::Query->from_existing($q, $x));
        }
        last;
      }
      if ($#new_queries > -1) {
        @ret = (@ret, @new_queries);
      } else {
        push(@ret, $q);
      }

    }
    return undef, \@ret;
}

sub search {
    my $class = shift;
    my $query = shift;

    my ($err, $normalized_queries) = $class->normalize_query($query);

    my @res;
    foreach my $m (@$normalized_queries){
        my $hashed_query = $m->hashed_query();
        my ($err2,$s) = CIF::Archive->search2($m);
        if($err){
          return('query failed, contact system administrator');
        }
        next unless($s);
        @res = (@res, @$s);
    }

    return(undef, \@res);
}

sub search2 {
    my $class = shift;
    my $query = shift;
 
    my $ret;
    if(is_uuid($query->query())) {
        $ret = $class->search_lookup(
            $query->query(),
            $query->apikey(),
        );
    } else {
        my $hashed_query = $query->hashed_query();
        my $err;
        try {
          $ret = CIF::Archive::Hash->query({
              query           => $hashed_query,

              description     => $query->description(),
              limit           => $query->limit(),
              confidence      => $query->confidence(),
              guid            => $query->guid(),

              nolog           => $query->nolog(),
              source          => $query->apikey(),
              apikey          => $query->apikey()
            });
        } catch {
          $err = shift;
        };
        if($err){
          warn $err;
          return($err);
        }
    }

    return unless($ret);
    my @recs = (ref($ret) ne 'CIF::Archive') ? reverse($ret->slice(0,$ret->count())) : ($ret);
    my @rr;
    foreach (@recs){
        # protect against orphans
        next unless($_->{'data'});
        my $e = $db_codec->decode_event($_->{'data'});

        push(@rr,$e);
    }

    return(undef,\@rr);
}

sub hash_querystring {
    my $class = shift;
    my $querystring = shift;
    if ($querystring =~ /^([a-f0-9]{40}|[a-f0-9]{32})$/i) {
      return lc($querystring);
    }
    return lc(sha1_hex(lc($querystring))); 
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


#__PACKAGE__->set_sql('insert_into_archive' => qq{
#INSERT INTO archive (uuid, guid, format, data, created, reporttime)
#VALUES (?, ?, ?, ?, to_timestamp(?), to_timestamp(?)) RETURNING id
#});
__PACKAGE__->set_sql('get_guid_id' => qq{
  SELECT id FROM archive_guid_map WHERE guid = ?
  });
__PACKAGE__->set_sql('insert_guid' => qq{
INSERT INTO archive_guid_map (guid)
VALUES (?) RETURNING id
});

__PACKAGE__->set_sql('insert_into_archive' => qq{
INSERT INTO archive (data,guid_id,created,reporttime)
VALUES (?, ?, to_timestamp(?), to_timestamp(?)) RETURNING id
});

__PACKAGE__->set_sql('insert_into_archive_asn' => qq{
INSERT INTO archive_asn (asn, archive_id, created, reporttime)
VALUES (?, ?, to_timestamp(?), to_timestamp(?))
});

__PACKAGE__->set_sql('insert_into_archive_cidr' => qq{
INSERT INTO archive_cidr (cidr, archive_id, created, reporttime)
VALUES (?, ?, to_timestamp(?), to_timestamp(?))
});

__PACKAGE__->set_sql('insert_into_archive_email' => qq{
INSERT INTO archive_email (email, archive_id, created, reporttime)
VALUES (?, ?, to_timestamp(?), to_timestamp(?))
});

__PACKAGE__->set_sql('insert_into_archive_fqdn' => qq{
INSERT INTO archive_fqdn (fqdn, archive_id, created, reporttime)
VALUES (?, ?, to_timestamp(?), to_timestamp(?))
});

__PACKAGE__->set_sql('insert_into_archive_ip' => qq{
INSERT INTO archive_ip (ip, archive_id, created, reporttime)
VALUES (?, ?, to_timestamp(?), to_timestamp(?))
});

__PACKAGE__->set_sql('insert_into_archive_url' => qq{
INSERT INTO archive_url (url, archive_id, created, reporttime)
VALUES (?, ?, to_timestamp(?), to_timestamp(?))
});


1;
