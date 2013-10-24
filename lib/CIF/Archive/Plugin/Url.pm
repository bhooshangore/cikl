package CIF::Archive::Plugin::Url;
use base 'CIF::Archive::Plugin';

use strict;
use warnings;

use Module::Pluggable require => 1, search_path => [__PACKAGE__];
use Iodef::Pb::Simple qw(:all);
use CIF qw/debug/;

my @plugins = __PACKAGE__->plugins();

use constant DATATYPE => 'url';
sub datatype { return DATATYPE; }

__PACKAGE__->table('url');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(All => qw/id uuid guid hash confidence reporttime created/);
__PACKAGE__->sequence('url_id_seq');

sub query { } # handled by hash lookup

sub insert {
    my $class   = shift;
    my $data    = shift;
    
    return unless(ref($data->{'data'}) eq 'IODEFDocumentType');
     
    my $addresses = iodef_addresses($data->{'data'});
    return unless(@$addresses);
    
    my $tbl = $class->table();
    my @ids;
    foreach my $i (@{$data->{'data'}->get_Incident()}){
        foreach(@plugins){
            if($_->prepare($i)){
                $class->table($_->table());
            }
        }
        my $reporttime = $i->get_ReportTime();
        my $confidence = iodef_confidence($i);
        $confidence = @{$confidence}[0]->get_content();   
        
        foreach my $address (@$addresses){
            my $addr = lc($address->get_content());
            next unless($addr =~ /^(ftp|https?):\/\//);
            ## TODO -- pull this out of the IODEF ?
            my $hash = generate_sha1_if_needed($addr);
            if($class->test_feed($data)){
                $class->SUPER::insert({
                    guid        => iodef_guid($i) || $data->{'guid'},
                    uuid        => $i->get_IncidentID->get_content(),
                    hash        => $hash,
                    confidence  => $confidence,
                    reporttime  => $reporttime,
                });
            }
            
            my $id = $class->insert_hash({ 
                    uuid        => $data->{'uuid'}, 
                    guid        => $data->{'guid'}, 
                    confidence  => $confidence,
                    reporttime  => $reporttime,
                },$addr);
            push(@ids,$id);
        }
    }
    $class->table($tbl);
    return(undef,\@ids);
}

1;
