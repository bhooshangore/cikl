package CIF::Router::Server;

use strict;
use warnings;
use AnyEvent;
use Coro;
use CIF::Router::Transport;
use Config::Simple;
use CIF::Router;
use Try::Tiny;
use CIF::Encoder::JSON;
use Sys::Hostname;
use CIF::Router::Services::Query;
use CIF::Router::Services::Submission;
use CIF::Router::Constants;
use CIF::Router::Services;

use CIF qw/debug init_logging/;

sub new {
    my $class = shift;
    my $type = shift;
    my $config = shift;

    my $self = {};
    bless($self,$class);

    $self->{starttime} = time();
    $self->{type} = $type;
    my $services = CIF::Router::Services->new();
    my $service_class = $services->lookup($type);
    if (!defined($service_class)) {
      die("Unknown service type: $type");
    }
    $self->{service_class} = $service_class;

    $self->{config} = Config::Simple->new($config) || die("Could not load config file: '$config'");
    $self->{server_config} = $self->{config}->param(-block => 'router_server');

    $self->{encoder} = CIF::Encoder::JSON->new();

    init_logging($self->{server_config}->{'debug'} || 0);

    # Initialize the router.
    my ($err,$router) = CIF::Router->new({
        config  => $self->{config},
      });
    if($err){
      ## TODO -- set debugging variable
      die $err;
    }

    $self->{router} = $router;

    my $driver_name = $self->{server_config}->{driver} || "RabbitMQ";
    my $driver_config = $self->{config}->param(-block => ('router_server_' . lc($driver_name)));
    my $driver_class = "CIF::Router::Transport::" . $driver_name;

    $self->{commit_interval} = $self->{server_config}->{commit_interval} || 2;


    $self->{service} = $service_class->new($self->{router}, $self->{encoder});
    my $driver;
    try {
      $driver = $driver_class->new($driver_config, $self->{service});
    } catch {
      $err = shift;
      die "Driver ($driver_class) failed to load: $err";
    };

    $self->{driver} = $driver;

    return($self);
}

sub run {
    my $self = shift;

    $self->{driver}->start();

    $self->{cv} = AnyEvent->condvar;

    my $thr = async {
      $self->{cv}->recv();
      $self->{cv} = undef;
    };

    while ( defined( $self->{cv} ) ) {
      Coro::AnyEvent::sleep 1;
    }

    $self->{driver}->stop();
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

    if ($self->{driver}) {
      $self->{driver}->shutdown();
      $self->{driver} = undef;
    }
}

1;
