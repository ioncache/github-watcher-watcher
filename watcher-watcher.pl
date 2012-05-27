#!/usr/bin/env perl

use FindBin;

use CHI;
use Data::Printer;
use Getopt::Declare;
use Growl::Tiny qw( notify );
use JSON;
use List::Compare;
use Modern::Perl;
use Perl6::Junction qw( none );
use WWW::Mechanize;
use WWW::Mechanize::Cached;

my $mech_class = 'WWW::Mechanize';
my $mech       = $mech_class->new;

use vars qw/$verbose $github_username $github_repo $delay_seconds $sticky/;

# some option defaults
$verbose         = 0;
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

# gets a list of the all the repositories for username
# if no repo name is given all repos from this list will be used
# if a repo name is given, it will be checked against this list and an error
# will be thrown if the repo name is not found -- this makes for a nicer
# error than the one github throws back
$mech->get( "$base_url/$github_username/" );
my $github_repositories = decode_json( $mech->content )->{repositories};
my @repositories        = ();
foreach my $repo ( @{$github_repositories} ) {
    push @repositories, $repo->{name};
}

if ( $verbose ) {
    use Data::Printer;
    p $verbose;
    say "\nRepositories owned by $github_username:";
    p @repositories;
}

# if commandline repo name(s) list exists, use that list instead of the
# entire repo list for the user
if ( $github_repo ) {
    my @repos = ();
    if ( $github_repo =~ /,/ ) {
        $github_repo =~ s{\s}{};
        @repos = split( ',', $github_repo );
    }
    elsif ( $github_repo =~ / / ) {
        @repos = split( ' ', $github_repo );
    }
    else {
        @repos = ( $github_repo );
    }

    my @valid_repos = ();
    foreach my $repo ( @repos ) {
        if ( none( @repositories ) eq $repo ) {
            say "\n*** $github_username does not own a repo called: $repo"
                if $verbose;
        }
        else {
            push @valid_repos, $repo;
        }
    }

    @repositories = @valid_repos;
    if ( !@repositories ) {
        say
            "\n*** $github_username does not own any of the specified repositories.";
        exit 2;
    }

    if ( $verbose ) {
        say "\nRepos to be watched:";
        p @repositories;
    }
}

# sets up the caches for each repo
foreach my $repo ( @repositories ) {
    my $cache_key = cache_key( $repo );
    my $cached = $cache->get( $cache_key ) || [];

    # only sets the cache to the list of watchers if it was previously empty
    if ( !scalar @{$cached} ) {
        $mech->get( "$base_url/$github_username/$repo/watchers" );
        my $watchers = decode_json( $mech->content )->{watchers};
        $cache->set( $cache_key => $watchers );
    }
    if ( $verbose ) {
        say "\nCache for $repo has " . scalar @{$cached} . " watchers.";
        say "Cached watchers are:";
        p $cached;
    }
}

while ( 1 ) {

    foreach my $repo ( @repositories ) {
        my $cache_key = cache_key( $repo );
        $mech->get( "$base_url/$github_username/$repo/watchers" );
        my $watchers = decode_json( $mech->content )->{watchers};

        # sets some default Growl message information
        my $title   = "$repo: Watcher count idle.";
        my $subject = "Repo has " . @{$watchers} . " watchers.";

      # does some comparisons between the current watcher list and the old one
        my $lc = List::Compare->new(
            {   lists    => [ $cache->get( $cache_key ), $watchers ],
                unsorted => 1,
            }
        );

        my @lost   = $lc->get_unique;
        my @gained = $lc->get_complement;

        if ( @lost ) {
            $subject .= "\n\nUnwatchers: " . join ", ", @lost;
            if ( $verbose ) {
                say "Unwatchers:";
                p @lost;
            }
        }

        if ( @gained ) {
            $subject .= "\n\nNew watchers: " . join ", ", @gained;
            if ( $verbose ) {
                say "New watchers:";
                p @gained;
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

        # slight delay between growls when watching multiple repos
        sleep( 1 );
    }

    sleep( $delay_seconds );
    last if !$delay_seconds;    # ends loop if number of seconds is < 1
}

sub cache_key {
    my $repo = shift;
    return join "-", $github_username, $repo, 'watchers';
}

exit 0;

#
# Helper Methods
#

sub parse_program_arguments {

    my $args = Getopt::Declare->new( <<'EOT');

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

    if ( $verbose ) {
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
