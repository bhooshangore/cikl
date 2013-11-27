package CIF::Models::Address::asn;
use strict;
use warnings;
use Moose;
use CIF::Models::AddressRole;
use CIF::MooseTypes;
use namespace::autoclean;
with 'CIF::Models::AddressRole';

sub type { 'asn' }

has '+value' => (
  isa => 'CIF::MooseTypes::Asn',
);

__PACKAGE__->meta->make_immutable;
1;


