package CIF::Router::Service;

use strict;
use warnings;
use CIF::Models::HostInfo;
use Sys::Hostname;
use Try::Tiny;
use CIF qw/debug/;
use CIF::Router::Constants;

sub new {
  my $class = shift;
  my $router = shift;
  my $encoder = shift;

  my $self = {
    starttime => time(),
    encoder => $encoder,
    router => $router
  };

  bless $self, $class;

  return $self;
}

sub service_type {
  my $class = shift;
  die("$class has not implemented name()");
}

# Should return 1 or 0
sub queue_should_autodelete {
  my $class = shift;
  die("$class has not implemented queue_should_autodelete()");
}

# Should return 1 or 0
sub queue_is_durable {
  my $class = shift;
  die("$class has not implemented queue_is_durable()");
}

# Should return 1 or 0
sub service_requests_are_broadcast {
  my $class = shift;
  die("$class has not implemented service_requests_are_broadcast()");
}

sub name {
  my $class = shift;
  return SVCNAMES->{$class->service_type()};
}

sub router {
  return $_[0]->{router};
}

sub encoder {
  return $_[0]->{encoder};
}

sub uptime {
  my $self = shift;
  return time() - $self->{starttime};
}

sub process_hostinfo_request {
  my $self = shift;
  my $payload = shift;
  my ($remote_hostinfo, $response, $encoded_response);
  try {
    $remote_hostinfo = $self->{encoder}->decode_hostinfo($payload);
    debug("Got ping: " . $remote_hostinfo->to_string());
    $response = CIF::Models::HostInfo->generate({uptime => $self->uptime(),
        service_type => $self->name()
      });
    $encoded_response = $self->{encoder}->encode_hostinfo($response);
  } catch {
    my $err = shift;
    debug("Got an error: $err");
    return($err, "ping_error", 'text/plain');
  };
  return($encoded_response, "pong", $self->{encoder}->content_type());
}

1;
