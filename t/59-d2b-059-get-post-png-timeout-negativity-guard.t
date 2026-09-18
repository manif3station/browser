use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::CLI;

# D2B-059: browser.get/browser.post/browser.png must refuse a negative
# --timeout-ms, mirroring the guard D2B-058 already added to
# browser.search's execute_search.

for my $method (qw(GET PNG POST)) {
    eval { Browser::CLI::execute( method => $method, argv => [ 'https://example.test', '--timeout-ms', '-1' ] ) };
    like( $@, qr/--timeout-ms/, "browser.$method refuses a negative --timeout-ms" );
    like( $@, qr/not be negative/, "browser.$method names the negativity problem clearly" );
}

# The negativity guard runs before the "only read by" guards, so POST with
# a negative --timeout-ms is refused for being negative, not for being the
# wrong method - the more specific, more useful error wins.
eval { Browser::CLI::execute( method => 'POST', argv => [ 'https://example.test', '--timeout-ms', '-1' ] ) };
unlike( $@, qr/only read by/, 'browser.POST with a negative --timeout-ms reports the negativity problem, not the wrong-method one' );

my $runner_calls = 0;
{
    package FakeRunner;
    sub new { bless {}, shift }
}
no warnings 'once';
local *FakeRunner::request = sub { $runner_calls++; return {}; };

Browser::CLI::execute(
    method => 'GET',
    argv   => [ 'https://example.test', '--timeout-ms', '3000' ],
    runner => FakeRunner->new,
);
is( $runner_calls, 1, 'a valid non-negative --timeout-ms still reaches the runner unaffected' );

done_testing();
