use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::CLI;

# D2B-058: browser.search --timeout-ms accepted a negative value with no
# validation, unlike --max which already refuses a negative value in the
# same sub. A negative --timeout-ms reached Playwright's native timeout
# option unchecked instead of being refused by this skill's own clear
# validation message.

{
    package FakeSearchRunner;
    sub new { bless { calls => [] }, shift }
    sub request {
        my ( $self, %args ) = @_;
        push @{ $self->{calls} }, {%args};
        return { is_captcha => 0, body => q{} };
    }
}

eval { Browser::CLI::execute_search( argv => [ 'query', '--timeout-ms', '-1' ], runner => FakeSearchRunner->new() ) };
like( $@, qr/--timeout-ms/, 'execute_search refuses a negative --timeout-ms value' );
like( $@, qr/not be negative/, 'execute_search names the negativity problem clearly' );

my $runner = FakeSearchRunner->new();
Browser::CLI::execute_search( argv => [ 'query', '--timeout-ms', '3000' ], runner => $runner );
is( $runner->{calls}[0]{timeout_ms}, 3000, 'a valid non-negative --timeout-ms still reaches the runner unaffected' );

done_testing();
