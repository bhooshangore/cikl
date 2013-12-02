package CIF::Models::AddressRole;
use strict;
use warnings;
use Moose::Role;
use namespace::autoclean;

requires 'type';

has 'value' => (
  is => 'rw',
  isa => 'Str',
  required => 1
);

sub as_string {
  my $self = shift;
  return $self->value;
}

sub normalize_value {
  my $class = shift;
  return shift;
}

sub new_normalized {
  my $class = shift;
  my %args = @_;
  $args{value} = $class->normalize_value($args{value});
  $class->new(%args);
}


1;
