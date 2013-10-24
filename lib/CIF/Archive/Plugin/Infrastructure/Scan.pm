package CIF::Archive::Plugin::Infrastructure::Scan;
use base 'CIF::Archive::Plugin::Infrastructure';

use strict;
use warnings;

use Iodef::Pb::Simple qw(iodef_impacts);

__PACKAGE__->table('infrastructure_scan');

use constant EVENT_REGEX => qr/^scan(?:(ning|ner))/;

sub assessment_regex {
  return EVENT_REGEX;;
}

sub prepare {
    my $class = shift;
    my $data = shift;
    
    my $impacts = iodef_impacts($data);
    foreach (@$impacts){
        return 1 if(lc($_->get_content->get_content()) =~ /^scan(?:(ning|ner))/);
    }
    return(0);
}

1;
