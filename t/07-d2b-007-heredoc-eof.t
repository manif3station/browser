use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Runner;

# D2B-007 claims a controller script containing a bare "EOF" line breaks
# _run_controller_script's heredoc build. Verify this actually reproduces
# before treating it as confirmed.

{
    package FakePage;
    sub new { bless $_[1], $_[0] }
    sub url { $_[0]{url} }
}

my $page = FakePage->new( { url => 'https://example.test' } );

my $script = <<'SCRIPT';
my $note = "line one\nEOF\nline three";
return { note => $note };
SCRIPT

my $result = eval {
    Browser::Runner::_run_controller_script(
        $page,
        browser    => undef,
        playwright => undef,
        response   => undef,
        method     => 'GET',
        url        => 'https://example.test',
        script     => $script,
    );
};
my $error = $@;

ok( !$error, 'controller script containing a bare EOF line does not fail to compile' )
    or diag("Controller script failed: $error");
is( $result->{note}, "line one\nEOF\nline three", 'controller script result is intact when the script text contains EOF' )
    if !$error;

# The more realistic case: the controller script itself uses its own nested
# heredoc terminated by EOF. Perl's heredoc terminator is matched against the
# literal source text of Runner.pm at compile time, not against the runtime
# value of --script, and the whole substituted script is later handed to a
# single eval STRING that recompiles it fresh - so a nested heredoc's own EOF
# terminator is scanned inside that fresh compilation, unaffected by anything
# outside it. This confirms D2B-007's originally reported premise (a bare EOF
# line breaking the outer heredoc build) does not reproduce.
my $nested_script = <<'NESTED';
my $text = <<EOF;
some content
EOF
return { text => $text };
NESTED

my $nested_result = eval {
    Browser::Runner::_run_controller_script(
        $page,
        browser    => undef,
        playwright => undef,
        response   => undef,
        method     => 'GET',
        url        => 'https://example.test',
        script     => $nested_script,
    );
};
my $nested_error = $@;

ok( !$nested_error, 'a controller script with its own nested EOF-terminated heredoc does not fail to compile' )
    or diag("Controller script failed: $nested_error");
is( $nested_result->{text}, "some content\n", 'nested heredoc content in the controller script is preserved' )
    if !$nested_error;

done_testing();
