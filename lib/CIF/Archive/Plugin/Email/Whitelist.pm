package CIF::Archive::Plugin::Email::Whitelist;
use base 'CIF::Archive::Plugin::Email';

use strict;
use warnings;

use Iodef::Pb::Simple qw(iodef_impacts);

__PACKAGE__->table('email_whitelist');

use constant EVENT_REGEX => qr/whitelist/;

sub assessment_regex {
  return EVENT_REGEX;;
}

sub prepare {
    my $class = shift;
    my $data = shift;
    
    my $impacts = iodef_impacts($data);
    foreach (@$impacts){
        return 1 if($_->get_content->get_content() =~ /whitelist/);
    }
    return(0);
}

1;
