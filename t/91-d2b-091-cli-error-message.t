use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::CLI;

# D2B-091: GetOptionsFromArray's failure path in both execute and
# execute_search discarded Getopt::Long's own specific rejection message
# (e.g. "Unknown option: bogus-flag") and replaced it with the generic
# literal "Invalid options" - a caller inspecting the raised error
# programmatically had no way to tell which option/value was rejected.

{
    package FakeRunner;
    sub new { bless {}, shift }
    sub request { die "FakeRunner::request should not be called\n" }
}

my $result = eval {
    Browser::CLI::execute(
        method => 'GET',
        argv   => [ 'http://example.com', '--bogus-flag' ],
        runner => FakeRunner->new(),
    );
};
my $error = $@;
ok( !$result, 'execute dies on an unrecognized option' );
like( $error, qr/bogus-flag/, 'execute\'s error names the specific rejected option, not just the generic "Invalid options" fallback' )
  or diag("Got error: $error");

$result = eval {
    Browser::CLI::execute_search(
        argv   => [ 'query', '--bogus-flag' ],
        runner => FakeRunner->new(),
    );
};
$error = $@;
ok( !$result, 'execute_search dies on an unrecognized option' );
like( $error, qr/bogus-flag/, 'execute_search\'s error names the specific rejected option, not just the generic "Invalid options" fallback' )
  or diag("Got error: $error");

done_testing();
