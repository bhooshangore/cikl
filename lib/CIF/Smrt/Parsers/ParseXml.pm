package CIF::Smrt::Parsers::ParseXml;
use base 'CIF::Smrt::Parser';

use strict;
use warnings;
require XML::LibXML;

sub parse {
    my $self = shift;
    my $content = shift;
    
    my $parser      = XML::LibXML->new();
    my $doc         = $parser->load_xml(string => $content);
    my @nodes       = $doc->findnodes('//'.$self->config->node);
    my @subnodes    = $doc->findnodes('//'.$self->config->subnode) if($self->config->subnode);
    
    return unless(@nodes);
    
    my @array;
    my @elements        = $self->config->elements; 
    my @elements_map    = $self->config->elements_map; 
    my @attributes_map  = $self->config->attributes_map; 
    my @attributes      = $self->config->attributes; 
    
    my %regex;
    # TODO MPR: clean this up. Modifying the config is bonkers.
    foreach my $k (keys %{$self->config}){
        # pull out any custom regex
        for($k){
            if(/^regex_(\S+)$/){
                $regex{$1} = qr/$self->config->{$k}/;
                delete($self->config->{$k});
                last;
            }
            # clean up the hash, so we can re-map the default values later
            if(/^(elements_?|attributes_?|node|subnode)/){
                delete($self->config->{$k});
                last;
            }
        }
    }
   
    foreach my $node (@nodes){
        my $h = $self->create_event();
        map { $h->{$_} = $self->config->{$_} } keys %{$self->config};
        my $found = 0;
        if(@elements_map){
            foreach my $e (0 ... $#elements_map){
                my $x = $node->findvalue('./'.$elements[$e]);
                next unless($x);
                if(my $r = $regex{$elements[$e]}){
                    if($x =~ $r){
                        $h->{$elements_map[$e]} = $x;
                        $found = 1;
                    } else {
                        $found = 0;
                    }
                } else {
                    $h->{$elements_map[$e]} = $x;
                    $found = 1;
                }
            }
        } else {
            foreach my $e (0 ... $#attributes_map){       
                my $x = $node->getAttribute($attributes[$e]);
                next unless($x);
                if(my $r = $regex{$attributes[$e]}){
                    if($x =~ $r){
                        $h->{$attributes_map[$e]} = $x;
                        $found = 1;
                    } else {
                        $found = 0;
                    }
                } else {
                    $h->{$attributes_map[$e]} = $x;
                    $found = 1;
                }
            }
        }
        push(@array,$h) if($found);

    }
    return(\@array);
}

1;
