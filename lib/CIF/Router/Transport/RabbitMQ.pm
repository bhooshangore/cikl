package CIF::Router::Transport::RabbitMQ;

use strict;
use warnings;

use CIF::Router::Transport;
use Mouse;
use AnyEvent;
use Coro;
use Try::Tiny;
use CIF qw/debug/;
use CIF::Router::Constants;
use CIF::Common::RabbitMQRole;
use namespace::autoclean;

with 'CIF::Router::Transport';
with 'CIF::Common::RabbitMQRole';

has 'prefetch_count' => (
  is => 'ro',
  isa => 'Num',
  builder => sub { $_[0]->{prefetch_count} || 500 }
);

has 'query_queue' => (
  is => 'ro',
  isa => 'Str',
  default => 'query-queue'
);

has 'submit_queue' => (
  is => 'ro',
  isa => 'Str',
  default => 'submit-queue'
);

has 'channels' => (
  is => 'ro',
  isa => 'ArrayRef',
  lazy_build => 1,
  traits => [ 'Array' ],
  init_arg => undef,
);

sub _build_channels {
  return [];
}

sub register_service {
  my $self = shift;
  my $service = shift;
  my $service_type = $service->service_type();

  my $config = undef;
  if ($service_type == CIF::Router::Constants::SVC_SUBMISSION) {
    $config = $self->_submission_service_config();
  } elsif ($service_type == CIF::Router::Constants::SVC_QUERY) {
    $config = $self->_query_service_config();
  } elsif ($service_type == CIF::Router::Constants::SVC_CONTROL) {
    $config = $self->_control_service_config();
  } else {
    die "Unknown service type: $service_type";
  }
  $self->_setup_processor($config, $service);
}

sub _query_service_config {
  my $self = shift;
  return {
    exchange_name => $self->query_exchange,
    exchange_type => "topic",
    queue_name => $self->query_queue,
    routing_key =>  $self->query_key,
    durable => 0,
    auto_delete => 1
  };
}

sub _submission_service_config {
  my $self = shift;
  return {
    exchange_name => $self->submit_exchange,
    exchange_type => "topic",
    queue_name => $self->submit_queue,
    routing_key =>  $self->submit_key,
    durable => 1,
    auto_delete => 0
  };
}

sub _control_service_config {
  my $self = shift;
  return {
    exchange_name => $self->control_exchange,
    exchange_type => "fanout",
    queue_name => "",
    routing_key =>  $self->control_key,
    durable => 0,
    auto_delete => 1
  };
}
sub _init_channel {
  my $self = shift;
  my $channel = $self->amqp->open_channel();
  my $config = shift;
  my $service = shift;

  $channel->declare_exchange(
    exchange => $config->{exchange_name},
    type => $config->{exchange_type},
    durable => 1,
    auto_delete => 0
  );
  $channel->qos(prefetch_count => $self->prefetch_count);
  my $acker = CIF::Router::Transport::RabbitMQ::DeferredAcker->new(
    channel => $channel,
    max_outstanding => $self->prefetch_count,
    timeout => 1
  );

  $self->_init_queue($channel, $config);
  $self->_init_consume($channel, $service, $acker);

  return $channel;
}

sub _init_consume {
  my $self = shift;
  my $channel = shift;
  my $service = shift;
  my $acker = shift;
  $channel->consume(
    no_ack => 0,
    on_consume => sub {
      $self->_handle_msg($channel, $_[0], $service, $acker);
    }
  );
}

sub _handle_msg {
  my $self = shift;
  my $channel = shift;
  my $msg = shift;
  my $service = shift;
  my $acker = shift;

  my $payload = $msg->{body}->payload;
  my ($reply, $type, $content_type, $err);

  try {
    ($reply, $type, $content_type) = $service->process($payload);
  } catch {
    $err = shift;
  };

  if ($err) {
    $reply = "Error while processing message: $err";
    $type = "error";
    $content_type = "text/plain";
    debug($reply);
    $acker->reject($msg->{deliver}->method_frame->delivery_tag);
  } else {
    $acker->ack($msg->{deliver}->method_frame->delivery_tag);
  }

  if (my $reply_queue = $msg->{header}->{reply_to}) {
    $channel->publish(
      # Note that we don't specify an exchange when replying.
      exchange => '',
      routing_key => $reply_queue,
      body => $reply,
      header => {
        content_type => $content_type,
        correlation_id => $msg->{header}->{correlation_id},
        type => $type 
      }
    );
  }
}

sub _init_queue {
  my $self = shift;
  my $channel = shift;
  my $config = shift;

  my $result = $channel->declare_queue(
    queue => $config->{queue_name},
    durable => $config->{durable},
    auto_delete => $config->{auto_delete}
  );

  $channel->bind_queue(
    exchange => $config->{exchange_name},
    queue => $config->{queue_name},
    routing_key => $config->{routing_key}
  );
}

sub _setup_processor {
  my $self = shift;
  my $config = shift;
  my $service = shift;
  my $channel = $self->_init_channel($config, $service, "process");
  push(@{$self->channels()}, $channel); 

  return undef;
}

sub start {
  my $self = shift;
  if (($#{$self->channels} == -1)) {
    die "Nothing to start! No services have been registered!";
  }
}

sub stop {
  # doesn't need to do anything. If AnyEvent isn't looping, we're stopped.
}

# This gets called before shutdown.
sub shutdown {
  my $self = shift;

  if (!$self->has_amqp()) {
    return;
  }
  debug("Shutting down");

  foreach my $channel (@{$self->channels}) {
    $channel->close();
  }
  # Clear the closed channels;
  $self->clear_channels();
  $self->amqp->close();
  $self->clear_amqp();
}

__PACKAGE__->meta->make_immutable();

package CIF::Router::Transport::RabbitMQ::DeferredAcker;
use strict;
use warnings;

use Mouse;
use namespace::autoclean;
use CIF qw/debug/;

has 'channel' => (
  is => 'ro',
  #isa => ???,
  required => 1
);

has 'max_outstanding' => (
  is => 'ro',
  isa => 'Int',
  required => 1
);

has 'timeout' => (
  is => 'ro',
  isa => 'Num',
  required => 1
);

has '_counter' => (
  traits  => ['Counter'],
  is => 'rw',
  isa => 'Int',
  init_arg => undef,
  default => 0,
  handles => {
    inc_counter   => 'inc',
    reset_counter => 'reset',
  }
);

has '_last_tag' => (
  is => 'rw',
  init_arg => undef
);

has '_timer' => (
  is => 'rw',
  init_arg => undef

);

sub ack {
  my $self = shift;
  $self->_last_tag(shift);
  $self->inc_counter();
  if ($self->_counter >= $self->max_outstanding()) {
    # Flush after X messages.
    $self->flush();
  } elsif (!defined($self->_timer)) {
    # Create timer that will flush for us.
    $self->_timer(AnyEvent->timer(
        after => $self->timeout, 
        cb => sub {$self->flush();}
      ));
  }
};

sub reject {
  my $self = shift;
  my $tag = shift;
  $self->flush();
  $self->channel->reject(delivery_tag => $tag);
}

sub flush {
  my $self = shift;
  $self->_timer(undef);
  $self->reset_counter();
  my $last_tag = $self->_last_tag;
  return if (!defined($last_tag));
  $self->channel->ack(delivery_tag => $last_tag, multiple => 1);
  $self->_last_tag(undef);
}

__PACKAGE__->meta->make_immutable();

1;


