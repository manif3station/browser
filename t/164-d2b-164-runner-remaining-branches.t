use strict;
use warnings;

use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib 'lib';
use Browser::Runner;

# D2B-164: closes 4 reachable branch groups in lib/Browser/Runner.pm
# found by a branch-coverage sweep extending the D2B-160/161/162/163
# pattern. Branch coverage was 92.3% before this ticket. No behavioral
# change - each branch already does the right thing; these tests prove
# and document it.

{
    package FakePage;
    sub new { bless $_[1], $_[0] }
    sub goto { return $_[0]{response} }
    sub url { $_[0]{url} }
    sub title { $_[0]{title} }
    sub content { $_[0]{content} }
    sub evaluate { return $_[0]{evaluate_return} }
    sub screenshot {
        my ( $self, $options ) = @_;
        if ( my $path = $options->{path} ) {
            open my $fh, '>', $path or die "Unable to write fake screenshot $path: $!";
            print {$fh} "fake png\n";
            close $fh;
        }
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

# D2B-164 items 1+2+3: _run_png with a FakePage whose goto() returns a
# falsy value (no response object at all) - exercises both the
# make_path-for-a-missing-nested-directory branch (a screenshot path
# under a directory that does not exist yet) and the $response ? : ...
# false branches for headers/status.
{
    my $temp   = tempdir( CLEANUP => 1 );
    my $nested = File::Spec->catfile( $temp, 'nested', 'dir', 'shot' );
    my $page   = FakePage->new( { response => undef, url => 'https://example.test/final', title => 'Example' } );
    my $playwright = FakePlaywright->new( { browser => FakeBrowser->new( { page => $page } ) } );
    my $runner = Browser::Runner->new( playwright_factory => sub { return $playwright } );

    my $result = $runner->request( method => 'PNG', url => 'https://example.test', file => $nested );

    ok( -d File::Spec->catdir( $temp, 'nested', 'dir' ), '_run_png creates a missing nested screenshot directory' );
    is_deeply( $result->{headers}, {}, '_run_png degrades headers to an empty hashref when goto() returns a falsy response' );
    is( $result->{status}, undef, '_run_png degrades status to undef when goto() returns a falsy response' );
}

# D2B-164 item 4: _is_captcha_page's "verify you are human" phrase - the
# only one of its 4 recognized phrases never directly tested (the other
# 3 - captcha, recaptcha, unusual traffic - already are).
ok( Browser::Runner::_is_captcha_page( title => 'Please verify you are human', body => q{} ), '_is_captcha_page detects the "verify you are human" title phrase' );

# D2B-164 item 5: _response_document's undef-body default - only
# reachable via a direct call, since _run_post always passes a defined
# body in production.
my $doc = Browser::Runner::_response_document( body => undef, content_type => 'text/html' );
is( $doc, q{}, '_response_document defaults an undef body to the empty string without dying' );

done_testing();
