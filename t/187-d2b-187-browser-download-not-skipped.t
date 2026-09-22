use strict;
use warnings;

use Test::More;

# D2B-187: _install_node_runtime unconditionally set
# PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 before running npm install, and there
# is no other install path anywhere in this codebase (confirmed via grep
# across lib/ and cli/ for "playwright install"/"npx playwright install" -
# zero matches). PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD is Playwright's own
# documented env var for suppressing its npm postinstall step that
# downloads the actual chromium/firefox/webkit browser binaries, so on a
# genuinely fresh environment (no prior unskipped Playwright install ever
# run on the machine), --browser firefox/webkit and the CHROMIUM_BIN-
# unusable fallback would fail with "Executable doesn't exist" - the
# skill's own install path never fetches the binaries it depends on.
#
# This is a structural regression guard on the source's shape (mirroring
# t/34-d2b-034-dead-code-removed.t's own precedent for this class of fix),
# not a live network-dependent install repro - actually running an
# unskipped `npm install` would require real network egress inside the
# Docker test container, which this suite's other tests deliberately
# avoid (every Browser::Runner test mocks playwright_factory instead).

my $node_runtime_source = _slurp('lib/Browser/Runner/NodeRuntime.pm');

my ($install_body) = $node_runtime_source =~ /^sub _install_node_runtime \{(.*?)^\}/ms;
ok( defined $install_body, '_install_node_runtime sub body was found for structural analysis' );

unlike(
    $install_body,
    qr/\$ENV\{PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD\}\s*=/,
    '_install_node_runtime no longer assigns PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD within its own sub body, so npm install is free to run Playwright\'s own postinstall browser download'
);

done_testing();

sub _slurp {
    my ($path) = @_;
    open my $fh, '<', $path or die "Unable to open $path: $!";
    my $text = do { local $/; <$fh> };
    close $fh or die "Unable to close $path: $!";
    return $text;
}
