use warnings;
use strict;

=head1 NAME

BarnOwl::Module::Twitter::Handle

=head1 DESCRIPTION

Abstraction for a handle to a Twitter-like service.  Returns 
the appropriate service sub-module for the provided arguments.

=cut

package BarnOwl::Module::Twitter::Handle;

use BarnOwl::Module::Twitter::Handle::Twitter;

sub new {
    my $class = shift;

    return BarnOwl::Module::Twitter::Handle::Twitter->new(@_);
}

1;
