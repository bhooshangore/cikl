package CIF::Models::Event;
use strict;
use warnings;
use Mouse;
use Mouse::Util::TypeConstraints;
use CIF::DataTypes;
use CIF::Models::AddressRole;
use CIF::AddressBuilder qw/create_address/;
use namespace::autoclean;

has 'group' => (
  is => 'rw',
  isa => 'CIF::DataTypes::LowerCaseStr',
  required => 1,
);

has 'assessment' => (
  is => 'rw',
  isa => 'CIF::DataTypes::LowerCaseStr',
  required => 1,
  coerce => 1
);

has 'description' => (
  is => 'rw',
  isa => 'CIF::DataTypes::LowerCaseStr',
  default => sub { 'unknown' },
  coerce => 1
);

has 'address' => (
  is => 'rw',
  does => 'CIF::Models::AddressRole'
);

has 'detecttime' => (
  is => 'rw',
  isa => "CIF::DataTypes::Integer",
  coerce => 1
);

has 'reporttime' => (
  is => 'rw',
  isa => "CIF::DataTypes::Integer",
  coerce => 1
);

has 'alternativeid' => (is => 'rw');
has 'alternativeid_restriction' => (is => 'rw');
has 'confidence' => (
  is => 'rw', 
  isa => 'CIF::DataTypes::Integer', 
  coerce => 1
);
has 'hash' => (is => 'rw');

has 'malware_md5' => (is => 'rw');
has 'malware_sha1' => (is => 'rw');
has 'md5' => (is => 'rw');
has 'sha1' => (is => 'rw');

has 'portlist' => (
  is => 'rw',
  isa => 'CIF::DataTypes::PortList'
);

has 'protocol' => (is => 'rw');
has 'restriction' => (is => 'rw');
has 'severity' => (is => 'rw');
has 'source' => (is => 'rw');

has 'cc' => (is => 'rw');
has 'rir' => (is => 'rw');

sub to_hash {
  my $ret = { %{$_[0]} };
  if ($ret->{address}) {
    $ret->{address} = $ret->{address}->to_hash();
  }
  return $ret;
}

sub from_hash {
  my $class = shift;
  my $data = shift;
  my $address = $data->{address};
  if ($address) {
    my $type = (keys %$address)[0];
    if ($type) {
      $address = create_address($type, $address->{$type});
      $data->{address} = $address;
    }
  }
  return $class->new($data);
}

__PACKAGE__->meta->make_immutable;

1;
