#!/usr/bin/perl

use strict;
use warnings;

# this just sets up the lib paths for apache

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

require CIF::Router::RabbitMQSTOMP;
use Data::Dumper;
use CIF qw/init_logging/;


my $stomp = CIF::Router::RabbitMQSTOMP->new(
  "cif-query-processor", "/topic/cif-query", 0);
print "Started\n";
$stomp->run();





1;

