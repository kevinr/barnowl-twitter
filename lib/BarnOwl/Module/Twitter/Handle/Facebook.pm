use warnings;
use strict;

=head1 NAME

BarnOwl::Module::Twitter::Handle::Facebook

=head1 DESCRIPTION

Contains everything needed to send and receive messages from Facebook

=cut

package BarnOwl::Module::Twitter::Handle::Facebook;

use WWW::Facebook::API;
use HTML::Entities;
use JSON;

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
        api_key => undef,
        secret => undef,
        %$cfg
       };

    my $self = {
        'cfg'  => $cfg,
        'facebook' => undef,
        'last_poll' => time,
        'last_direct_poll' => time,
        'has_session' => 0,
    };

    bless($self, $class);

    my %twitter_args = @_;

    $self->{facebook}  = WWW::Facebook::API->new(
        desktop => 1,
        api_key => $self->{cfg}->{api_key},
        secret => $self->{cfg}->{secret}
    );

    $self->{token} = $self->{facebook}->auth->create_token();
    $self->{login_url} = $self->{facebook}->get_login_url( auth_token => $self->{token} );

    BarnOwl::admin_message('Facebook Login', "Log into Facebook at:\n".$self->{login_url});
    #http://www.facebook.com/connect/prompt_permissions.php?api_key=1270bb6d452f02c16054c3c36b1c99b3&session_key=3.3Em6dZgOWDuYoM23GrgMCA__.86400.1251662400-501955124&ext_perm=read_stream,publish_stream&extern=1&enable_profile_selector=1

    return $self;
}

sub die_on_error {
    my $self = shift;
    my $error = shift;

    die "$error" if $error;
}

sub get_session {
    my $self = shift;

    unless ($self->{has_session}) {
        BarnOwl::message("Getting session...");
        eval { $self->{facebook}->auth->get_session($self->{token}) };
        if ($@) {
            warn "$@";
            return 0;
        } else {
            $self->{has_session} = 1;
            BarnOwl::message("Got session!");
        }
    }
    return 1;
}

sub poll_twitter {
    my $self = shift;

    return unless ( time - $self->{last_poll} ) >= 60;
    $self->{last_poll} = time;
    return unless BarnOwl::getvar('twitter:poll') eq 'on';

    return unless $self->get_session();
    BarnOwl::message("Polling Facebook...");

    sleep 1;

    my $timeline = eval { $self->{facebook}->stream->get( start_time => $self->{last_poll} ) };
    $self->die_on_error($@);
    use Data::Dumper;
    warn Dumper($timeline);

#    if ($self->{cfg}->{show_unsubscribed_replies}) {
#    }

#    if ( scalar @$timeline ) {
#        for my $tweet ( reverse @$timeline ) {
#            if ( $tweet->{id} <= $self->{last_id} ) {
#                next;
#            }
#            my $msg = BarnOwl::Message->new(
#                type      => 'Twitter',
#                sender    => $tweet->{user}{screen_name},
#                recipient => $self->{cfg}->{user} || $self->{user},
#                direction => 'in',
#                source    => decode_entities($tweet->{source}),
#                location  => decode_entities($tweet->{user}{location}||""),
#                body      => decode_entities($tweet->{text}),
#                status_id => $tweet->{id},
#                service   => $self->{cfg}->{service},
#                account   => $self->{cfg}->{account_nickname},
#               );
#            BarnOwl::queue_message($msg);
#        }
#        $self->{last_id} = $timeline->[0]{id} if $timeline->[0]{id} > $self->{last_id};
#    } else {
#        # BarnOwl::message("No new tweets...");
#    }
}

sub poll_direct {
    my $self = shift;

#    return unless ( time - $self->{last_direct_poll}) >= 120;
#    $self->{last_direct_poll} = time;
#    return unless BarnOwl::getvar('twitter:poll') eq 'on';
#
#    my $direct = eval { $self->{twitter}->direct_messages( { since_id => $self->{last_direct} } ) };
#    warn "$@" if $@;
#    unless(defined($direct) && ref($direct) eq 'ARRAY') {
#        $self->twitter_error();
#        return;
#    };
#    if ( scalar @$direct ) {
#        for my $tweet ( reverse @$direct ) {
#            if ( $tweet->{id} <= $self->{last_direct} ) {
#                next;
#            }
#            my $msg = BarnOwl::Message->new(
#                type      => 'Twitter',
#                sender    => $tweet->{sender}{screen_name},
#                recipient => $self->{cfg}->{user} || $self->{user},
#                direction => 'in',
#                location  => decode_entities($tweet->{sender}{location}||""),
#                body      => decode_entities($tweet->{text}),
#                isprivate => 'true',
#                service   => $self->{cfg}->{service},
#                account   => $self->{cfg}->{account_nickname},
#               );
#            BarnOwl::queue_message($msg);
#        }
#        $self->{last_direct} = $direct->[0]{id} if $direct->[0]{id} > $self->{last_direct};
#    } else {
#        # BarnOwl::message("No new tweets...");
#    }
}

sub twitter {
    my $self = shift;

    my $msg = shift;
    my $reply_to = shift;

#    if($msg =~ m{\Ad\s+([^\s])+(.*)}sm) {
#        $self->twitter_direct($1, $2);
#    } elsif(defined $self->{twitter}) {
    if (defined $self->{facebook}) {
        return unless $self->get_session();
        $self->{facebook}->stream->publish( message => $msg );
    }
#        if(defined($reply_to)) {
#            $self->{twitter}->update({
#                status => $msg,
#                in_reply_to_status_id => $reply_to
#               });
#        } else {
#            $self->{twitter}->update($msg);
#        }
#    }
}

sub twitter_direct {
    my $self = shift;

#    my $who = shift;
#    my $msg = shift;
#    if(defined $self->{twitter}) {
#        $self->{twitter}->new_direct_message({
#            user => $who,
#            text => $msg
#           });
#        if(BarnOwl::getvar("displayoutgoing") eq 'on') {
#            my $tweet = BarnOwl::Message->new(
#                type      => 'Twitter',
#                sender    => $self->{cfg}->{user} || $self->{user},
#                recipient => $who, 
#                direction => 'out',
#                body      => $msg,
#                isprivate => 'true',
#                service   => $self->{cfg}->{service},
#               );
#            BarnOwl::queue_message($tweet);
#        }
#    }
}

sub twitter_atreply {
    my $self = shift;

#    my $to  = shift;
#    my $id  = shift;
#    my $msg = shift;
#    if(defined($id)) {
#        $self->twitter("@".$to." ".$msg, $id);
#    } else {
#        $self->twitter("@".$to." ".$msg);
#    }
}

sub twitter_follow {
    my $self = shift;

#    my $who = shift;
#
#    my $user = $self->{twitter}->create_friend($who);
#    # returns a string on error
#    if (defined $user && !ref $user) {
#        BarnOwl::message($user);
#    } else {
#        BarnOwl::message("Following " . $who);
#    }
}

sub twitter_unfollow {
    my $self = shift;

#    my $who = shift;
#
#    my $user = $self->{twitter}->destroy_friend($who);
#    # returns a string on error
#    if (defined $user && !ref $user) {
#        BarnOwl::message($user);
#    } else {
#        BarnOwl::message("No longer following " . $who);
#    }
}

sub nickname {
    my $self = shift;
    return $self->{cfg}->{account_nickname};
}

1;
