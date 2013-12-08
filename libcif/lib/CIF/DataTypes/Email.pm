package CIF::DataTypes::Email;
use strict;
use warnings;
use namespace::autoclean;
use Mouse::Util::TypeConstraints;
use Mail::RFC822::Address qw/valid/;

subtype 'CIF::DataTypes::Email',
  as 'CIF::DataTypes::LowerCaseStr',
  where { valid($_) && $_ !~ /^\s+|\s+$/ },
  message { "Invalid E-Mail address: $_"} ;
1;



