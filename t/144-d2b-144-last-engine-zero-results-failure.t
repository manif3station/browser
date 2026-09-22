use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Search;

# D2B-144: Browser::Search::search() only treated a substantial (>200
# char), non-CAPTCHA, zero-parsed-results page as a failure worth falling
# through to the next engine when $engine_index < $#engines - i.e. never
# for the last (or sole) engine tried. That engine's identical zero-result
# case must be recorded as a failure too, not returned as a "successful"
# empty search indistinguishable from a genuinely empty query.

{
    package FakeSearchRunner;
    sub new { bless { code => $_[1] }, $_[0] }
    sub request { my ( $self, %args ) = @_; return $self->{code}->(%args); }
}

# Sole engine, substantial non-CAPTCHA body, zero parsed results.
{
    my $error = eval {
        Browser::Search::search(
            query   => 'test query',
            engines => [ { name => 'duckduckgo', url => sub { 'https://example.test/?q=' . $_[0] } } ],
            runner  => FakeSearchRunner->new(
                sub { return { is_captcha => 0, body => '<html><body>' . ( 'unrelated content ' x 50 ) . '</body></html>' } }
            ),
        );
        1;
    } ? undef : $@;

    ok( $error, 'D2B-144: the sole engine\'s substantial zero-parsed-results body dies instead of returning a "successful" empty search' );
    like( $error, qr/All search engines failed/, 'D2B-144: the die uses the same aggregated-failure message as every other engine exhaustion case' );
    like( $error, qr/duckduckgo/,                'D2B-144: the die names the engine that failed to parse' );
    like( $error, qr/no results parsed/,          'D2B-144: the die explains it as a parse failure, not a generic error' );
}

# Last engine (of two), same substantial zero-parsed-results body -
# behaves identically to the sole-engine case above.
{
    my @requested;
    my $error = eval {
        Browser::Search::search(
            query   => 'test query',
            engines => [
                { name => 'bing',       url => sub { 'https://example.test/bing?q=' . $_[0] } },
                { name => 'duckduckgo', url => sub { 'https://example.test/ddg?q=' . $_[0] } },
            ],
            runner => FakeSearchRunner->new(
                sub {
                    my (%args) = @_;
                    push @requested, $args{url};
                    return { is_captcha => 0, body => '<html><body>' . ( 'unrelated content ' x 50 ) . '</body></html>' };
                }
            ),
        );
        1;
    } ? undef : $@;

    ok( $error, 'D2B-144: the last engine\'s substantial zero-parsed-results body dies instead of returning a "successful" empty search' );
    like( $error, qr/All search engines failed/, 'D2B-144: the die names both engines\' failures in the aggregated message' );
    like( $error, qr/bing/,                       'D2B-144: the first (non-last) engine\'s failure is still recorded' );
    like( $error, qr/duckduckgo/,                 'D2B-144: the second (last) engine\'s failure is now also recorded, not silently treated as success' );
    is( scalar @requested, 2, 'D2B-144: both engines were actually tried before dying' );
}

# Regression guard: a non-last engine's existing zero-results-fallback
# behavior (falls through to try the next engine, which succeeds) is
# completely unchanged.
{
    my @requested;
    my $result = Browser::Search::search(
        query   => 'test query',
        engines => [
            { name => 'bing',   url => sub { 'https://example.test/bing?q=' . $_[0] } },
            { name => 'google', url => sub { 'https://example.test/google?q=' . $_[0] } },
        ],
        runner => FakeSearchRunner->new(
            sub {
                my (%args) = @_;
                push @requested, $args{url};
                return { is_captcha => 0, body => '<html><body>' . ( 'unrelated content ' x 50 ) . '</body></html>' } if @requested == 1;
                return { is_captcha => 0, body => '<div class="g"><a href="https://example.com"><h3>Found</h3></a><span class="VwiC3b">snippet</span></div>' };
            }
        ),
    );
    is( $result->{engine_used}, 'google', 'D2B-144 regression guard: a non-last engine\'s zero-results-fallback still falls through to the next engine, unaffected by this fix' );
    is( scalar @{ $result->{results} }, 1, 'D2B-144 regression guard: the successful fallback engine\'s results are still returned' );
}

# The 200-character boundary: exactly 200 chars is trivial (success),
# 201 chars is substantial (failure) - the heuristic's ">" comparison,
# not ">=", is what this pins down.
{
    my $result = Browser::Search::search(
        query   => 'test query',
        engines => [ { name => 'duckduckgo', url => sub { 'https://example.test/?q=' . $_[0] } } ],
        runner  => FakeSearchRunner->new( sub { return { is_captcha => 0, body => 'x' x 200 } } ),
    );
    is_deeply( $result->{results}, [], 'D2B-144: a body of exactly 200 characters is still trivial - success with empty results, not a failure' );
}

{
    my $error = eval {
        Browser::Search::search(
            query   => 'test query',
            engines => [ { name => 'duckduckgo', url => sub { 'https://example.test/?q=' . $_[0] } } ],
            runner  => FakeSearchRunner->new( sub { return { is_captcha => 0, body => 'x' x 201 } } ),
        );
        1;
    } ? undef : $@;
    ok( $error, 'D2B-144: a body of 201 characters is substantial - dies as a failure, one character past the trivial-body threshold' );
}

done_testing();
