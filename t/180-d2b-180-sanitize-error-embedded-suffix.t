use strict;
use warnings;
use Test::More;

use Browser::CLI ();

# D2B-180: sanitize_error's regex was anchored to \z, so it only ever
# stripped the LAST "at FILE line N." suffix. A message with an earlier,
# non-trailing suffix already embedded (e.g. Browser::Search::search()'s
# aggregated per-engine failure text, which can carry an inner die's own
# location suffix ahead of the outer die's own trailing one) kept that
# earlier fragment verbatim, leaking an internal file path/line to the
# CLI-facing error text. This test pins that every occurrence, not only
# the trailing one, is stripped.

{
    my $multi_suffix = "All search engines failed: bing (request failed: inner failure at -e line 5.) at lib/Browser/Search.pm line 90.";
    my $sanitized     = Browser::CLI::sanitize_error($multi_suffix);
    unlike( $sanitized, qr/\bat\s+\S+\s+line\s+\d+\./, 'no "at FILE line N." fragment survives anywhere in a multi-suffix error, embedded or trailing' );
    is( $sanitized, 'All search engines failed: bing (request failed: inner failure)', 'both suffixes stripped, remaining text preserved exactly' );
}

{
    my $trailing_only = "Some failure at Runner.pm line 42.";
    is( Browser::CLI::sanitize_error($trailing_only), 'Some failure', 'existing single-trailing-suffix case still stripped correctly (no regression)' );
}

{
    my $no_suffix = "A plain error with no location suffix at all";
    is( Browser::CLI::sanitize_error($no_suffix), $no_suffix, 'a message with no "at FILE line N." suffix is left untouched' );
}

{
    my $trailing_newline = "Trailing newline preserved as chomp behavior\n";
    is( Browser::CLI::sanitize_error($trailing_newline), 'Trailing newline preserved as chomp behavior', 'chomp still strips a trailing newline' );
}

done_testing();
