package CIF::Client::Transport::HTTP;
use base 'CIF::Client::Transport';
use base 'LWP::UserAgent';

use strict;
use warnings;

use CIF qw/debug/;
require LWP::UserAgent;
use Try::Tiny;
use JSON::XS;
use CIF::MsgHelpers;

our $AGENT = 'libcif/'.$CIF::VERSION.' (collectiveintel.org)';

sub new {
    my $class = shift;
    my $args = shift;

    my $self = $class->SUPER::new($args);
     
    # seems to be a bug if you don't set this
    $self->{'max_redirect'}    = $args->{'max_redirect'} || 5;

    if(defined($self->get_config->{'verify_tls'}) && $self->get_config->{'verify_tls'} == 0){
        $self->ssl_opts(SSL_verify_mode => 'SSL_VERIFY_NONE');
        $self->ssl_opts(verify_hostname => 0);
    }

    # set proxy
    # eg: export http_proxy='http://localhost:5050'
    $self->env_proxy();

    # override
    if($self->get_config->{'proxy'}){
        debug('setting proxy') if($::debug);
        $self->proxy(['http','https'],$self->get_config->{'proxy'});
    }
    
    $self->agent($AGENT);
    
    my $cache = $self->get_config->{'total_capacity'} || 5;
    $self->conn_cache({ total_capacity => $cache });
    
    my $timeout = $self->get_config->{'timeout'} || 300;
    $self->timeout($timeout);

    return($self);
}

sub _send_msg {
    my $self = shift;
    my $data = shift;
    
    my ($err, $resp) = $self->_send($data->encode());

    return $err if($err);

    my $msg = MessageType->decode($resp);

    $err = CIF::MsgHelpers::get_msg_error($msg);
    return $err if ($err);

    return(undef, $msg);
}

sub query {
    my $self = shift;
    my $queries = shift;

    my $msg = CIF::MsgHelpers::msg_wrap_queries($queries);
    my ($err, $msg2) = $self->_send_msg($msg);

    return ($err) if (defined($err));

    return CIF::MsgHelpers::decode_msg_feeds($msg2);
}

sub submit {
    my $self = shift;
    my $apikey = shift;
    my $guid = shift;
    my $iodefs = shift;

    my $msg = CIF::MsgHelpers::build_submission_msg($apikey, $guid, $iodefs);
    my ($err, $ret) = $self->_send_msg($msg);
    return $err if ($err);
    return (undef, $ret->get_data());
}

sub send_json {
    my $self = shift;
    my $args = shift;
    
    my $apikey  = $args->{'apikey'} || return 'missing apikey';
    my $data    = $args->{'data'}   || return 'missing data';
    
    $self->default_header('Accept' => 'application/json');
    $self->get_config->{'host'} .= '?apikey='.$apikey;
    return $self->_send($data);
}

sub _send {
    my $self = shift;
    my $data = shift;
    return unless($data);
    
    my ($err,$ret);
    my $x = 0;
    
    do {
        debug('posting data...') if($::debug);
        try {
            $ret = $self->post($self->get_config->{'host'},Content => $data);
        } catch {
            $err = shift;
        };
        if($err){
            for(lc($err)){
                if(/^server closed connection/){
                    debug('server closed the connection, retrying...') if($::debug);
                    $err = undef;
                    sleep(5);
                    last;
                }
                if(/connection refused/){
                    debug('server connection refused, retrying...') if($::debug);
                    $err = undef;
                    sleep(5);
                    last;
                }
                $x = 5;
            }
        }
    } while(!$ret && ($x++ < 5));
    ## TODO -- do we turn this into a re-submit?
    return('unknown, possible server timeout....') unless($ret);
    return($ret->status_line()) unless($ret->is_success());
    debug('data sent succesfully...') if($::debug);
    return(undef,$ret->decoded_content());
}

1;
