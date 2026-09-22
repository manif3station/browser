use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Search;

# D2B-161: closes the 4 remaining untested branches in
# lib/Browser/Search.pm flagged by D2B-160's own fold-back
# (branch coverage was 92.0% after D2B-160, unchanged before this
# ticket). No behavioral change - each branch already does the right
# thing; these tests prove it.

{
    package FakeEmptyErrorRunner;
    sub new { bless {}, shift }
    sub request { die "\n" }
}

# D2B-161 item 1: search()'s request-failure branch falls back to
# 'unknown error' when the die message is empty (lib/Browser/Search.pm:61).
eval {
    Browser::Search::search(
        query   => 'test query',
        engines => [ { name => 'bing', url => sub { 'https://example.test/?q=' . $_[0] } } ],
        runner  => FakeEmptyErrorRunner->new,
    );
};
like( $@, qr/bing \(request failed: unknown error\)/, 'search() falls back to "unknown error" when the runner dies with an empty message' );

# D2B-161 item 2: _parse_results defaults an omitted/undef body to the
# empty string instead of dying (lib/Browser/Search.pm:96).
my $parsed = Browser::Search::_parse_results(
    engine => { name => 'bing', parser => sub { return { rank => 1, snippet => $_[0] } } },
);
is_deeply( $parsed, { rank => 1, snippet => q{} }, '_parse_results defaults an omitted body to the empty string without dying' );

# D2B-161 item 3: _strip_tags(undef) returns the empty string
# (lib/Browser/Search.pm:149).
is( Browser::Search::_strip_tags(undef), q{}, '_strip_tags(undef) returns the empty string' );

# D2B-161 item 4: _decode_entities leaves an unknown named entity
# unescaped rather than dying or silently dropping it
# (lib/Browser/Search.pm:175).
is( Browser::Search::_decode_entities('&notarealentity;'), '&notarealentity;', '_decode_entities leaves an unknown named entity unescaped' );

done_testing();
