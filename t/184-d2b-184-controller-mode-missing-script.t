use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Runner;

# D2B-184: _run_script's own first line ('return if !defined
# $args{script}') fired BEFORE it ever checked $args{controller}, so
# _run_controller_script's own "Controller mode requires --script" die
# was unreachable for the omitted-flag case - only the explicit
# empty-string case (--script '') could ever trigger it (see D2B-158).
# browser.get/post/png --playwright (or --agent/--flow) given with no
# --script at all silently no-op'd instead of erroring.

my @evaluated;
{
    package FakePage;
    sub new { bless {}, shift }
    sub evaluate { my ( $self, $script ) = @_; push @evaluated, $script; return 'evaluated'; }
}

eval {
    Browser::Runner::_run_script(
        FakePage->new,
        controller => 1,
        script     => undef,
        browser    => bless( {}, 'FakeBrowser' ),
        playwright => bless( {}, 'FakePlaywright' ),
        method     => 'GET',
        url        => 'https://example.test',
    );
};
like( $@, qr/Controller mode requires --script/,
    'controller mode with --script entirely omitted now dies with the documented error, instead of silently no-oping' );

# Regression guard: plain (non-controller) mode omitting --script entirely
# must remain a silent no-op - this is intentional, correct behavior for
# plain JS mode and must not change.
my $result = eval { Browser::Runner::_run_script( FakePage->new ) };
is( $@, q{}, 'plain (non-controller) mode omitting --script entirely still does not die' );
is( $result, undef, 'plain (non-controller) mode omitting --script entirely still returns undef (no-op)' );
is( scalar @evaluated, 0, 'page->evaluate() was never called in either case' );

done_testing();
