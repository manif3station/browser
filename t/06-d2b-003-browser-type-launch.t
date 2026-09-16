use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib 'lib';
use Browser::Runner;

# D2B-003: --launch_options()/_validated_browser_path() must not force a
# Chromium/Chrome executablePath onto a non-chrome browser type such as
# firefox or webkit, even when CHROMIUM_BIN is configured.

{
    my $temp_root = tempdir( CLEANUP => 1 );
    my $chrome_path = File::Spec->catfile( $temp_root, 'fake-chrome' );
    open my $fh, '>', $chrome_path or die "Unable to write fake chrome binary: $!";
    print {$fh} "#!/bin/sh\nexit 0\n";
    close $fh or die "Unable to close fake chrome binary: $!";
    chmod 0755, $chrome_path or die "Unable to chmod fake chrome binary: $!";

    local $ENV{CHROMIUM_BIN} = $chrome_path;

    my %firefox_launch = Browser::Runner::BrowserPath::_launch_options(
        browser  => 'firefox',
        headless => 1,
    );
    is( $firefox_launch{type}, 'firefox', 'launch options keep the requested firefox type' );
    ok(
        !exists $firefox_launch{executablePath},
        'launch options do not force the configured CHROMIUM_BIN executable onto a firefox launch'
    );

    my %webkit_launch = Browser::Runner::BrowserPath::_launch_options(
        browser  => 'webkit',
        headless => 1,
    );
    is( $webkit_launch{type}, 'webkit', 'launch options keep the requested webkit type' );
    ok(
        !exists $webkit_launch{executablePath},
        'launch options do not force the configured CHROMIUM_BIN executable onto a webkit launch'
    );

    my %chrome_launch = Browser::Runner::BrowserPath::_launch_options(
        browser  => 'chrome',
        headless => 1,
    );
    is( $chrome_launch{type}, 'chrome', 'launch options keep the requested chrome type' );
    is(
        $chrome_launch{executablePath}, $chrome_path,
        'launch options still apply CHROMIUM_BIN for an actual chrome launch (unchanged behaviour)'
    );

    my %chromium_launch = Browser::Runner::BrowserPath::_launch_options(
        browser  => 'chromium',
        headless => 1,
    );
    is( $chromium_launch{type}, 'chrome', 'launch options map chromium onto the Playwright chrome type' );
    is(
        $chromium_launch{executablePath}, $chrome_path,
        'launch options still apply CHROMIUM_BIN for a chromium launch (unchanged behaviour)'
    );
}

done_testing();
