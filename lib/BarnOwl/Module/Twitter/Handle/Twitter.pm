use warnings;
use strict;

=head1 NAME

BarnOwl::Module::Twitter::Handle::Twitter

=head1 DESCRIPTION

Contains everything needed to send and receive messages from a Twitter-like service.

=cut

package BarnOwl::Module::Twitter::Handle::Twitter;

use Net::Twitter::Lite;
BEGIN {
    # Backwards compatibility with version of Net::Twitter::Lite that
    # lack home_timeline.
    if(!defined(*Net::Twitter::Lite::home_timeline{CODE})) {
        *Net::Twitter::Lite::home_timeline =
          \&Net::Twitter::Lite::friends_timeline;
    }
}

use HTML::Entities;

use BarnOwl;
use BarnOwl::Message::Twitter;

sub fail {
    my $self = shift;
    my $msg = shift;
    undef $self->{twitter};
    my $nickname = $self->{cfg}->{account_nickname} || "";
    die("[Twitter $nickname] Error: $msg\n");
}

sub new {
    my $class = shift;
    my $cfg = shift;

    $cfg = {
        account_nickname => '',
        default_sender   => 0,
        poll_for_tweets  => 1,
        poll_for_dms     => 1,
        publish_tweets   => 1,
        show_unsubscribed_replies => 1,
        %$cfg
       };

    my $self = {
        'cfg'  => $cfg,
        'twitter' => undef,
        'last_poll' => 0,
        'last_direct_poll' => 0,
        'last_id' => undef,
        'last_direct' => undef,
    };

    bless($self, $class);

    my %twitter_args = @_;

    $self->{twitter}  = Net::Twitter::Lite->new(%twitter_args);

    my $timeline = eval { $self->{twitter}->friends_timeline({count => 1}) };
    warn "$@" if $@;

    if(!defined($timeline)) {
        $self->fail("Invalid credentials");
    }

    eval {
        $self->{last_id} = $timeline->[0]{id};
    };
    $self->{last_id} = 1 unless defined($self->{last_id});

    eval {
        $self->{last_direct} = $self->{twitter}->direct_messages()->[0]{id};
    };
    warn "$@" if $@;
    $self->{last_direct} = 1 unless defined($self->{last_direct});

    eval {
        $self->{twitter}->{ua}->timeout(1);
    };
    warn "$@" if $@;

    return $self;
}

sub twitter_error {
    my $self = shift;

    my $ratelimit = eval { $self->{twitter}->rate_limit_status };
    warn "$@" if $@;
    unless(defined($ratelimit) && ref($ratelimit) eq 'HASH') {
        # Twitter's just sucking, sleep for 5 minutes
        $self->{last_direct_poll} = $self->{last_poll} = time + 60*5;
        # die("Twitter seems to be having problems.\n");
        return;
    }
    if(exists($ratelimit->{remaining_hits})
       && $ratelimit->{remaining_hits} <= 0) {
        $self->{last_direct_poll} = $self->{last_poll} = $ratelimit->{reset_time_in_seconds};
        die("Twitter: ratelimited until " . $ratelimit->{reset_time} . "\n");
    } elsif(exists($ratelimit->{error})) {
        die("Twitter: ". $ratelimit->{error} . "\n");
        $self->{last_direct_poll} = $self->{last_poll} = time + 60*20;
    }
}

sub poll_twitter {
    my $self = shift;

    return unless ( time - $self->{last_poll} ) >= 60;
    $self->{last_poll} = time;
    return unless BarnOwl::getvar('twitter:poll') eq 'on';

    my $timeline = eval { $self->{twitter}->friends_timeline( { since_id => $self->{last_id} } ) };
    warn "$@" if $@;
    unless(defined($timeline) && ref($timeline) eq 'ARRAY') {
        $self->twitter_error();
        return;
    };

    if ($self->{cfg}->{show_unsubscribed_replies}) {
        my $mentions = eval { $self->{twitter}->mentions( { since_id => $self->{last_id} } ) };
        warn "$@" if $@;
        unless (defined($mentions) && ref($mentions) eq 'ARRAY') {
            $self->twitter_error();
            return;
        };
        #combine, sort by id, and uniq
        push @$timeline, @$mentions;
        @$timeline = sort { $b->{id} <=> $a->{id} } @$timeline;
        my $prev = { id => 0 };
        @$timeline = grep($_->{id} != $prev->{id} && (($prev) = $_), @$timeline);
    }

    if ( scalar @$timeline ) {
        for my $tweet ( reverse @$timeline ) {
            if ( $tweet->{id} <= $self->{last_id} ) {
                next;
            }
            my $msg = BarnOwl::Message->new(
                type      => 'Twitter',
                sender    => $tweet->{user}{screen_name},
                recipient => $self->{cfg}->{user} || $self->{user},
                direction => 'in',
                source    => decode_entities($tweet->{source}),
                location  => decode_entities($tweet->{user}{location}||""),
                body      => decode_entities($tweet->{text}),
                status_id => $tweet->{id},
                service   => $self->{cfg}->{service},
                account   => $self->{cfg}->{account_nickname},
               );
            BarnOwl::queue_message($msg);
        }
        $self->{last_id} = $timeline->[0]{id} if $timeline->[0]{id} > $self->{last_id};
    } else {
        # BarnOwl::message("No new tweets...");
    }
}

