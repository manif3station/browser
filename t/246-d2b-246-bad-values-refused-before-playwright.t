use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use Test::More;

use Browser::Runner ();

# D2B-246: Browser::Runner::request created the playwright object (a Node
# runtime check, then Playwright itself) before it looked at --browser, and
# --wait-until was not looked at until the browser had been launched and a
# page opened. A mistyped value therefore cost seconds (measured in the test
# container: about 4 s for --wait-until bogus and 3.8 s for --browser safari,
# against about 60 ms for a value refused up front) and started a Node process
# and a browser for nothing. browser.pdf's Chromium-only check was already done
# before any of that (D2B-196). Both checks now run first.
#
# The factory below stands in for Playwright: it records that it was called
# and then stops the request, so a test can tell "refused up front" from
# "reached Playwright" without starting anything.

my $started = 0;
my $runner = Browser::Runner->new(
    playwright_factory => sub {
        $started++;
        die "playwright factory reached\n";
    },
);

sub attempt {
    my (%args) = @_;
    $started = 0;
    my $ok = eval { $runner->request( method => 'GET', url => 'http://example.invalid/', %args ); 1 };
    return ( $ok, $@, $started );
}

# A value that is not a supported browser type.
for my $bad ( 'safari', 'ie', q{} ) {
    my ( $ok, $error, $calls ) = attempt( browser => $bad );
    ok( !$ok, "--browser '$bad' is refused" );
    is( $calls, 0, "--browser '$bad' is refused before the playwright object is created" );
    is( $error =~ s/ at \S+ line \d+\.?\n?\z//r, "Unsupported browser type: $bad (expected one of: chrome chromium firefox webkit edge)", "--browser '$bad' keeps its message" );
}

# A value that is not a supported wait-until mode, on the commands that read it.
for my $method (qw(GET PNG PDF)) {
    my ( $ok, $error, $calls ) = attempt( method => $method, wait_until => 'bogus' );
    ok( !$ok, "$method: --wait-until bogus is refused" );
    is( $calls, 0, "$method: --wait-until bogus is refused before the playwright object is created" );
    like( $error, qr/\AUnsupported wait-until mode: bogus\b/, "$method: --wait-until bogus keeps its message" );
}

# Good values still reach Playwright, exactly as before.
for my $browser ( undef, 'chrome', 'Chrome', 'chromium', 'edge', 'firefox', 'webkit' ) {
    my $label = defined $browser ? $browser : 'omitted';
    my ( $ok, $error, $calls ) = attempt( defined $browser ? ( browser => $browser ) : () );
    is( $calls, 1, "--browser $label reaches the playwright factory" );
    is( $error, "playwright factory reached\n", "--browser $label is not refused" );
}
for my $mode (qw(load domcontentloaded networkidle)) {
    my ( $ok, $error, $calls ) = attempt( wait_until => $mode );
    is( $calls, 1, "--wait-until $mode reaches the playwright factory" );
}

# browser.post never reads --wait-until, so a bad one is not refused by the runner
# (the CLI refuses the flag itself); that must not change.
{
    my ( $ok, $error, $calls ) = attempt( method => 'POST', wait_until => 'bogus' );
    is( $calls, 1, 'POST does not refuse --wait-until (it never reads it) and still reaches the playwright factory' );
}

# browser.pdf's own up-front check is unchanged.
{
    my ( $ok, $error, $calls ) = attempt( method => 'PDF', browser => 'firefox' );
    is( $calls, 0, 'PDF with firefox is still refused before the playwright object is created' );
    like( $error, qr/browser\.pdf only supports Chromium-based browsers/, 'PDF with firefox keeps its message' );
}

done_testing();
