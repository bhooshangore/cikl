package CIF::Smrt::Handler;

use strict;
use warnings;
use CIF::Client;
use CIF::Smrt::ClientBroker;
use CIF::EventBuilder;
use CIF::Smrt::Broker;
use Config::Simple;
use Try::Tiny;
use AnyEvent;
use Coro;
use DateTime;

use Moose;
use CIF qw/debug/;
use Net::SSLeay;
Net::SSLeay::SSLeay_add_ssl_algorithms();

use namespace::autoclean;

has 'apikey' => (
  is => 'ro',
  isa => 'Str',
  required => 1
);

has 'global_config' => (
  is => 'ro',
  isa => 'Config::Simple',
  required => 1
);

has 'event_builder' => (
  is => 'ro',
  isa => 'CIF::EventBuilder',
  init_arg => undef,
  lazy => 1,
  builder => "_event_builder"
);

has 'not_before' => (
  is => 'ro', 
  isa => 'DateTime',
  required => 1,
  default => sub {return DateTime->now()->subtract(days => 3);}
);

has 'proxy' => (
  is => 'ro',
  required => 0
);

sub _event_builder {
  my $self = shift;
  return CIF::EventBuilder->new(
    not_before => $self->not_before(),
    default_event_data => $self->default_event_data(),
    refresh => $self->refresh()
  ) 
}

sub default_event_data {
  return {};
}

sub refresh {
  return 0;
}

sub get_client {
  my $self = shift;
  my ($err,$client) = CIF::Client->new({
      config  => $self->global_config,
      apikey  => $self->apikey,
    });

  if ($err) {
    die($err);
  }
  return($client);
}

sub process {
    my $self = shift;
    my ($err, $ret);
    
    my $client = $self->get_client();

    my $broker = CIF::Smrt::ClientBroker->new(
      client => $client,
      builder => $self->event_builder()
    );
    try {
      my ($err) = $self->parse($broker);
      if ($err) {
        die($err);
      }
    } catch {
      $err = shift;
    } finally {
      if ($client) {
        $client->shutdown();
      }
    };
    if ($err) {
      return($err);
    }

    if($::debug) {
      debug('records to be processed: '.$broker->count() . ", too old: " . $broker->count_too_old());
    }

    if($broker->count() == 0){
      if ($broker->count_too_old() != 0) {
        debug('your goback is too small, if you want records, increase the goback time') if($::debug);
      }
      return (undef, 'no records');
    }

    return(undef);
}

sub fetch { 
    my $self = shift;
    my $cv = AnyEvent->condvar;
    my $fetcher = $self->get_fetcher();

    async {
      try {
        $cv->send($fetcher->fetch());
      } catch {
        $cv->croak(shift);
      };
    };
    while (!($cv->ready())) {
      Coro::AnyEvent::sleep(1);
    }
    my $retref = $cv->recv();

    # auto-decode the content if need be
    $retref = $self->decode($retref);

    ## TODO MPR : This looks like a hack for the utf8 and CR stuff below.
    #return(undef,$ret) if($feedparser_config->{'cif'} && $feedparser_config->{'cif'} eq 'true');

    ## Commenting this out as I haven't run into any issues, yet.  
    # encode to utf8
    #$ret = encode_utf8($ret);
    
    # remove any CR's
    #$ret =~ s/\r//g;
    return($retref);
}


sub parse {
    my $self = shift;
    my $broker = shift;

    my $content_ref = $self->fetch();
    
    my $return = $self->get_parser()->parse($content_ref, $broker);
    return(undef);
}

# Just pass things through. This can be overridden by subclasses.
sub decode {
    my $self = shift;
    my $content_ref = shift;
    return $content_ref;
}


# Stuff that needs to be implemented

# Returns an instance of a fetcher. We will call fetcher->fetch()
sub get_fetcher {
    my $self = shift;
    die("get_fetcher() not implemented!");
}

# Returns an instance of a parser. We will call parser->parse($content_ref, $broker)
sub get_parser {
    my $self = shift;
    die("get_parser() not implemented!");
}

__PACKAGE__->meta->make_immutable;

1;
