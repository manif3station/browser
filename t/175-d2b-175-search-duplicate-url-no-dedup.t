use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Search;

# D2B-175: pins the current, deliberately-unchanged behavior that
# _parse_bing (and, via the shared _parse_results/truncation path in
# search(), every engine) does not deduplicate result entries sharing
# an identical URL - a realistic collision on a real search page (an
# ad slot plus the matching organic result, or a carousel repeat).
# This is a documented limitation (README.md/docs/usage.md), not a
# bug being fixed here - whether to actually deduplicate is left as a
# product decision for a possible follow-up ticket.

my $body = join q{},
  '<li class="b_algo"><h2><a href="https://example.com/x">First</a></h2><div class="b_caption"><p>Snippet one</p></div></li>',
  '<li class="b_algo"><h2><a href="https://other.com/y">Second</a></h2><div class="b_caption"><p>Snippet two</p></div></li>',
  '<li class="b_algo"><h2><a href="https://example.com/x">Third dup</a></h2><div class="b_caption"><p>Snippet three</p></div></li>';

my $results = Browser::Search::_parse_bing($body);

is( scalar @$results, 3, '_parse_bing returns all 3 result blocks, including the duplicate-URL one, with no deduplication' );
is( $results->[0]{url}, 'https://example.com/x', 'the first entry keeps its own URL' );
is( $results->[2]{url}, $results->[0]{url}, 'the third entry shares the identical URL with the first - both are kept as separate results, each still consuming its own rank/slot' );

done_testing();
