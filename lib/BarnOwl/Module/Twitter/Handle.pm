use warnings;
use strict;

=head1 NAME

BarnOwl::Module::Twitter::Handle

=head1 DESCRIPTION

Contains everything needed to send and receive messages from a Twitter-like service.

=cut

package BarnOwl::Module::Twitter::Handle;

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

use Scalar::Util qw(weaken);

use BarnOwl;
use BarnOwl::Message::Twitter;
use POSIX qw(asctime);

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

    my $val;

    if(!exists $cfg->{default} &&
       defined($val = delete $cfg->{default_sender})) {
        $cfg->{default} = $val;
    }

    if(!exists $cfg->{show_mentions} &&
       defined($val = delete $cfg->{show_unsubscribed_replies})) {
        $cfg->{show_mentions} = $val;
    }

    $cfg = {
        account_nickname => '',
        default          => 0,
        poll_for_tweets  => 1,
        poll_for_dms     => 1,
        publish_tweets   => 0,
        show_mentions    => 1,
        %$cfg
       };

    my $self = {
        'cfg'  => $cfg,
        'twitter' => undef,
        'last_id' => undef,
        'last_direct' => undef,
        'timer'        => undef,
        'direct_timer' => undef
    };

    bless($self, $class);

    my %twitter_args = @_;

    $self->{twitter}  = Net::Twitter::Lite->new(%twitter_args);

    my $timeline = eval { $self->{twitter}->home_timeline({count => 1}) };
    warn "$@\n" if $@;

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
    warn "$@\n" if $@;
    $self->{last_direct} = 1 unless defined($self->{last_direct});

    eval {
        $self->{twitter}->{ua}->timeout(1);
    };
    warn "$@\n" if $@;

    $self->sleep(0);

    return $self;
}

=head2 sleep SECONDS

Stop polling Twitter for SECONDS seconds.

=cut

sub sleep {
    my $self  = shift;
    my $delay = shift;

    my $weak = $self;
    weaken($weak);

    if($self->{cfg}->{poll_for_tweets}) {
        $self->{timer} = BarnOwl::Timer->new({
            after    => $delay,
            interval => 90,
            cb       => sub { $weak->poll_twitter if $weak }
           });
    }

    if($self->{cfg}->{poll_for_dms}) {
        $self->{direct_timer} = BarnOwl::Timer->new({
            after    => $delay,
            interval => 180,
            cb       => sub { $weak->poll_direct if $weak }
           });
    }
}

=head2 twitter_command COMMAND ARGS...

Call the specified method on $self->{twitter} with an extended
timeout. This is intended for interactive commands, with the theory
that if the user explicitly requested an action, it is slightly more
acceptable to hang the UI for a second or two than to fail just
because Twitter is being slightly slow. Polling commands should be
called normally, with the default (short) timeout, to prevent
background Twitter suckage from hosing the UI normally.

=cut

sub twitter_command {
    my $self = shift;
    my $cmd = shift;

    eval { $self->{twitter}->{ua}->timeout(5); };
    my $result = eval {
        $self->{twitter}->$cmd(@_);
    };
    my $error = $@;
    eval { $self->{twitter}->{ua}->timeout(1); };
    if ($error) {
        die($error);
    }
    return $result;
}

sub twitter_error {
    my $self = shift;

    my $ratelimit = eval { $self->{twitter}->rate_limit_status };
    BarnOwl::debug($@) if $@;
    unless(defined($ratelimit) && ref($ratelimit) eq 'HASH') {
        # Twitter's probably just sucking, try again later.
        $self->sleep(5*60);
        return;
    }

    if(exists($ratelimit->{remaining_hits})
       && $ratelimit->{remaining_hits} <= 0) {
        my $timeout = $ratelimit->{reset_time_in_seconds};
        $self->sleep($timeout - time + 60);
        BarnOwl::error("Twitter" .
                       ($self->{cfg}->{account_nickname} ?
                        "[$self->{cfg}->{account_nickname}]" : "") .
                        ": ratelimited until " . asctime(localtime($timeout)));
    } elsif(exists($ratelimit->{error})) {
        $self->sleep(60*20);
        die("Twitter: ". $ratelimit->{error} . "\n");
    }
}

sub poll_twitter {
    my $self = shift;

    return unless BarnOwl::getvar('twitter:poll') eq 'on';

    BarnOwl::debug("Polling " . $self->{cfg}->{account_nickname});

    my $timeline = eval { $self->{twitter}->home_timeline( { since_id => $self->{last_id} } ) };
    BarnOwl::debug($@) if $@;
    unless(defined($timeline) && ref($timeline) eq 'ARRAY') {
        $self->twitter_error();
        return;
    };

    if ($self->{cfg}->{show_mentions}) {
        my $mentions = eval { $self->{twitter}->mentions( { since_id => $self->{last_id} } ) };
        BarnOwl::debug($@) if $@;
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

    return unless BarnOwl::getvar('twitter:poll') eq 'on';

    BarnOwl::debug("Polling direct for " . $self->{cfg}->{account_nickname});

    my $direct = eval { $self->{twitter}->direct_messages( { since_id => $self->{last_direct} } ) };
    BarnOwl::debug($@) if $@;
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
                private => 'true',
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
        if(length($msg) > 140) {
            die("Twitter: Message over 140 characters long.\n");
        }
        $self->twitter_command('update', {
            status => $msg,
            defined($reply_to) ? (in_reply_to_status_id => $reply_to) : ()
           });
    }
    $self->poll_twitter if $self->{cfg}->{poll_for_tweets};
}

sub twitter_direct {
    my $self = shift;

    my $who = shift;
    my $msg = shift;
    if(defined $self->{twitter}) {
        $self->twitter_command('new_direct_message', {
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
                private => 'true',
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

sub twitter_retweet {
    my $self = shift;
    my $msg = shift;

    if($msg->service ne $self->{cfg}->{service}) {
        die("Cannot retweet a message from a different service.\n");
    }
    $self->twitter_command(retweet => $msg->{status_id});
    $self->poll_twitter if $self->{cfg}->{poll_for_tweets};
}

sub twitter_follow {
    my $self = shift;

    my $who = shift;

    my $user = $self->twitter_command('create_friend', $who);
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

    my $user = $self->twitter_command('destroy_friend', $who);
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
