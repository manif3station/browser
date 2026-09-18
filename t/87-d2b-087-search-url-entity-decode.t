use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Search;

# D2B-087: Browser::Search's parsers (_parse_bing, _parse_google,
# _parse_duckduckgo) capture the href attribute value directly into the
# result's url field, but never decode HTML entities the way title/snippet
# do via _strip_tags. Real result markup routinely HTML-entity-encodes
# ampersands inside href query strings, so the returned url contained the
# literal three-character sequence '&amp;' instead of a single '&',
# corrupting the query string for any downstream consumer of that url.

{
    my $body = '<li class="b_algo"><h2><a href="https://www.bing.com/ck/a?u=abc&amp;ntb=1">Title</a></h2>'
      . '<div class="b_caption"><p>snippet</p></div>';
    my $results = Browser::Search::_parse_results( engine => 'bing', body => $body );
    is( $results->[0]{url}, 'https://www.bing.com/ck/a?u=abc&ntb=1', 'bing parser decodes an entity-encoded ampersand in the result url' );
}

{
    my $body = '<div class="g"><a href="https://example.com/x?a=1&amp;b=2"><h3>Title</h3></a>'
      . '<span class="VwiC3b">snippet</span></div>';
    my $results = Browser::Search::_parse_results( engine => 'google', body => $body );
    is( $results->[0]{url}, 'https://example.com/x?a=1&b=2', 'google parser decodes an entity-encoded ampersand in the result url' );
}

{
    my $body = '<a class="result__a" href="https://example.com/y?a=1&amp;b=2">Title</a>'
      . '<a class="result__snippet">snippet</a>';
    my $results = Browser::Search::_parse_results( engine => 'duckduckgo', body => $body );
    is( $results->[0]{url}, 'https://example.com/y?a=1&b=2', 'duckduckgo parser decodes an entity-encoded ampersand in the result url' );
}

done_testing();
