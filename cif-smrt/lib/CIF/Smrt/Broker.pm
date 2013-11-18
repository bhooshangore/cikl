package CIF::Smrt::Broker;
use strict;
use warnings;
use Moose;
use namespace::autoclean;

has 'emit_cb' => (
  is => 'bare',
  isa => 'CodeRef',
  reader => '_emit_cb',
  required => 1
);

has 'builder' => (
  is => 'bare',
  isa => 'CIF::EventBuilder',
  reader => '_builder',
  required => 1
);

has 'count' => (
  is => 'ro',
  isa => 'Num',
  writer => '_set_count',
  required => 1,
  default => 0,
  init_arg => undef
);

has 'count_too_old' => (
  is => 'ro',
  isa => 'Num',
  writer => '_set_count_too_old',
  required => 1,
  default => 0,
  init_arg => undef
);

sub emit {
  my $self = shift;
  my $event_hash = shift;
  my $event = $self->_builder->build_event($event_hash);
  if (defined($event)) {
    $self->_set_count($self->count() + 1);
    $self->_emit_cb->($event);
  } else {
    $self->_set_count_too_old($self->count_too_old() + 1);
    # It was too old.
  }
}

__PACKAGE__->meta->make_immutable;

1;
