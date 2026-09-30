use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Search;

# D2B-241: DuckDuckGo's html results wrap every link in its own redirector.
# Observed live (a genuine HTTP 200 response with 10 results), the hrefs
# look like //duckduckgo.com/l/?uddg=<percent-encoded target>&amp;rut=<token>
# - protocol-relative, and pointing at DuckDuckGo rather than the page - yet
# _parse_with_regex returned the decoded href untouched, so a DuckDuckGo
# result's url was not the reusable target url the docs promise.
#
# The three hrefs below are real ones from that response (rut token
# shortened; it is opaque). What is NOT real is the anchor markup around
# them: it is the shape the parser's regex already expects (the shape the
# other tests use), because a full genuine page could not be captured
# again - DuckDuckGo bot-checks repeated requests - so this pins the
# unwrapping, not the parser's match against today's live markup.

my ($ddg)  = grep { $_->{name} eq 'duckduckgo' } Browser::Search::default_engines();
my ($bing) = grep { $_->{name} eq 'bing' } Browser::Search::default_engines();

sub _ddg_body {
    return join q{}, map { qq{<a class="result__a" href="$_->[0]">$_->[1]</a> <a class="result__snippet">$_->[2]</a>\n} } @_;
}

sub _ddg { return Browser::Search::_parse_results( engine => $ddg, body => _ddg_body(@_) ) }

# 1. The real wrapped hrefs come back as the real target urls.
{
    my $results = _ddg(
        [ '//duckduckgo.com/l/?uddg=https%3A%2F%2Fwww.perl.org%2F&amp;rut=ea34812c26d0', 'The Perl Programming Language', 'Snippet one' ],
        [ '//duckduckgo.com/l/?uddg=https%3A%2F%2Fen.wikipedia.org%2Fwiki%2FPerl&amp;rut=9432cc6d6d2d', 'Perl - Wikipedia', 'Snippet two' ],
        [ '//duckduckgo.com/l/?uddg=https%3A%2F%2Fwww.geeksforgeeks.org%2Fperl%2Fperl%2Dprogramming%2Dlanguage%2F&amp;rut=791c20702c80', 'Perl Programming Language', 'Snippet three' ],
    );
    is( scalar @$results, 3, 'three results parsed' );
    is( $results->[0]{url}, 'https://www.perl.org/',                                        'a wrapped href yields the real target url' );
    is( $results->[1]{url}, 'https://en.wikipedia.org/wiki/Perl',                           'a target url containing a path is decoded' );
    is( $results->[2]{url}, 'https://www.geeksforgeeks.org/perl/perl-programming-language/', 'a percent-encoded hyphen (%2D) decodes to a hyphen' );
    is_deeply( [ map { $_->{rank} } @$results ], [ 1, 2, 3 ], 'ranks are unaffected' );
    is( $results->[0]{title},   'The Perl Programming Language', 'title is unaffected' );
    is( $results->[0]{snippet}, 'Snippet one',                   'snippet is unaffected' );
}

# 2. An absolute https:// wrapper is unwrapped too.
{
    my $results = _ddg( [ 'https://duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.test%2Fa%3Fb%3D1%26c%3D2&amp;rut=abc', 'T', 'S' ] );
    is( $results->[0]{url}, 'https://example.test/a?b=1&c=2', 'an absolute wrapper is unwrapped and its encoded query string decoded' );
}

# 3. Guards: things that must NOT change.
{
    my $clean = _ddg( [ 'https://example.test/plain', 'T', 'S' ] );
    is( $clean->[0]{url}, 'https://example.test/plain', 'a clean absolute href is unchanged' );

    my $no_param = _ddg( [ '//duckduckgo.com/l/?rut=abc', 'T', 'S' ] );
    is( $no_param->[0]{url}, '//duckduckgo.com/l/?rut=abc', 'a wrapper with no uddg parameter is returned unchanged' );

    my $empty = _ddg( [ '//duckduckgo.com/l/?uddg=&amp;rut=abc', 'T', 'S' ] );
    is( $empty->[0]{url}, '//duckduckgo.com/l/?uddg=&rut=abc', 'a wrapper with an empty uddg is returned unchanged (entity-decoded, as before)' );

    my $bad = eval { _ddg( [ '//duckduckgo.com/l/?uddg=%ZZbroken&amp;rut=abc', 'T', 'S' ] ) };
    ok( defined $bad, 'a malformed uddg value does not die' ) or diag($@);

    my $non_http = _ddg( [ '//duckduckgo.com/l/?uddg=javascript%3Aalert%281%29&amp;rut=abc', 'T', 'S' ] );
    is( $non_http->[0]{url}, '//duckduckgo.com/l/?uddg=javascript%3Aalert%281%29&rut=abc', 'a uddg target that is not an http(s) url is NOT unwrapped' );

    my $other_host = _ddg( [ '//example.test/l/?uddg=https%3A%2F%2Fevil.test%2F', 'T', 'S' ] );
    is( $other_host->[0]{url}, '//example.test/l/?uddg=https%3A%2F%2Fevil.test%2F', 'a uddg parameter on a host other than duckduckgo.com is NOT followed' );
}

# 4. Bing is untouched: a wrapper-shaped Bing href stays exactly as before.
{
    my $body = '<li class="b_algo"><h2><a href="https://www.bing.com/ck/a?u=abc&amp;ntb=1">T</a></h2><div class="b_caption"><p>S</p>';
    my $results = Browser::Search::_parse_results( engine => $bing, body => $body );
    is( $results->[0]{url}, 'https://www.bing.com/ck/a?u=abc&ntb=1', 'a Bing wrapper-shaped href is left as it was (out of scope)' );
}

done_testing();
