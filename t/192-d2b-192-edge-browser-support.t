use strict;
use warnings;

use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib 'lib';
use Browser::Runner::BrowserPath;

# D2B-192: --browser edge is not recognized at all - @SUPPORTED_BROWSER_TYPES
# only lists chrome/chromium/firefox/webkit. Playwright launches Microsoft
# Edge not as its own browser type but by launching Chromium with
# launch({channel: 'msedge'}) - so an edge request must resolve to
# type=>'chrome' plus channel=>'msedge', and must NOT get an
# executablePath even if CHROMIUM_BIN is configured (channel and
# executablePath are mutually exclusive in Playwright's own launch() API).

{
    my $temp_root = tempdir( CLEANUP => 1 );
    my $chrome_path = File::Spec->catfile( $temp_root, 'fake-chrome' );
    open my $fh, '>', $chrome_path or die "Unable to write fake chrome binary: $!";
    print {$fh} "#!/bin/sh\nexit 0\n";
    close $fh or die "Unable to close fake chrome binary: $!";
    chmod 0755, $chrome_path or die "Unable to chmod fake chrome binary: $!";

    local $ENV{CHROMIUM_BIN} = $chrome_path;

    my %edge_launch = eval { Browser::Runner::BrowserPath::_launch_options( browser => 'edge', headless => 1 ) };
    ok( !$@, '--browser edge is accepted instead of dying with "Unsupported browser type"' ) or diag("Got error: $@");
    is( $edge_launch{type}, 'chrome', 'edge resolves to Playwright\'s chrome launch type' ) if %edge_launch;
    is( $edge_launch{channel}, 'msedge', 'edge sets the msedge channel option' ) if %edge_launch;
    ok( !exists $edge_launch{executablePath}, 'edge does not get an executablePath even with CHROMIUM_BIN configured' ) if %edge_launch;

    my %edge_launch_mixed_case = eval { Browser::Runner::BrowserPath::_launch_options( browser => 'EDGE', headless => 1 ) };
    ok( !$@, '--browser EDGE (mixed case) is accepted the same as lowercase edge' ) or diag("Got error: $@");
    is( $edge_launch_mixed_case{channel}, 'msedge', 'mixed-case Edge also resolves to the msedge channel' ) if %edge_launch_mixed_case;

    # Sanity: chrome itself is unaffected and still gets executablePath, no channel.
    my %chrome_launch = Browser::Runner::BrowserPath::_launch_options( browser => 'chrome', headless => 1 );
    is( $chrome_launch{executablePath}, $chrome_path, 'a plain chrome launch is unaffected and still gets CHROMIUM_BIN as executablePath' );
    ok( !exists $chrome_launch{channel}, 'a plain chrome launch never gets a channel option' );
}

done_testing();
