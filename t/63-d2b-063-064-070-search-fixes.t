use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Search;

{
    package FakeSearchRunner;
    sub new { bless { code => $_[1] }, $_[0] }
    sub request { my ( $self, %args ) = @_; return $self->{code}->(%args); }
}

# D2B-064: Browser::Search::search() must refuse a negative timeout_ms
# itself, not rely solely on the CLI layer (D2B-058).
eval {
    Browser::Search::search(
        query      => 'test query',
        engines    => [ { name => 'bing', url => sub { 'https://example.test/?q=' . $_[0] } } ],
        runner     => FakeSearchRunner->new( sub { return { is_captcha => 0, body => q{} } } ),
        timeout_ms => -5000,
    );
};
like( $@, qr/--timeout-ms/, 'search() refuses a negative timeout_ms' );
like( $@, qr/not be negative/, 'search() names the negativity problem clearly' );

# D2B-063: when an engine's markup no longer matches its parser (empty
# results over a substantial, non-captcha, non-failed body), search()
# must fall through to the next engine instead of silently returning
# empty results as if it were a genuine zero-result query.
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
    is( $result->{engine_used}, 'google', 'falls through to the next engine when the first parses to zero results over a substantial body' );
    is( scalar @{ $result->{results} }, 1, 'the second engine\'s results are returned' );
}

# The "is this the last engine" check must compare array position, not
# object identity - a caller-supplied engines list that repeats the exact
# same hashref (unusual, but not forbidden) must not cause an earlier
# occurrence to be mistaken for the final one.
{
    my $duplicate_engine = { name => 'bing', url => sub { 'https://example.test/bing?q=' . $_[0] } };
    my @requested;
    my $result = Browser::Search::search(
        query   => 'test query',
        engines => [ $duplicate_engine, $duplicate_engine ],
        runner  => FakeSearchRunner->new(
            sub {
                my (%args) = @_;
                push @requested, $args{url};
                return { is_captcha => 0, body => '<html><body>' . ( 'unrelated content ' x 50 ) . '</body></html>' } if @requested == 1;
                return { is_captcha => 0, body => '<li class="b_algo"><h2><a href="https://example.com">Found</a></h2><div class="b_caption"><p>snippet</p></div></li>' };
            }
        ),
    );
    is( scalar @{ $result->{results} }, 1, 'a duplicated engine hashref in the engines list still correctly falls through by position, not by reference identity' );
}

# The genuine last-resort case: if every engine parses to zero results
# (or the body really is trivial), search() still returns success with
# an empty result set rather than dying, since nothing else could help.
{
    my $result = Browser::Search::search(
        query   => 'test query',
        engines => [ { name => 'bing', url => sub { 'https://example.test/?q=' . $_[0] } } ],
        runner  => FakeSearchRunner->new( sub { return { is_captcha => 0, body => q{} } } ),
    );
    is_deeply( $result->{results}, [], 'a single trivially-empty-body engine still returns success with empty results rather than dying' );
}

# D2B-070: _parse_results should work whether or not the caller-supplied
# engine hash carries its own parser coderef, and default_engines()'
# entries should carry one so a new engine's parser lives with its URL
# builder instead of a separate name-dispatch table.
{
    my @default_engines = Browser::Search::default_engines();
    for my $engine (@default_engines) {
        ok( ref $engine->{parser} eq 'CODE', "default_engines()' $engine->{name} entry carries its own parser coderef" );
    }
}

# D2B-070 behavioral: _parse_results must actually CALL the engine's own
# parser coderef when present, not just have one sitting unused.
{
    my $custom_parser_called = 0;
    my $custom_engine = {
        name   => 'custom',
        parser => sub { $custom_parser_called++; return [ { url => 'https://example.test/custom', title => 'Custom', snippet => 'x', rank => 1 } ]; },
    };
    my $results = Browser::Search::_parse_results( engine => $custom_engine, body => 'irrelevant body' );
    is( $custom_parser_called, 1, '_parse_results calls the engine hash\'s own parser coderef when present' );
    is( $results->[0]{title}, 'Custom', 'the parser coderef\'s own results are returned unchanged' );
}

# D2B-070 behavioral: a caller-supplied engine hash with NO parser key
# must still fall back to the legacy name-based dispatch (backward
# compatibility for custom engines arrays, like the one D2B-026's own
# test passes to search()).
{
    my $results = Browser::Search::_parse_results(
        engine => { name => 'bing' },
        body   => '<li class="b_algo"><h2><a href="https://example.com">Legacy dispatch</a></h2><div class="b_caption"><p>via name, no parser key</p></div></li>',
    );
    is( $results->[0]{title}, 'Legacy dispatch', 'a caller-supplied engine hash with no parser key still resolves via the legacy name-based dispatch (_parse_bing)' );
}

# D2B-130: a scheduled hunt initially flagged this legacy name-based
# fallback as unreachable dead code, having traced only search()'s own
# default engines and Browser::CLI's %by_name map (both of which always
# carry a parser). Investigation found that conclusion wrong - this test,
# and the bare-string-engine test in t/22-d2b-026-search-fallback-and-parsing.t,
# already prove the fallback is genuinely reachable and intentional for any
# caller of search(engines => [...]) that hand-builds a parser-less engine
# hash or passes a bare engine-name string. No code change was made. The
# fixture below is distinctive (unlike an empty body, which would pass
# even if the duckduckgo dispatch branch were deleted) so this genuinely
# proves _parse_duckduckgo was reached, not just that the call didn't die.
{
    my $results = Browser::Search::_parse_results(
        engine => 'duckduckgo',
        body   => '<a class="result__a" href="https://example.com">Bare-string dispatch</a> <a class="result__snippet">via name, no engine hash at all</a>',
    );
    is( $results->[0]{title}, 'Bare-string dispatch', 'D2B-130: the by-name fallback for a bare-string engine genuinely dispatches to _parse_duckduckgo, not dead code' );
}

done_testing();
