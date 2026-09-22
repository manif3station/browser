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

# D2B-119 restructured the single-line "die ... if !$ok; return $exit;"
# into an "if (!$ok) { ... die ...; } return $exit;" block (to capture and
# report stdout/stderr on failure) - same contract, different shape. Like
# the original D2B-034 regex, the checks below are a structural
# regression guard on the source's shape, not a formal proof that no
# other failure/success path can exist (a Codex review round correctly
# pushed back on an earlier draft's comment overstating that) - the
# actual runtime contract (dies on failure, returns the exit code on
# success) is verified behaviorally by t/04-runner-unit.t's real
# success/failure calls against this function.
my ($quiet_command_body) = $node_runtime_source =~ /^sub _run_quiet_command \{(.*?)^\}/ms;
ok( defined $quiet_command_body, '_run_quiet_command sub body was found for structural analysis' );

my @command_failed_dies = $quiet_command_body =~ /\bdie\s+"Command failed:/g;
my @returns              = $quiet_command_body =~ /\breturn\b/g;
is( scalar(@command_failed_dies), 1, '_run_quiet_command contains exactly one "Command failed" die() in its source (the other die()s are defensive open()-failure guards, unrelated to this contract) - a structural guard, not a formal proof' );
is( scalar(@returns), 1, '_run_quiet_command contains exactly one return statement in its source - a structural guard, not a formal proof' );

like(
    $quiet_command_body,
    qr/if\s*\(\s*!\$ok\s*\)\s*\{.*?die\s+"Command failed:.*?\}\s*\n\s*unlink[^\n]*\n\s*return\s+\$exit;/s,
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
