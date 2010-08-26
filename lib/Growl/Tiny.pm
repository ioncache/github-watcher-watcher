package Growl::Tiny;
use strict;
use warnings;

use base 'Exporter';
our @EXPORT_OK = ( 'notify' );

our $VERSION;

#my $GROWL_COMMAND = "/usr/local/bin/growlnotify";
my $GROWL_COMMAND = "growlnotify";

#_* Libraries

use Carp;

#_* POD

=head1 NAME

Growl::Tiny - tiny perl module for sending Growl notifications on Mac OS X


=head1 SYNOPSIS

    use Growl::Tiny;

=head1 DESCRIPTION

Following the Tiny perl module convention, this module attempts to
provide a way to use Mac::Growl on OS X without any of the prereqs
(Mac::Glue, Mac::Carbon, etc.).  I have repeatedly run into a number
of problems installing these modules (on an old or brand new version
of the OS, using a 64-bit perl, etc.), so I decided to write a tiny
one that got the job done without them.

The only way I knew to use Growl without any prereqs was to use the
growlnotify command-line tool.  For more information on this tool, see:

  http://growl.info/documentation/growlnotify.php

There are some limitations, please see the BUGS AND LIMITATIONS
section below.  If these are a problem for you, please use Mac::Growl
instead.


=cut


#_* Methods

=head1 SUBROUTINES/METHODS

=over 4

=item notify( { %options } )

Send a growl notification.  Accepts either a hash or a hash reference.

Returns true if a notification was submitted.

=back

=head2 Options

=over 8

=item subject  => 'required notification text'

Text to be used for the notification body.

This is a required field--no notification will be generated if it is
not set.

=item title    => 'optional title'

Optional text to be used for the notification title.

=item priority => 0

Optional priority.  This can be -2, -1, 0, 1, or 2.

=item sticky   => 0

If 'sticky' is set to 'true', then the notification will remain
on-screen until clicked.

=item quiet    => 0

Suppress this notification.

=item host     => ''

Send a network notification to the specified host by passing the -H
option to growlnotify.  Note that growl must be configured to accept
network notifications for this to work.  Set this to 'localhost' to
use local network delivery for improved reliability--see the BUGS AND
LIMITATIONS section below for more information.

If the environment variable GROWL_HOST is set, all notifications will
be sent to that host by default.  Individual notifications may still
be sent to other hosts using the 'host' option.

=item image    => '/path/to/image'

Set the path to an image to be used as an icon for notifications.

=item name     => 'Growl::Tiny'

Set to the name of the application that is sending the notifications.
By default this will be set to 'Growl::Tiny'.  Setting this to the
name of your application allows you to customize the notification
options for your application in the growl preferences pane under the
'applications' tab.


=back

=cut

sub notify {
    my $options;

    if ( ref $_[0] eq "HASH" ) {
        $options = $_[0];
    }
    else {
        $options = \%_;
    }

    # skip notifications with no subject
    return unless $options->{subject};

    # skip notifications with the 'quiet' flag set
    return if $options->{quiet};

    my $host = $options->{host} || $ENV{GROWL_HOST} || 'localhost';

    #
    # setup the option flags based on OS
    #
    my $cl_opts = undef;
    if ( $^O =~ /Win/ ) {
        $cl_opts->{host} = '/host:' . $host;
        $cl_opts->{subject} = '"' . $options->{subject} . '"';
        if ($options->{image}) {
            $cl_opts->{image} = '/i:"' . $options->{image} . '"';
        }
        if ($options->{name}) {        
            $cl_opts->{name} = '/a:"' . $options->{name} . '" /r:"General Notification"';
        }
        else {
            $cl_opts->{name} = '/a:"' . "Growl::Tiny" . '" /r:"General Notification"';
        }
        if ($options->{priority}) {
            $cl_opts->{priority} = '/p:' . $options->{priority};
        }
        if ($options->{sticky}) {
            $cl_opts->{sticky} = '/s:true';
        }
        if ($options->{title}) {
            $cl_opts->{title} = '/t:"' . $options->{title} . '"';
        }
    }
    else {
        $cl_opts->{host} = '-H ' . $host;
        $cl_opts->{subject} = '-m ' . $options->{subject};

        if ($options->{image}) {
            $cl_opts->{image} = '--image ' . $options->{image};
        }
        if ($options->{name}) {        
            $cl_opts->{name} = '-n ' . $options->{name};
        }
        else {
            $cl_opts->{name} = '-n ' . "Growl::Tiny";
        }
        if ($options->{priority}) {
            $cl_opts->{priority} = '-p ' . $options->{priority};
        }
        if ($options->{sticky}) {
            $cl_opts->{sticky} = '-s';
        }
        if ($options->{title}) {
            $cl_opts->{title} = '-t ' . $options->{title};
        }
    }

    #
    # build the command line options
    #
    my @command_line_args = ( $GROWL_COMMAND );
    push @command_line_args, $cl_opts->{name};
    push @command_line_args, $cl_opts->{sticky} if $cl_opts->{sticky};
    push @command_line_args, $cl_opts->{priority} if $cl_opts->{priority};
    push @command_line_args, $cl_opts->{host} if $cl_opts->{host};
    push @command_line_args, $cl_opts->{image} if $cl_opts->{image};
    push @command_line_args, $cl_opts->{title} if $cl_opts->{title};
    push @command_line_args, $cl_opts->{subject};

    print "COMMAND: ", join " ", @command_line_args, "\n";
    return system( @command_line_args ) ? 0 : 1;
}

# for automated testing only
sub _set_growl_command {
    my ( $command ) = @_;

    $GROWL_COMMAND = $command;

    return 1;
}


#_* End


1;

__END__

=head1 DEPENDENCIES

Growl (http://growl.info) must be installed locally.  You must also
have the growlnotify script installed at:

    /usr/local/bin/growlnotify


=head1 BUGS AND LIMITATIONS

The 'growlnotify' script will drop notifications when multiple
notifications are being processed concurrently or are submitted too
rapidly.  I only discovered this while writing the test cases.  As a
result, this module is NOT recommended for any application where more
than one notification might be generated per second.  Note that
Growl::Tiny will actually send messages much faster than this, but
exceeding this rate may cause some notifications to be dropped.

The work-around for this is to use growlnotify to deliver network
notifications to localhost.  Unlike the default mechanism used by
growlnotify, the network delivery seems to be very reliable.  To
enable this, go into the growl preference pane, select the 'network'
tab, and enable 'listen for incoming connections'.  I did not have to
restart growl after changing this setting.  Once this has been done,
to use network notifications in Growl::Tiny, either set the
environment variable GROWL_HOST, or else set the 'host' property on
each notification to 'localhost'.

Note that there is no reasonable way to test if a notification has
actually been displayed and not dropped.  It is only possible to check
that growlnotify returned success.  This greatly limits the amount and
quality of automated testing that can be performed.

=head1 EXPORT

notify - send a notification

=head1 SEE ALSO

http://growl.info - The Growl Project site

Mac::Growl - Local Growl Notification Framework.

Net::Growl - Growl Notifications over the network

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2009, VVu@geekfarm.org
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

- Redistributions of source code must retain the above copyright
  notice, this list of conditions and the following disclaimer.

- Redistributions in binary form must reproduce the above copyright
  notice, this list of conditions and the following disclaimer in the
  documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
