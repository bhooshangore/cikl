package CIF::EventBuilder;
use strict;
use warnings;
use CIF::Models::Event;
use Moose;
use namespace::autoclean;
use Try::Tiny;
use DateTime;
use CIF qw/normalize_timestamp debug/;
use Module::Pluggable search_path => "CIF::EventNormalizers", 
      require => 1, sub_name => '__preprocessors';

has 'default_event_data' => (
  is => 'rw',
  isa => 'HashRef',
  required => 1,
  default => sub { return {}; }
);

has 'refresh' => (
  is => 'rw',
  isa => 'Bool',
  default => 0,
  required => 1
);

has 'not_before' => (
  is => 'rw', 
  isa => 'DateTime',
  required => 1,
  default => sub {
    return DateTime->now()->subtract(days => 3);
  }
);

has '_now' => (
  is => 'ro', 
  default => sub { DateTime->from_epoch(epoch => time()) },
  init_arg => undef
);

has '_preprocessors' => (
  traits => ['Array'],
  is => 'ro', 
  isa => 'ArrayRef[Str]',
  default => sub { [__preprocessors()]; },
  init_arg => undef
);

sub merge_default_event_data {
  my $self = shift;
  my $data_to_merge = shift;
  my $merged_data = {%{$self->default_event_data}, %$data_to_merge};
  $self->default_event_data($merged_data);
}

sub normalize {
  my $self = shift;
  my $r = shift;

  my $now  = $self->_now;
  my $dt = $r->{'detecttime'} || $now;
  my $rt = $r->{'reporttime'} || $now;
  $rt = $now if($self->refresh);
    
  $dt = normalize_timestamp($dt,$now);
  $rt = normalize_timestamp($rt,$now);

  if(DateTime->compare($dt, $self->not_before) == -1) {
    return(undef);
  }

  $r->{'detecttime'}        = $dt->epoch();
  $r->{'reporttime'}        = $rt->epoch();

  $r->{addresses} ||= [];

  my $addresses = $r->{addresses};
  
  if (my $fqdn = delete($r->{fqdn})) {
    push(@$addresses, CIF::Models::Address->new(type => 'fqdn', value => $fqdn));
    $r->{address} = $r->{address} // $fqdn;
  };
  if (my $ipv4 = delete($r->{ipv4})) {
    push(@$addresses, CIF::Models::Address->new(type => 'ipv4', value => $ipv4));
    $r->{address} = $r->{address} // $ipv4;
  }
  if (my $ipv4_cidr = delete($r->{ipv4_cidr})) {
    push(@$addresses, CIF::Models::Address->new(type => 'ipv4_cidr', value => $ipv4_cidr));
    $r->{address} = $r->{address} // $ipv4_cidr;
  }
  if (my $url = delete($r->{url})) {
    push(@$addresses, CIF::Models::Address->new(type => 'url', value => $url));
    $r->{address} = $r->{address} // $url;
  }
  if (my $email = delete($r->{email})) {
    push(@$addresses, CIF::Models::Address->new(type => 'email', value => $email));
    $r->{address} = $r->{address} // $email;
  }
  if (my $asn = delete($r->{asn})) {
    push(@$addresses, CIF::Models::Address->new(type => 'asn', value => $asn));
    $r->{address} = $r->{address} // $asn;
  }

  # MPR: Disabling value expansion, for now.
#  foreach my $key (keys %$r){
#    my $v = $r->{$key};
#    next unless($v);
#    if($v =~ /<(\S+)>/){
#      my $value_to_expand = $1;
#      my $x = $r->{$value_to_expand};
#      if($x){
#        $r->{$key} =~ s/<\S+>/$x/;
#      }
#    }
#  }
  foreach my $p (@{$self->_preprocessors}){
    $r = $p->process($r);
  }

  return $r;
}

sub build_event {
  my $self = shift;
  my $hashref = shift;
  if (!defined($hashref)) {
    die("build_event requires a hashref of arguments!");
  }
  my $merged_hash = {%{$self->default_event_data}, %$hashref};
  my $normalized = $self->normalize($merged_hash);
  if (!defined($normalized)) {
    return undef;
  }

  my $event;
  my $err;
  try {
    $event = CIF::Models::Event->new($normalized);
  } catch {
    $err = shift;
  };
  if ($err) {
    die("Failed to build event. Likely missing a required field: $err");
  }
  return $event;
}

__PACKAGE__->meta->make_immutable;

1;

