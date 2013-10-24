package CIF::Archive::Hash;
use base 'CIF::DBI';

use strict;
use warnings;

use Module::Pluggable require => 1, search_path => [__PACKAGE__];
use Iodef::Pb::Simple qw(iodef_confidence iodef_additional_data iodef_guid);
use CIF qw/debug/;

# work-around for cif-v1
use Regexp::Common qw/net/;
use Digest::SHA qw(sha1_hex);

my @plugins = __PACKAGE__->plugins();

__PACKAGE__->table('hash');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(All => qw/id uuid guid hash confidence reporttime created/);
__PACKAGE__->sequence('hash_id_seq');
__PACKAGE__->has_a(uuid => 'CIF::Archive');
__PACKAGE__->add_trigger(after_delete => \&trigger_after_delete);

sub trigger_after_delete {
    my $class = shift;
     
    my $archive = CIF::Archive->retrieve(uuid => $class->uuid());
    $archive->delete() if($archive);
}

sub prepare {}

sub insert {
    my $class   = shift;
    my $data    = shift;
    my $confidence;
    my @ids;
    my $tbl = $class->table();

    # we're explicitly placing a hash
    if($data->{'hash'}){
        debug("Inserting hash");
        $confidence = $data->{'confidence'};
        
        if(my $t = return_table($data->{'hash'})){
            $class->table($t);
        }
        my $id = $class->SUPER::insert({
            hash        => $data->{'hash'},
            uuid        => $data->{'uuid'},
            guid        => $data->{'guid'},
            confidence  => $confidence,
            reporttime  => $data->{'reporttime'},
        });
        push(@ids,$id);
    } elsif(ref($data->{'data'}) eq 'IODEFDocumentType') {
        foreach my $i (@{$data->{'data'}->get_Incident()}){
            $confidence = iodef_confidence($i);
            $confidence = @{$confidence}[0]->get_content();
         
            # for now, we expect all hashes to be sent in
            # under Incident.AdditionalData
            # we can improve this in the future
            my $ad = iodef_additional_data($i);
            return unless($ad);
            
            my @ids;
            foreach my $a (@$ad){
                next unless($a->get_meaning() && lc($a->get_meaning()) =~ /^(md5|sha(\d+)|uuid|hash)$/);
                next unless($a->get_content());
                my $hash = $a->get_content();
                if(my $t = return_table($hash)){
                    $class->table($t);
                }
                debug("Inserting something other than a hash");
                my $id = $class->SUPER::insert({
                    hash        => $hash,
                    uuid        => $data->{'uuid'},
                    guid        => $data->{'guid'},
                    confidence  => $confidence,
                    reporttime  => $data->{'reporttime'},
                });
                push(@ids,$id);
            }
        }
    }
    $class->table($tbl);
    return(undef,\@ids); 
}

sub return_table {
    my $hash = shift;
    foreach (@plugins){
        next unless($_->prepare($hash));
        return $_->table();
        last;
    }
}

sub query {
    my $class   = shift;
    my $data    = shift;
    foreach (@plugins){
        my $r = $_->query($data);
        return ($r) if($r && $r->count());
    }
    return;
}

sub purge_hashes {
    my $self    = shift;
    my $args    = shift;
    
    my $ts = $args->{'timestamp'};
    
    debug('purging...');
    my $ret = $self->sql_purge_hashes->execute($ts);
    unless($ret){
        debug('error, rolling back...');
        $self->dbi_rollback();
        return;
    }
    $ret = $self->sql_purge_archive->execute($ts);
    debug('commit...');
    $self->dbi_commit();
    
    debug('done...');
    return (undef,$ret);
}

__PACKAGE__->set_sql('purge_archive'    => qq{
    DELETE FROM archive
    WHERE reporttime <= ?
});

__PACKAGE__->set_sql('purge_hashes' => qq{
    DELETE FROM __TABLE__
    WHERE reporttime <= ?
});

__PACKAGE__->set_sql('lookup' => qq{
    SELECT t1.id,t1.uuid,archive.data
    FROM (
        SELECT t2.id, t2.hash, t2.uuid, t2.guid
        FROM hash_sha1 t2
        LEFT JOIN apikeys_groups on t2.guid = apikeys_groups.guid
        WHERE
            hash = ?
            AND confidence >= ?
            AND apikeys_groups.uuid = ?
        ORDER BY t2.id DESC
        LIMIT ?
    ) t1
    LEFT JOIN archive ON archive.uuid = t1.uuid
    WHERE 
        archive.uuid IS NOT NULL
});


1;
