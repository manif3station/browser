use strict;
use warnings;

use File::Spec;
use FindBin qw($Bin);
use Test::More;

use lib 'lib';
use Browser::Search;

# D2B-026: browser.search must fall back past any engine that comes back
# CAPTCHA-walled (per the runner's own is_captcha flag), report which
# engine actually served the results, and parse rank/title/url/snippet
# out of each engine's own result markup.

sub _fixture {
    my ($name) = @_;
    open my $fh, '<', File::Spec->catfile( $Bin, 'fixtures', $name ) or die "Unable to read fixture $name: $!";
    local $/;
    return <$fh>;
}

# --- Fallback: first engine walled, second engine clean ---
{
    my @requested;
    my $fake_runner = FakeSearchRunner->new(
        sub {
            my (%args) = @_;
            push @requested, $args{url};
            return { is_captcha => 1, body => q{} } if @requested == 1;
            return { is_captcha => 0, body => _fixture('search-google.html') };
        }
    );

    my $result = Browser::Search::search(
        query  => 'which mini PC can run a ~30B Qwen3 at 1M context',
        engines => [
            { name => 'bing',   url => sub { 'https://www.bing.com/search?q=' . $_[0] } },
            { name => 'google', url => sub { 'https://www.google.com/search?q=' . $_[0] } },
        ],
        runner => $fake_runner,
    );

    is( $result->{engine_used}, 'google', 'falls back to the second engine when the first is CAPTCHA-walled' );
    is_deeply( $result->{engines_tried}, [ 'bing', 'google' ], 'engines_tried records both engines in order' );
    is( scalar @{ $result->{results} }, 2, 'parses both results from the clean engine' );
    is( $result->{results}[0]{rank}, 1, 'first result is ranked 1' );
    is( $result->{results}[0]{title}, 'Best mini PCs for running a 30B model', 'first result title parsed' );
    is( $result->{results}[0]{url}, 'https://example.com/mini-pc-30b', 'first result url parsed' );
    like( $result->{results}[0]{snippet}, qr/unified memory/, 'first result snippet parsed' );
}

# --- All engines walled: structured, non-hanging error ---
{
    my $fake_runner = FakeSearchRunner->new( sub { return { is_captcha => 1, body => q{} } } );

    eval {
        Browser::Search::search(
            query   => 'test query',
            engines => [
                { name => 'bing',   url => sub { 'https://www.bing.com/search?q=' . $_[0] } },
                { name => 'google', url => sub { 'https://www.google.com/search?q=' . $_[0] } },
            ],
            runner  => $fake_runner,
        );
    };
    like( $@, qr/bing/,   'all-walled error names the first walled engine' );
    like( $@, qr/google/, 'all-walled error names the second walled engine' );
    like( $@, qr/--ask/,  'all-walled error points to --ask for interactive use' );
}

# --- An engine that dies (network error, runner exception) is treated like a wall, not a fatal abort ---
{
    my @requested;
    my $fake_runner = FakeSearchRunner->new(
        sub {
            my (%args) = @_;
            push @requested, $args{url};
            die "connection refused\n" if @requested == 1;
            return { is_captcha => 0, body => _fixture('search-google.html') };
        }
    );

    my $result = Browser::Search::search(
        query   => 'test query',
        engines => [
            { name => 'bing',   url => sub { 'https://www.bing.com/search?q=' . $_[0] } },
            { name => 'google', url => sub { 'https://www.google.com/search?q=' . $_[0] } },
        ],
        runner  => $fake_runner,
    );
    is( $result->{engine_used}, 'google', 'an engine whose request throws is skipped like a walled engine, not a fatal error' );
}

# --- --max 0 genuinely returns zero results, even when the engine has real matches ---
{
    my $fake_runner = FakeSearchRunner->new(
        sub { return { is_captcha => 0, body => _fixture('search-bing.html') } }
    );
    my $result = Browser::Search::search(
        query   => 'test query',
        engines => [ { name => 'bing', url => sub { 'https://www.bing.com/search?q=' . $_[0] } } ],
        runner  => $fake_runner,
        max     => 0,
    );
    is( scalar @{ $result->{results} }, 0, '--max 0 returns zero results, not the default 10' );
}

# --- --max caps the result count ---
{
    my $fake_runner = FakeSearchRunner->new(
        sub { return { is_captcha => 0, body => _fixture('search-bing.html') } }
    );
    my $result = Browser::Search::search(
        query   => 'test query',
        engines => [ { name => 'bing', url => sub { 'https://www.bing.com/search?q=' . $_[0] } } ],
        runner  => $fake_runner,
        max     => 1,
    );
    is( scalar @{ $result->{results} }, 1, '--max caps the number of returned results' );
}

# --- Per-engine parsers against each fixture ---
for my $case (
    [ 'bing',       'search-bing.html' ],
    [ 'google',     'search-google.html' ],
    [ 'duckduckgo', 'search-duckduckgo.html' ],
) {
    my ( $engine, $fixture ) = @$case;
    my $results = Browser::Search::_parse_results( engine => $engine, body => _fixture($fixture) );
    is( scalar @$results, 2, "$engine parser extracts both results from its fixture" );
    is( $results->[0]{title}, 'Best mini PCs for running a 30B model', "$engine parser extracts the first title" );
    is( $results->[0]{url}, 'https://example.com/mini-pc-30b', "$engine parser extracts the first url" );
    like( $results->[0]{snippet}, qr/unified memory/, "$engine parser extracts the first snippet" );
}

# --- An unrecognised engine name parses to no results rather than dying ---
{
    my $results = Browser::Search::_parse_results( engine => 'not-a-real-engine', body => 'anything' );
    is_deeply( $results, [], '_parse_results returns an empty list for an engine with no parser' );
}

package FakeSearchRunner;
sub new { my ( $class, $code ) = @_; return bless { code => $code }, $class; }
sub request { my ( $self, %args ) = @_; return $self->{code}->(%args); }

package main;
done_testing();
