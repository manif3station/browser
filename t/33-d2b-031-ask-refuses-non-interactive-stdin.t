use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Runner;

# D2B-031: --ask/--askme blocks for Enter via 'scalar <$input_fh>'. If
# input_fh is already at EOF (closed, e.g. stdin redirected from
# /dev/null under an automated, non-interactive invocation), that read
# returns undef immediately with no blocking at all - the interactive
# pause silently no-ops and the caller proceeds as if the user had
# confirmed. This must instead die with a clear error naming the real
# problem (no interactive terminal available), rather than silently
# continuing as if nothing were wrong.

open my $eof_fh, '<', \(my $empty = q{}) or die "Unable to open empty scalar handle: $!";
scalar <$eof_fh>;    # consume to reach EOF, mirroring a fully-drained pipe

my $prompt_output = q{};
open my $prompt_fh, '>', \$prompt_output or die "Unable to open prompt scalar handle: $!";

eval {
    Browser::Runner::_await_user( input_fh => $eof_fh, prompt_fh => $prompt_fh );
};
like( $@, qr/stdin.*not interactive|interactive.*terminal/i, '_await_user refuses a closed/EOF input handle with a clear error instead of silently continuing' );

# A real, still-open handle with actual input (pressing Enter) must keep working exactly as before.
open my $real_fh, '<', \(my $enter = "\n") or die "Unable to open real input handle: $!";
my $ok = eval { Browser::Runner::_await_user( input_fh => $real_fh, prompt_fh => $prompt_fh ); 1 };
ok( $ok, '_await_user still works normally with a real, non-EOF input handle' ) or diag("Got error: $@");

done_testing();
