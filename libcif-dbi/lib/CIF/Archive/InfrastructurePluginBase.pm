package CIF::Archive::InfrastructurePluginBase;
use base 'CIF::Archive::AddressPluginBase';

use warnings;
use strict;

use Regexp::Common qw/net/;
use Regexp::Common::net::CIDR;
use CIF qw/debug/;

use constant DATATYPE => 'infrastructure';
sub datatype { return DATATYPE; }
sub feedtype { return DATATYPE; }

__PACKAGE__->table('infrastructure');
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->columns(All => qw/id uuid guid hash address confidence reporttime created/);
__PACKAGE__->sequence('infrastructure_id_seq');

sub match_event {
  my $class = shift;
  my $event = shift;
  my $ret = $class->SUPER::match_event($event);
  if ($ret == 0) {
    return 0;
  }

  my $address = $event->address();
  if (!defined($address)) {
    return 0;
  }

  unless($address =~ /^$RE{'net'}{'IPv4'}$/ || $address =~ /^$RE{'net'}{'CIDR'}{'IPv4'}$/) {
    return 0;
  }

  return 1;
}

#sub insert_into_feed {
#  my $class = shift;
#  my $event = shift;
#  my $address = lc($event->address());
#### TODO MPR: This is trying to make supplied port ranges indexable, but Ill 
#    #have to come back to it later.
#
###    use Parse::Range qw(parse_range);
###    # we just need a unique hash based on port/protocol
###    # this is a fast way to stringify what we have and hash it
###    my $services = $system->get_Service();
###    $services = (ref($system->get_Service()) eq 'ARRAY') ? $system->get_Service() : [$system->get_Service] if($services);
###    if($services){
###      my $ranges;
###      foreach my $service (@$services){
###        my $portlist = $service->get_Portlist();
###        if($portlist){
###          if($portlist =~ /^\d([\d,-]+)?$/){
###            $portlist = parse_range($portlist);
###            push(@{$ranges->{$service->get_ip_protocol()}},$portlist);
###          } else {
###            debug('invalid portlist format: '.$portlist);
###            debug('uuid: '.$data->{'uuid'});
###          }
###        }
###      }
###      if($ranges){
###        $ranges = encode_json($ranges);
###        $hash = sha1_hex($hash.$ranges);
###      }
###    }
#  $class->index_event_for_feed($event, $address, {address => $address});
#}

sub insert {
  my $class = shift;
  my $event = shift;

  my $address = $event->address;
  my @ids;

  my $id;

  ## TODO -- clean this up into a function, map with ipv6
  ## it'll evolve into pushing this search into the hash table
  ## the client will then do the final leg of the work (Net::Patricia, etc)
  ## right now postgres can do it, but down the road big-data warehouses might not
  ## this way we can do faster hash lookups for non-advanced CIDR queries

  my @index;
  if($address =~ /^$RE{'net'}{'IPv4'}$/){
    my @array = split(/\./,$address);
    push(@index, (
        $address,
        $array[0].'.'.$array[1].'.'.$array[2].'.0/24',
        $array[0].'.'.$array[1].'.0.0/16',
        $array[0].'.0.0.0/8'
      ));
  } elsif($address =~ /^$RE{'net'}{'CIDR'}{'IPv4'}{-keep}$/){
    my @array = split(/\./,$1);
    my $mask = $2;
    my @a1;
    for($mask){
      if($_ >= 8){
        push(@index, $array[0].'.0.0.0/8');
      }
      if($_ >= 16){
        push(@index,$array[0].'.'.$array[1].'.0.0/16');
      }
      if($_ >= 24){
        push(@index,$array[0].'.'.$array[1].'.'.$array[2].'.0/24');
      }     
    }
  }

  foreach my $x (@index){
    $id = $class->insert_hash($event,$x);
    push(@ids,$id);
  }
  return(undef,\@ids);
}

1;
