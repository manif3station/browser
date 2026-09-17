use strict;
use warnings;

use Test::More;

# D2B-034: Browser::Runner::NodeRuntime::_run_quiet_command dies
# unconditionally on any nonzero exit and only ever returns on success
# (always 0). _browser_path_is_usable's "return 0 if $exit != 0;" check
# is therefore unreachable dead code - any failure already died and was
# caught by the preceding "return 0 if $@;" check. This misleadingly
# implies a return-code contract the function doesn't actually have.

my $node_runtime_source = _slurp('lib/Browser/Runner/NodeRuntime.pm');
like(
    $node_runtime_source,
    qr/die\s+"Command failed:.*if\s+!\$ok;\s*\n\s*return\s+\$exit;/s,
    '_run_quiet_command still dies unconditionally on failure and only returns on success (0), confirming the contract the dead-code removal relies on'
);

my $browser_path_source = _slurp('lib/Browser/Runner/BrowserPath.pm');
unlike(
    $browser_path_source,
    qr/return 0 if \$exit != 0;/,
    '_browser_path_is_usable no longer contains the unreachable "return 0 if $exit != 0" dead-code check'
);
like(
    $browser_path_source,
    qr/only returns on success|never returns a nonzero|only ever returns/i,
    '_browser_path_is_usable documents, in a comment, why only the eval/$@ check is needed'
);

done_testing();

sub _slurp {
    my ($path) = @_;
    open my $fh, '<', $path or die "Unable to open $path: $!";
    my $text = do { local $/; <$fh> };
    close $fh or die "Unable to close $path: $!";
    return $text;
}
