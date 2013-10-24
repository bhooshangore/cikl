package CIF::Archive::Plugin::Cc;
use base 'CIF::Archive::Plugin';

use strict;
use warnings;

use Module::Pluggable require => 1, search_path => [__PACKAGE__];
use Try::Tiny;
use Iodef::Pb::Simple qw(iodef_confidence iodef_bgp);

my @plugins = __PACKAGE__->plugins();

use constant DATATYPE => 'cc';
sub datatype { return DATATYPE; }

sub query { } # handled by the address module

sub insert {
    my $class = shift;
    my $data = shift;
    
    return unless($class->test_datatype($data));
    return unless(ref($data->{'data'}) eq 'IODEFDocumentType');

    my $tbl = $class->table();
    my @ids;
 
    foreach my $i (@{$data->{'data'}->get_Incident()}){
        foreach(@plugins){
            if($_->prepare($i)){
                $class->table($class->sub_table($_));
                last;
            }
        }

        my $uuid = $i->get_IncidentID->get_content();
        
        my $bgp = iodef_bgp($i);
        next unless($bgp);
        my $confidence = iodef_confidence($i);
        $confidence = @{$confidence}[0]->get_content();
        
        foreach my $e (@$bgp){
            next unless($e->{'cc'} && $e->{'cc'} =~ /^[a-zA-Z]{2}$/);
            $e->{'cc'} = lc($e->{'cc'});
            my $id = $class->insert_hash({ 
                uuid        => $data->{'uuid'}, 
                guid        => $data->{'guid'}, 
                confidence  => $confidence,
                reporttime  => $data->{'reporttime'},
            },$e->{'cc'});
        
            push(@ids,$id);
        }
    }
    $class->table($tbl);
    return(undef,\@ids);
}

1;
