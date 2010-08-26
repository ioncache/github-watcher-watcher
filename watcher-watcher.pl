#!/user/bin/perl

use FindBin;
use lib "$FindBin::Bin/../Growl-Tiny/lib";

#use Find::Lib '../Growl-Tiny/lib';

use CHI;
use Data::Dump qw( dump );
use Getopt::Declare;
use Growl::Tiny qw( notify );
use JSON;
use List::Compare;
use Modern::Perl;
use WWW::Mechanize;
use WWW::Mechanize::Cached;

my $mech_class = 'WWW::Mechanize';
my $mech       = $mech_class->new;

use vars qw/$debug $github_username $github_repo $delay_seconds $sticky/;

# some option defaults
$debug           = 0;
$github_username = '';
$github_repo     = '';
$delay_seconds   = 3600;
$sticky          = 0;

parse_program_arguments();

my $base_url = "http://github.com/api/v2/json/repos/show";

my $cache = CHI->new(
    driver     => 'FastMmap',
    share_file => '/tmp/git-growl',
);

my $cache_key = $github_repo . '-watchers';
my $cached = $cache->get($cache_key) || [];

$mech->get("$base_url/$github_username/$github_repo/watchers");
my $watchers = decode_json( $mech->content )->{watchers};

# only sets the cache to the list watchers if it was previously empty
if (!@{$cached}) {
    $cache->set( $cache_key => $watchers );
}

while (1) {
    # sets some default Growl message information
    my $title   = "Watcher count idle.";
    my $subject = "$github_repo has " . @{$watchers} . " watchers.";

    # does some comparisons between the current watcher list and the old one
    my $lc = List::Compare->new(
        {   lists    => [ $cached, $watchers ],
            unsorted => 1,
        }
    );

    my @lost   = $lc->get_unique;
    my @gained = $lc->get_complement;

    if (@lost) {
        $subject .= "\n\nUnwatchers: " . join ", ", @lost;
    }

    if (@gained) {
        $subject .= "\n\nNew watchers: " . join ", ", @gained;
    }

    # updates the cache and changes the title if the watchers have changed
    if ( @lost || @gained ) {
        $title = "Watcher count changed!";
        $cache->set( $cache_key => $watchers );
    }

    notify(
        {   name    => "Watcher-Watcher",
            title   => $title,
            sticky  => $sticky,
            subject => $subject,
            image   => "$FindBin::Bin/icon.png",
        }
    );

    sleep($delay_seconds);
    last if !$delay_seconds; # ends loop if number of seconds is < 1
    
    # updates the watcher list - this is done at the end of the loop to
    # avoid repeating the process after the intial setup outside the loop
    $mech->get("$base_url/$github_username/$github_repo/watchers");
    $watchers = decode_json( $mech->content )->{watchers};
}

exit 0;

sub test {

    push @{$watchers}, 'somenewguy';    # test new watchers
    shift @{$watchers};                 # test unwatchers

    say dump $cached;
    say dump $watchers;

}

sub parse_program_arguments {

    my $args = Getopt::Declare->new(<<'EOT');

    -u[sername] <username>	Github username to check
            { $::github_username = $username; }
    -r[epo]     <repo>	Github repo name to check
            { $::github_repo = $repo; }
    -t[ime]     <time>	Time in seconds between checks (default: 3600, 0: run once)
            { $::delay_seconds = $time; }
    -d[ebug]	        Turns on debug mode
            { $::debug = 1; }
    -s[ticky]	        Makes growls stay on screen until clicked
            { $::sticky = 1; }

EOT

    if ($debug) {
        say "\n***** Arguments *****";
        say "Username: $github_username";
        say "Repo:     $github_repo";
        say "Seconds:  $delay_seconds";
        say "Sticky:   $sticky";
        say "*********************\n";
    }

    if ( $github_username eq '' ) {
        say "\n*** A Github username is required.";
        exit 1;
    }

    if ( $github_repo eq '' ) {
        say "\n*** A Github repo is required.";
        exit 2;
    }
}
