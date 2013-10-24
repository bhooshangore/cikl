package CIF::Archive::Plugin::Infrastructure::Spam;
use base 'CIF::Archive::Plugin::Infrastructure';

use strict;
use warnings;

use Iodef::Pb::Simple qw(iodef_impacts);

__PACKAGE__->table('infrastructure_spam');

use constant EVENT_REGEX => qr/^spam$/;

sub assessment_regex {
  return EVENT_REGEX;;
}

sub prepare {
    my $class = shift;
    my $data = shift;

    my $impacts = iodef_impacts($data);
    foreach (@$impacts){
        return 1 if($_->get_content->get_content() =~ /^spam$/);
    }
    return(0);
}

1;
