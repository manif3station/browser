use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::CLI;

# D2B-041: Browser::CLI::execute_search's --engines parsing splits on a
# bare comma with no whitespace trimming, so a human-friendly value like
# '--engines "bing, google"' (a space after the comma) produces the
# engine name ' google' (leading space), which fails the exact-match
# lookup against the known engine names and dies with "Unknown engine".

{
    package FakeSearchRunner;
    sub new { bless { calls => [] }, shift }
    sub request {
        my ( $self, %args ) = @_;
        push @{ $self->{calls} }, $args{url};
        return { is_captcha => 0, body => '<div class="g"><a href="https://example.com/x"><h3>X</h3></a><span class="VwiC3b">Y</span></div>' };
    }
}

my $runner = FakeSearchRunner->new();
my $result = eval {
    Browser::CLI::execute_search(
        argv   => [ 'query', '--engines', 'bing, google' ],
        runner => $runner,
    );
};
ok( !$@, 'execute_search accepts --engines with whitespace around the comma instead of dying with "Unknown engine"' ) or diag("Got error: $@");
is( $result->{engine_used}, 'bing', 'the first engine name is trimmed and resolved correctly' ) if $result;

$runner = FakeSearchRunner->new();
$result = Browser::CLI::execute_search(
    argv   => [ 'query', '--engines', '  duckduckgo  ,  bing  ' ],
    runner => $runner,
);
like( $runner->{calls}[0], qr/duckduckgo\.com/, 'leading/trailing whitespace around every engine name in the list is trimmed' );

# D2B-086: the trim above only strips ASCII whitespace (Perl's \s by
# default). A trailing non-breaking space - plausible from copy-pasted
# text - survives the trim and causes a real engine name to be
# rejected as unknown. Codex review round 1 found the initial fix used
# the DECODED U+00A0 character ("\x{A0}"), but @ARGV arrives as raw,
# undecoded bytes (this codebase never decodes argv as UTF-8) - a
# non-breaking space typed/pasted as UTF-8 is the two-byte sequence
# \xC2\xA0, not the single decoded character, so this test uses the
# literal byte sequence to match the real CLI input path.
$runner = FakeSearchRunner->new();
$result = eval {
    Browser::CLI::execute_search(
        argv   => [ 'query', '--engines', "bing\xC2\xA0" ],
        runner => $runner,
    );
};
ok( !$@, 'execute_search accepts an engine name padded with a raw-UTF-8-byte non-breaking space instead of dying with "Unknown engine"' ) or diag("Got error: $@");
is( $result->{engine_used}, 'bing', 'a non-breaking-space-padded engine name (as raw UTF-8 bytes, matching how @ARGV actually arrives) is trimmed and resolved correctly' ) if $result;

done_testing();
