use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::CLI;

# D2B-127: the singular --engine option is pushed into @requested_names
# with no trimming at all, unlike --engines' list-parsing path (D2B-041/
# D2B-086), which strips leading/trailing ASCII whitespace and the
# literal UTF-8 non-breaking-space byte sequence. A copy-pasted or
# accidentally-padded single --engine value was rejected as unknown
# while the identical padded name given via --engines was correctly
# trimmed and accepted.

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
        argv   => [ 'query', '--engine', '  bing  ' ],
        runner => $runner,
    );
};
ok( !$@, 'execute_search accepts --engine padded with ASCII whitespace instead of dying with "Unknown engine" (D2B-127)' ) or diag("Got error: $@");
is( $result->{engine_used}, 'bing', 'a whitespace-padded single --engine name is trimmed and resolved correctly (D2B-127)' ) if $result;

# D2B-086's exact non-breaking-space scenario, applied to the singular
# flag - see t/41's own comment for why the literal \xC2\xA0 byte
# sequence (not the decoded \x{A0} character) is the correct match,
# since @ARGV arrives as raw, undecoded bytes.
$runner = FakeSearchRunner->new();
$result = eval {
    Browser::CLI::execute_search(
        argv   => [ 'query', '--engine', "bing\xC2\xA0" ],
        runner => $runner,
    );
};
ok( !$@, 'execute_search accepts a single --engine name padded with a raw-UTF-8-byte non-breaking space instead of dying with "Unknown engine" (D2B-127)' ) or diag("Got error: $@");
is( $result->{engine_used}, 'bing', 'a non-breaking-space-padded single --engine name is trimmed and resolved correctly (D2B-127)' ) if $result;

# Regression guard: a clean, unpadded --engine value must be completely
# unaffected by this fix.
$runner = FakeSearchRunner->new();
$result = Browser::CLI::execute_search(
    argv   => [ 'query', '--engine', 'bing' ],
    runner => $runner,
);
is( $result->{engine_used}, 'bing', 'a clean, unpadded --engine value is unaffected by the trim fix (D2B-127)' );

# D2B-127 (Codex review round 1): a whitespace-only --engine value must
# be refused with the same specific message --engines already gives an
# all-empty list, not fall through to a generic "Unknown engine: "
# lookup failure with a blank name.
eval {
    Browser::CLI::execute_search(
        argv => [ 'query', '--engine', '   ' ],
    );
};
like( $@, qr/--engine named no engine at all/, 'a whitespace-only --engine value is refused with a specific message, not a blank "Unknown engine" (D2B-127)' );

done_testing();
