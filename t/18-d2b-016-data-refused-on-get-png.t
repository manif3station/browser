use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::CLI;

# D2B-016: browser.get/browser.png must refuse --data (only browser.post
# reads it), instead of silently accepting and ignoring it.

eval { Browser::CLI::execute( method => 'GET', argv => [ 'https://example.test', '--data', 'x=1' ] ) };
like( $@, qr/--data/, 'browser.get refuses --data' );
like( $@, qr/browser\.post/, 'browser.get names browser.post as the command that reads --data' );

eval { Browser::CLI::execute( method => 'PNG', argv => [ 'https://example.test', '--data', 'x=1' ] ) };
like( $@, qr/--data/, 'browser.png refuses --data' );
like( $@, qr/browser\.post/, 'browser.png names browser.post as the command that reads --data' );

my $runner_calls = 0;
{
    package FakeRunner;
    sub new { bless {}, shift }
    sub request { $runner_calls++; return {}; }
}
no warnings 'once';
local *FakeRunner::request = sub { $runner_calls++; return {} };

Browser::CLI::execute(
    method => 'POST',
    argv   => [ 'https://example.test', '--data', 'x=1' ],
    runner => FakeRunner->new,
);
is( $runner_calls, 1, 'browser.post --data is unaffected and still reaches the runner' );

done_testing();
