package CIF::Router::Server;

use strict;
use warnings;
use AnyEvent;
use Coro;
use Coro::AnyEvent;
use CIF::Router::Transport;
use CIF::Router::ServiceRole;
use Config::Simple;
use Mouse;
use namespace::autoclean;

use CIF qw/debug init_logging generate_uuid_ns/;

has 'service' => (
  is => 'ro',
  isa => 'CIF::Router::ServiceRole',
  required => 1
);

has 'control_service' => (
  is => 'ro',
  isa => 'CIF::Router::Services::Control',
  required => 1
);

has 'transport' => (
  is => 'ro',
  isa => 'CIF::Router::Transport',
  required => 1,
);

has 'config' => (
  is => 'ro',
  isa => 'Config::Simple',
  required => 1
);

has 'starttime' => (
  is => 'ro',
  isa => 'Num',
  init_arg => undef,
  default => sub {time()}
);

sub run {
  my $self = shift;

  $self->transport->start();

  $self->{cv} = AnyEvent->condvar;

  my $thr = async {
    $self->{cv}->recv();
    $self->{cv} = undef;
  };

  while ( defined( $self->{cv} ) ) {
    Coro::AnyEvent::sleep 1;
  }

  $self->transport->stop();
}

sub stop {
  my $self = shift;
  if (my $cv = $self->{cv}) {
    debug("Stopping");
    $cv->send(undef);
  }
}

sub shutdown {
  my $self = shift;
  $self->service->shutdown();
  $self->control_service->shutdown();
  $self->transport->shutdown();
}

__PACKAGE__->meta->make_immutable();
1;
