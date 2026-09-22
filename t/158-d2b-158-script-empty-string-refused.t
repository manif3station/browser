use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Runner;

# D2B-158: Browser::Runner::_run_script only checked !defined $args{script}
# before falling through to $page->evaluate('') in plain (non-controller)
# mode - an explicit empty-string --script value silently evaluated an
# empty script instead of being refused, unlike controller mode's
# _run_controller_script, which already refuses the same empty value with
# "Controller mode requires --script". TDD red: this is not yet fixed.

my @evaluated;
{
    package FakePage;
    sub new { bless {}, shift }
    sub evaluate { my ( $self, $script ) = @_; push @evaluated, $script; return 'evaluated'; }
}

eval { Browser::Runner::_run_script( FakePage->new, script => q{} ) };
like( $@, qr/\S/, '_run_script refuses an explicit empty-string --script in plain (non-controller) mode instead of silently evaluating it' );
is( scalar @evaluated, 0, 'the empty script never reached page->evaluate()' );

# Regression guard: omitting --script entirely must remain a silent no-op.
my $result = eval { Browser::Runner::_run_script( FakePage->new ) };
is( $@, q{}, '_run_script omitting --script entirely still does not die' );
is( $result, undef, '_run_script omitting --script entirely still returns undef (no-op)' );

# Regression guard: controller mode's existing empty-script refusal is unaffected.
eval {
    Browser::Runner::_run_script(
        FakePage->new,
        script     => q{},
        controller => 1,
        browser    => bless( {}, 'FakeBrowser' ),
        playwright => bless( {}, 'FakePlaywright' ),
        method     => 'GET',
        url        => 'https://example.test',
    );
};
like( $@, qr/Controller mode requires --script/, 'controller mode still refuses an empty script with its own established message' );

done_testing();
