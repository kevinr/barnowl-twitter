use warnings;
use strict;

=head1 NAME

BarnOwl::Module::Twitter::Handle

=head1 DESCRIPTION

Abstraction for a handle to a Twitter-like service.  Returns 
the appropriate service sub-module for the provided arguments.

=cut

package BarnOwl::Module::Twitter::Handle;

use Net::Twitter::Lite;

use BarnOwl::Module::Twitter::Handle::Twitter;
use BarnOwl::Module::Twitter::Handle::Facebook;

sub new {
    my $class = shift;
    my $cfg = shift;
 
    if ($cfg->{service} =~ /facebook/i) {
        return BarnOwl::Module::Twitter::Handle::Facebook->new($cfg, @_);
    }

    return BarnOwl::Module::Twitter::Handle::Twitter->new($cfg, @_);
}

1;
