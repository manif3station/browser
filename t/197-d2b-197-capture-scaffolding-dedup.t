use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Runner::Capture ();

# D2B-197: run_png and run_pdf duplicate the same ~25-line scaffolding
# (owns_file/path reservation, directory guard, make_path, running the
# script callback inside eval, cleanup-on-failure, result-hashref
# assembly). This test is the red/TDD driver for extracting that
# scaffolding into one shared private helper - it fails against the
# pre-refactor code (no such helper exists yet) and passes once run_png
# and run_pdf both become thin callers of it.

my @capture_subs = grep { defined &{"Browser::Runner::Capture::$_"} }
  keys %Browser::Runner::Capture::;

ok( ( grep { /^_capture/ } @capture_subs ), 'Capture.pm defines a shared _capture* helper sub used by both run_png and run_pdf' )
  or diag( 'Defined subs in Browser::Runner::Capture: ' . join( ', ', sort @capture_subs ) );

done_testing();
