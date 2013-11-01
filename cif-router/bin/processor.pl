#!/usr/bin/perl

use strict;
use warnings;

# fix lib paths, some may be relative
BEGIN {
    require File::Spec;
    my @libs = (
        "lib", 
        "local/lib",
        
        # dev mode stuff
        '../libcif/lib',
        '../libcif-dbi/lib',
        '../libcif-dbi-asn/lib',
        '../libcif-dbi-cc/lib',
        '../libcif-dbi-rir/lib',
    );
    my $bin_path;

    for my $lib (@libs) {
        unless ( File::Spec->file_name_is_absolute($lib) ) {
            unless ($bin_path) {
                if ( File::Spec->file_name_is_absolute(__FILE__) ) {
                    $bin_path = ( File::Spec->splitpath(__FILE__) )[1];
                }
                else {
                    require FindBin;
                    no warnings "once";
                    $bin_path = $FindBin::Bin;
                }
            }
            $lib = File::Spec->catfile( $bin_path, File::Spec->updir, $lib );
        }
        unshift @INC, $lib;
    }
}

use Getopt::Long;
use CIF::Router::Server;
use Pod::Usage;
use CIF qw/debug/;

my $help;
my $man;
my $config = $ENV{'HOME'}.'/.cif';

Getopt::Long::Configure ("bundling");
GetOptions(
  'help|?|h' => \$help, 
  'man' => \$man,
  'config|C=s' => \$config,
) or pod2usage(2);

pod2usage(1) if $help;
pod2usage(-exitval =>0, -verbose => 2) if $man;

if ($#ARGV > 0) {
  warn "ERROR: Only one mode may be specified.";
  pod2usage(2);
} elsif ($#ARGV == -1) {
  warn "ERROR: A mode must be specified.";
  pod2usage(2);
}

my $mode = shift(@ARGV);

my $server_type;
if ($mode eq 'submit') {
  $server_type = CIF::Router::Transport->SUBMISSION;
} elsif ($mode eq 'query') {
  $server_type = CIF::Router::Transport->QUERY;
} else {
  warn "ERROR: Unknown mode: $mode";
  pod2usage(2);
}

my $server = CIF::Router::Server->new($server_type, $config);

$SIG{INT} = sub {
  debug("Caught interrupt. Shutting down.");
  $server->shutdown();
};
print "Running. Ctrl-C or SIGINT to shutdown.\n";
$server->run();
# Doesn't return!
debug("All done!");

__END__

=head1 NAME

=head1 SYNOPSIS

processor.pl [OPTION] MODE
 
 MODE:
    submit                  Starts a submission server
    query                   Starts a query server

 Options:
    -C, --config=FILE       specify cofiguration file, default: ~/.cif 
    -h, -?, --help          this message
    --man                   detailed documentation        

 Examples:
    processor.pl query
    processor.pl submit
    processor.pl -C /path/to/cif.conf submit

=head1 DESCRIPTION

=over 8

=item B<MODE>

    Either 'submit' or 'query'

=item B<-C>, B<--config CONFIG_FILE>

    Specify the path to the cif.conf. Defaults to ~/.cif

=item B<--help>

    Print out brief help message.

=item B<--man>

    Print out detailed documentation.


=back

=cut

