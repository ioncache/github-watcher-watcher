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

use vars qw/$verbose $github_username $github_repo $delay_seconds $sticky/;

# some option defaults
$verbose           = 0;
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

# sets up the repository list
# either a single/list of repos from the commandline option
# or all the repos for the specified user
my $repositories = [];
if ( $github_repo ) {
    my @repos = ();
    if ( $github_repo =~ /,/) {
        @repos = split(',', $github_repo);
    }
    elsif ( $github_repo =~ / /){
        @repos = split(' ', $github_repo);
    }
    else {
        push @repos, $github_repo;
    }

    foreach my $repo (@repos) {
        push @{$repositories}, { name => $repo };
    }

    if ( $verbose ) {
        say dump $repositories;
    }
}
else {
    $mech->get("$base_url/$github_username/");
    $repositories = decode_json( $mech->content )->{repositories};
    if ( $verbose ) {
        say "Repositories for $github_username:";
        foreach my $repository (@{$repositories}) {
            say dump $repository;
            say $repository->{name};
        }
    }
}

# sets up the caches for each repo
foreach my $repository (@{$repositories}) {
    my $repo = $repository->{name};
    my $cache_key = $repo . '-watchers';
    my $cached = $cache->get($cache_key) || [];

    # only sets the cache to the list of watchers if it was previously empty
    if (! scalar @{$cached}) {
        $mech->get("$base_url/$github_username/$repo/watchers");
        my $watchers = decode_json( $mech->content )->{watchers};
        $cache->set( $cache_key => $watchers );
    }
    if ($verbose) {
        say "Cache for $repo has " . scalar @{$cached} . " watchers.";
        say "Cached watchers are:";
        say dump $cached;
    }
}

while (1) {
    
    foreach my $repository (@{$repositories}) {
        my $repo = $repository->{name};
        my $cache_key = $repo . '-watchers';
        $mech->get("$base_url/$github_username/$repo/watchers");
        my $watchers = decode_json( $mech->content )->{watchers};

        # sets some default Growl message information
        my $title   = "$repo: Watcher count idle.";
        my $subject = "Repo has " . @{$watchers} . " watchers.";
    
        # does some comparisons between the current watcher list and the old one
        my $lc = List::Compare->new(
            {   lists    => [ $cache->get($cache_key), $watchers ],
                unsorted => 1,
            }
        );
    
        my @lost   = $lc->get_unique;
        my @gained = $lc->get_complement;
    
        if (@lost) {
            $subject .= "\n\nUnwatchers: " . join ", ", @lost;
            if ($verbose) {
                say "Unwatchers:";
                say dump @lost;
            }
        }
    
        if (@gained) {
            $subject .= "\n\nNew watchers: " . join ", ", @gained;
            if ($verbose) {
                say "New watchers:";
                say dump @gained;
            }
        }
    
        # updates the cache and changes the title if the watchers have changed
        if ( @lost || @gained ) {
            $title = "$repo: Watcher count changed!";
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
    }

    sleep($delay_seconds);
    last if !$delay_seconds; # ends loop if number of seconds is < 1
}

exit 0;

#
# Helper Methods
#

sub parse_program_arguments {

    my $args = Getopt::Declare->new(<<'EOT');

    -u[sername] <username>	Github username to check
            { $::github_username = $username; }
    -r[epo]     <repo>	Github repo name to check
            { $::github_repo = $repo; }
    -t[ime]     <time>	Time (seconds) between checks (default: 3600, 0: run once)
            { $::delay_seconds = $time; }
    -v[erbose]	        Turns on verbose mode
            { $::verbose = 1; }
    -s[ticky]	        Makes growls stay on screen until clicked
            { $::sticky = 1; }

EOT

    if ($verbose) {
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
}