sub poll_direct {
    my $self = shift;

    return unless ( time - $self->{last_direct_poll}) >= 120;
    $self->{last_direct_poll} = time;
    return unless BarnOwl::getvar('twitter:poll') eq 'on';

    my $direct = eval { $self->{twitter}->direct_messages( { since_id => $self->{last_direct} } ) };
    warn "$@" if $@;
    unless(defined($direct) && ref($direct) eq 'ARRAY') {
        $self->twitter_error();
        return;
    };
    if ( scalar @$direct ) {
        for my $tweet ( reverse @$direct ) {
            if ( $tweet->{id} <= $self->{last_direct} ) {
                next;
            }
            my $msg = BarnOwl::Message->new(
                type      => 'Twitter',
                sender    => $tweet->{sender}{screen_name},
                recipient => $self->{cfg}->{user} || $self->{user},
                direction => 'in',
                location  => decode_entities($tweet->{sender}{location}||""),
                body      => decode_entities($tweet->{text}),
                isprivate => 'true',
                service   => $self->{cfg}->{service},
                account   => $self->{cfg}->{account_nickname},
               );
            BarnOwl::queue_message($msg);
        }
        $self->{last_direct} = $direct->[0]{id} if $direct->[0]{id} > $self->{last_direct};
    } else {
        # BarnOwl::message("No new tweets...");
    }
}

sub twitter {
    my $self = shift;

    my $msg = shift;
    my $reply_to = shift;

    if($msg =~ m{\Ad\s+([^\s])+(.*)}sm) {
        $self->twitter_direct($1, $2);
    } elsif(defined $self->{twitter}) {
        if(defined($reply_to)) {
            $self->{twitter}->update({
                status => $msg,
                in_reply_to_status_id => $reply_to
               });
        } else {
            $self->{twitter}->update($msg);
        }
    }
}

sub twitter_direct {
    my $self = shift;

    my $who = shift;
    my $msg = shift;
    if(defined $self->{twitter}) {
        $self->{twitter}->new_direct_message({
            user => $who,
            text => $msg
           });
        if(BarnOwl::getvar("displayoutgoing") eq 'on') {
            my $tweet = BarnOwl::Message->new(
                type      => 'Twitter',
                sender    => $self->{cfg}->{user} || $self->{user},
                recipient => $who, 
                direction => 'out',
                body      => $msg,
                isprivate => 'true',
                service   => $self->{cfg}->{service},
               );
            BarnOwl::queue_message($tweet);
        }
    }
}

sub twitter_atreply {
    my $self = shift;

    my $to  = shift;
    my $id  = shift;
    my $msg = shift;
    if(defined($id)) {
        $self->twitter("@".$to." ".$msg, $id);
    } else {
        $self->twitter("@".$to." ".$msg);
    }
}

sub twitter_follow {
    my $self = shift;

    my $who = shift;

    my $user = $self->{twitter}->create_friend($who);
    # returns a string on error
    if (defined $user && !ref $user) {
        BarnOwl::message($user);
    } else {
        BarnOwl::message("Following " . $who);
    }
}

sub twitter_unfollow {
    my $self = shift;

    my $who = shift;

    my $user = $self->{twitter}->destroy_friend($who);
    # returns a string on error
    if (defined $user && !ref $user) {
        BarnOwl::message($user);
    } else {
        BarnOwl::message("No longer following " . $who);
    }
}

sub nickname {
    my $self = shift;
    return $self->{cfg}->{account_nickname};
}

1;
