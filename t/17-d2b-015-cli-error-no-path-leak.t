use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::CLI;

# D2B-015: CLI error output must not leak internal source file paths and
# line numbers (Perl's own "at FILE line N." trailer) to the end user.

my $stderr = q{};
open my $error_fh, '>', \$stderr or die "Unable to open stderr scalar: $!";

my $rc = Browser::CLI::main(
    method   => 'GET',
    argv     => [],
    error_fh => $error_fh,
);
close $error_fh;

is( $rc, 2, 'main returns exit code 2 for a usage error' );
unlike( $stderr, qr{/lib/}, 'stderr output does not contain an internal lib/ path' );
unlike( $stderr, qr{line\s+\d+\.}, 'stderr output does not contain a Perl "line N." trailer' );
like( $stderr, qr{Missing URL}, 'stderr output still names the actual problem' );

done_testing();
