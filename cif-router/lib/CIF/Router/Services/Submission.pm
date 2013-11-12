package CIF::Router::Services::Submission;
use parent 'CIF::Router::Service';

use strict;
use warnings;
use CIF::Router::Constants;
use Try::Tiny;
use CIF qw/debug/;

sub service_type { SVC_SUBMISSION }

# Should return 1 or 0
sub queue_should_autodelete {
  return 0;
}

# Should return 1 or 0
sub queue_is_durable {
  return 1;
}

sub process {
  my $self = shift;
  my $payload = shift;
  my $content_type = shift;
  my ($submission, $results);
  try {
    $submission = $self->encoder->decode_submission($payload);
    $results = $self->router->process_submission($submission);
  } catch {
    my $err = shift;
    debug($err);
    return($err, "submission_error", 'text/plain');
  };
  return($results, "submission_response", $self->encoder->content_type());
}

1;

