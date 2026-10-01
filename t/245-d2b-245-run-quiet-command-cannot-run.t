use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use Test::More;

use Browser::Runner::NodeRuntime ();

# D2B-245: Browser::Runner::NodeRuntime::_run_quiet_command used $? >> 8 as
# the exit code. When system() cannot start the command at all (a missing
# binary) it returns -1 in $?, and -1 >> 8 is 72057594037927935, so the error
# said "exit code 72057594037927935" and never said the command had not been
# run. The reason ("No such file or directory") only showed up as a warning
# inside the captured stderr. This pins the corrected message and guards the
# two behaviours that must not change: a command that runs and exits with a
# status other than 0 keeps its "exit code N" message, and a command that
# succeeds returns 0.

my $missing = 'no-such-binary-d2b-245';

# A command that cannot be run.
{
    my $ok = eval { Browser::Runner::NodeRuntime::_run_quiet_command( $missing, '--version' ); 1 };
    my $error = $@;
    ok( !$ok, 'a command that cannot be run dies' );
    like( $error, qr/\Q$missing\E/, 'the message names the command' );
    like( $error, qr/could not be run/i, 'the message says the command could not be run' );
    like( $error, qr/No such file or directory/, 'the message gives the reason from $!' );
    unlike( $error, qr/exit code/i, 'the message does not print an exit code for a command that never ran' );
    unlike( $error, qr/72057594037927935/, 'the message does not print the shifted -1' );
}

# A command that runs and exits with status 3 keeps its existing message.
{
    my $ok = eval { Browser::Runner::NodeRuntime::_run_quiet_command( $^X, '-e', 'exit 3' ); 1 };
    my $error = $@;
    ok( !$ok, 'a command that exits with status 3 dies' );
    like( $error, qr/\ACommand failed: \Q$^X\E -e exit 3 \(exit code 3\)\n/, 'the existing message with the real exit code is unchanged' );
    like( $error, qr/captured stdout:\n/, 'the captured stdout section is still present' );
    like( $error, qr/captured stderr:\n/, 'the captured stderr section is still present' );
    unlike( $error, qr/could not be run/i, 'a command that ran is not reported as one that could not be run' );
}

# A command that succeeds returns 0.
{
    my $exit = eval { Browser::Runner::NodeRuntime::_run_quiet_command( $^X, '-e', 'exit 0' ) };
    is( $@, q{}, 'a command that succeeds does not die' );
    is( $exit, 0, 'a command that succeeds returns 0' );
}

done_testing();
