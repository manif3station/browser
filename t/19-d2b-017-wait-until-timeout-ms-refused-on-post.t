use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::CLI;

# D2B-017: browser.post must refuse --wait-until and --timeout-ms (only
# browser.get/browser.png read them via _goto_options), instead of
# silently accepting and ignoring them.

eval { Browser::CLI::execute( method => 'POST', argv => [ 'https://example.test', '--wait-until', 'load' ] ) };
like( $@, qr/--wait-until/, 'browser.post refuses --wait-until' );
like( $@, qr/browser\.get.*browser\.png|browser\.png.*browser\.get/, 'browser.post names browser.get/browser.png as the commands that read --wait-until' );

eval { Browser::CLI::execute( method => 'POST', argv => [ 'https://example.test', '--timeout-ms', '999' ] ) };
like( $@, qr/--timeout-ms/, 'browser.post refuses --timeout-ms' );

my $runner_calls = 0;
{
    package FakeRunner;
    sub new { bless {}, shift }
    sub request { $runner_calls++; return {}; }
}

Browser::CLI::execute(
    method => 'GET',
    argv   => [ 'https://example.test', '--wait-until', 'load' ],
    runner => FakeRunner->new,
);
is( $runner_calls, 1, "browser.get's own --wait-until handling is unaffected" );

$runner_calls = 0;
Browser::CLI::execute(
    method => 'PNG',
    argv   => [ 'https://example.test', '--timeout-ms', '999' ],
    runner => FakeRunner->new,
);
is( $runner_calls, 1, "browser.png's own --timeout-ms handling is unaffected" );

done_testing();
