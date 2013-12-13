package CIF::Postgres::QueryHandler;
use strict;
use warnings;
use Mouse;
use CIF::QueryHandler::Role ();
use CIF::Postgres::SQLRole ();
use CIF::Codecs::JSON ();
use namespace::autoclean;

with "CIF::QueryHandler::Role", "CIF::Postgres::SQLRole";

has '_db_codec' => (
  is => 'ro', 
  init_arg => undef,
  default => sub {CIF::Codecs::JSON->new()}
);

sub search {
  my $self = shift;
  my $query = shift;
  my $arrayref_event_json = $self->sql->search($query);

  my $codec = $self->_db_codec;
  my $ret = [ map { $codec->decode_event($_); } @$arrayref_event_json ];
  return $ret;
}

after "shutdown" => sub {
  my $self = shift;
  $self->sql->shutdown();
};

__PACKAGE__->meta->make_immutable();


1;

