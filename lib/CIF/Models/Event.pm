package CIF::Models::Event;
use strict;
use warnings;
use Scalar::Util qw(blessed);
use Data::Dumper;
use CIF qw(generate_uuid_random);
require JSON;
#use Tie::Hash;
#our @ISA = 'Tie::StdHash';

use constant FIELDS => {
  address => 1,
  address_mask => 1,
  alternativeid => 1,
  alternativeid_restriction => 1,
  assessment => 1,
  carboncopy => 1,
  confidence => 1,
  contact => 1,
  contact_email => 1,
  description => 1,
  detecttime => 1,
  guid => 1,
  hash => 1,
  id => 1,
  lang => 1,
  malware_md5 => 1,
  malware_sha1 => 1,
  md5 => 1,
  method => 1,
  portlist => 1,
  protocol => 1,
  purpose => 1,
  relatedid => 1,
  reporttime => 1,
  restriction => 1,
  severity => 1,
  sha1 => 1,
  source => 1,
  timezone => 1,
  timestamp_epoch => 1
};

sub new {
  my $class = shift;
  my $guid = shift;
  my $data = shift || {};
  my $self = {};
  #tie %{$self}, $class;
  map { $self->{$_} = $data->{$_} } keys %{$data};
  $self->{guid} = $guid;
  if (!defined($self->{id})) {
    $self->{id} = generate_uuid_random();
  }
  bless $self, $class;
  return $self;
}

sub guid {
  my $self = shift;
  return $self->{guid};
}

sub to_json {
  my $self = shift;
  my $data = {};
  foreach my $key (keys %$self) {
    $data->{$key} = $self->{$key};
  }
  return JSON::encode_json($data);
}

sub from_json {
  my $class = shift;
  my $data = JSON::decode_json(shift);

  return($class->new($data));
}


1;
