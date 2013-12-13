package CIF::DataStore::Factory;
use strict;
use warnings;

sub instantiate {
  my $class = shift;
  my $datastore_config = shift;
  my $driver_class = $datastore_config->{driver} or 
    die("No driver provided for datastore config!");

  eval("require $driver_class") or die("Failed to load $driver_class: $!");

  return $driver_class->new($datastore_config);
}

1;
