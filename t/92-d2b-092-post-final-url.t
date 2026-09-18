use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Runner;

# D2B-092: _run_post's final_url result field always reported
# about:blank in non-controller mode instead of the actual POST
# response URL. setContent() (used to inject the response body for
# display) never itself navigates the page, so $page->url() stayed
# at its pre-request value; only something that actually navigates
# the page afterwards (a controller script, the response body's own
# embedded script, or manual --ask interaction) changes it. The fix
# went through two rounds of Codex review, each finding a real hole:
# round 1's before/after URL-equality check was fooled by a script
# that deliberately navigated back to its starting URL; round 2's
# "did a --script argument exist" check missed navigation caused by
# the response body's own inline script (setContent evaluates
# embedded scripts) or by manual --ask navigation. The final fix
# checks the literal Playwright default "about:blank" sentinel
# instead of trying to infer *why* nothing navigated, since a fresh
# page/browser is launched per request() call in this codebase.

{
    package FakeResponse;
    sub new { bless $_[1], $_[0] }
    sub status { $_[0]{status} }
    sub text { $_[0]{body} }
    sub headers { $_[0]{headers} }
    sub url { $_[0]{url} }
}

{
    package FakeRequest;
    sub new { bless $_[1], $_[0] }
    sub post {
        my ( $self, $url, $options ) = @_;
        return FakeResponse->new(
            {
                status  => 200,
                body    => 'posted',
                headers => { 'content-type' => 'text/plain' },
                url     => $url,
            }
        );
    }
}

{
    package FakePage;
    sub new { bless $_[1], $_[0] }
    sub url { $_[0]{url} }
    sub title { $_[0]{title} }
    sub evaluate { return $_[0]{evaluate_return} }
    sub request { $_[0]{request} }
    sub setContent {
        my ( $self, $html ) = @_;
        $self->{set_content} = $html;
        # Simulates a response body whose own embedded <script> calls
        # location.href = ... on load - real Playwright's setContent()
        # evaluates embedded scripts, so this can navigate the page
        # with no --script argument at all.
        $self->{url} = $self->{navigate_on_set_content} if defined $self->{navigate_on_set_content};
        return 1;
    }
}

{
    package FakeBrowser;
    sub new { bless $_[1], $_[0] }
    sub newPage { $_[0]{page} }
}

{
    package FakePlaywright;
    sub new { bless $_[1], $_[0] }
    sub launch { return $_[0]{browser} }
    sub quit { return 1 }
}

my $page = FakePage->new(
    {
        url     => 'about:blank',
        request => FakeRequest->new( {} ),
        title   => 'Posted',
    }
);
my $playwright = FakePlaywright->new(
    { browser => FakeBrowser->new( { page => $page } ) },
);
my $runner = Browser::Runner->new( playwright_factory => sub { return $playwright } );

my $result = $runner->request(
    method => 'POST',
    url    => 'https://example.test/submit',
    data   => 'a=1',
);

is( $result->{final_url}, 'https://example.test/submit',
    'non-controller browser.post reports the actual POST response URL as final_url, not about:blank' );
isnt( $result->{final_url}, 'about:blank',
    'final_url is never the page\'s pre-request placeholder when no navigation happened' );

# Codex review round 1 found a real edge case in an earlier version of
# this fix: comparing the page's URL before/after the script phase
# for equality cannot tell "nothing navigated" apart from "a
# controller script deliberately navigated back to the same URL" -
# in the latter case that heuristic would wrongly substitute the
# response's URL instead of the script's real final page state. The
# final fix instead checks the literal "about:blank" sentinel (see
# lib/Browser/Runner.pm) rather than comparing URLs for equality, so
# this same-URL-navigation case (to a non-blank URL) must still
# report the page's own real URL, not the response's.
my $same_url_page = FakePage->new(
    {
        url     => 'https://example.test/original',
        request => FakeRequest->new( {} ),
        title   => 'Posted',
    }
);
my $same_url_playwright = FakePlaywright->new(
    { browser => FakeBrowser->new( { page => $same_url_page } ) },
);
my $same_url_runner = Browser::Runner->new( playwright_factory => sub { return $same_url_playwright } );

my $same_url_result = $same_url_runner->request(
    method     => 'POST',
    url        => 'https://example.test/submit',
    controller => 1,
    # Deliberately navigates back to the exact same URL the page was
    # already at before setContent() - the coincidence case where a
    # naive "did the URL change" check would be fooled.
    script     => q{ $page->{url} = 'https://example.test/original'; return 1; },
);
is( $same_url_result->{final_url}, 'https://example.test/original',
    'a controller script that navigates back to the same URL it started at reports that real page state, not the unrelated POST response URL' );

# Codex review round 2 found a second real hole: checking merely
# "did a --script argument exist" missed navigation caused by the
# response body's OWN embedded script (evaluated by setContent, with
# no --script given at all) - this must still report the real
# navigated URL, not the unrelated POST response URL.
my $embedded_script_page = FakePage->new(
    {
        url                      => 'about:blank',
        navigate_on_set_content  => 'https://example.test/redirected-by-body-script',
        request                  => FakeRequest->new( {} ),
        title                    => 'Posted',
    }
);
my $embedded_script_playwright = FakePlaywright->new(
    { browser => FakeBrowser->new( { page => $embedded_script_page } ) },
);
my $embedded_script_runner = Browser::Runner->new( playwright_factory => sub { return $embedded_script_playwright } );

my $embedded_script_result = $embedded_script_runner->request(
    method => 'POST',
    url    => 'https://example.test/submit',
);
is( $embedded_script_result->{final_url}, 'https://example.test/redirected-by-body-script',
    'a response body whose own embedded script navigates the page (no --script argument at all) reports that real navigated URL, not the unrelated POST response URL' );

done_testing();
