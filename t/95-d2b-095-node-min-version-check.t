use strict;
use warnings;

use File::Temp qw(tempdir);
use Test::More;

use lib 'lib';
use Browser::Runner::NodeRuntime;

# D2B-095: nothing checked the system's actual `node` binary version
# before calling _ensure_node_runtime - an outdated Node only surfaced
# as whatever cryptic native error Playwright/require produced deep in
# its own module-loading chain. Playwright's own package.json declares
# "engines": { "node": ">=20" }, so this is the real, verified minimum.

is( Browser::Runner::NodeRuntime::_minimum_node_major_version(), 20,
    'the declared minimum matches the verified Playwright engines.node requirement' );

sub _with_fake_node {
    my ( $version_line, $code ) = @_;
    my $dir = tempdir( CLEANUP => 1 );
    my $fake_node = File::Spec->catfile( $dir, 'node' );
    open my $fh, '>', $fake_node or die "Unable to write fake node: $!";
    print {$fh} "#!/bin/sh\necho '$version_line'\n";
    close $fh;
    chmod 0755, $fake_node;

    local $ENV{PATH} = "$dir:$ENV{PATH}";
    return $code->();
}

_with_fake_node(
    'v18.19.0',
    sub {
        my $error = eval { Browser::Runner::NodeRuntime::_check_node_version(); 1 };
        ok( !$error, '_check_node_version dies when the system node is below the required minimum' );
        like( $@, qr/Node\.js v20\+ is required/,
            'the error names the required minimum version' );
        like( $@, qr/found v18/,
            'the error also names the actually-found version, not just the requirement' );
    }
);

_with_fake_node(
    'v20.11.0',
    sub {
        my $ok = eval { Browser::Runner::NodeRuntime::_check_node_version(); 1 };
        ok( $ok, '_check_node_version passes through unaffected when the system node meets the minimum' )
          or diag("Got error: $@");
    }
);

_with_fake_node(
    'v22.5.1',
    sub {
        my $ok = eval { Browser::Runner::NodeRuntime::_check_node_version(); 1 };
        ok( $ok, '_check_node_version passes through unaffected when the system node exceeds the minimum' )
          or diag("Got error: $@");
    }
);

# Codex review round 1 found a real bug: qx{node --version} can return
# undef (e.g. `node` is not on PATH at all, so the shell itself fails to
# exec it), and matching a regex against undef emits "Use of
# uninitialized value" - the die message itself was already graceful,
# but the warning still leaked. This must not warn.
{
    local $ENV{PATH} = '/nonexistent-path-for-this-test-only';
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };
    my $error = eval { Browser::Runner::NodeRuntime::_check_node_version(); 1 };
    ok( !$error, '_check_node_version dies when node is not found on PATH at all' );
    like( $@, qr/unrecognized 'node --version' output/,
        'the error message is the graceful unrecognized-output message, not a crash' );
    is( scalar @warnings, 0,
        'no "Use of uninitialized value" warning leaks when qx{node --version} itself fails to execute' );
}

done_testing();
