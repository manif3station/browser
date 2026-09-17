use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Search;

# D2B-040: browser.search never passed timeout_ms through to the runner,
# so each engine attempt relied solely on Playwright's own internal
# default (~30s). With multiple default engines tried sequentially, a
# genuinely slow/unresponsive engine could stack multiple ~30s waits
# before the all-walled/real error surfaced - a real mismatch against
# README's "never hangs" wording. search() must pass a bounded
# timeout_ms to every engine attempt by default, and allow it to be
# overridden.

{
    package RecordingRunner;
    sub new { bless { calls => [] }, shift }
    sub request {
        my ( $self, %args ) = @_;
        push @{ $self->{calls} }, {%args};
        return { is_captcha => 0, body => q{} };
    }
}

my $runner = RecordingRunner->new();
Browser::Search::search(
    query   => 'test query',
    engines => [ { name => 'bing', url => sub { 'https://www.bing.com/search?q=' . $_[0] } } ],
    runner  => $runner,
);
ok( defined $runner->{calls}[0]{timeout_ms}, "search()'s request() call passes a defined timeout_ms by default" );
cmp_ok( $runner->{calls}[0]{timeout_ms}, '>', 0, 'the default timeout_ms is a real, positive bound' );
cmp_ok( $runner->{calls}[0]{timeout_ms}, '<=', 15000, 'the default timeout_ms is meaningfully shorter than stacking multiple Playwright ~30s defaults across several engines' );

$runner = RecordingRunner->new();
Browser::Search::search(
    query      => 'test query',
    engines    => [ { name => 'bing', url => sub { 'https://www.bing.com/search?q=' . $_[0] } } ],
    runner     => $runner,
    timeout_ms => 5000,
);
is( $runner->{calls}[0]{timeout_ms}, 5000, 'an explicit timeout_ms override is passed through to the runner unchanged' );

# --- CLI wiring: --timeout-ms is exposed on browser.search too ---
{
    require Browser::CLI;
    $runner = RecordingRunner->new();
    Browser::CLI::execute_search( argv => [ 'query', '--timeout-ms', '3000' ], runner => $runner );
    is( $runner->{calls}[0]{timeout_ms}, 3000, 'browser.search --timeout-ms overrides the default, matching browser.get/post/png\'s own flag' );
}

done_testing();
