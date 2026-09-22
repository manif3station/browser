use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Runner::VersionCompare ();

# D2B-037: version_satisfies_spec only understands an exact version, '*',
# 'latest', or a caret ('^') range. Any other real npm range syntax (tilde
# ranges, comparison operators, space-separated ranges) falls through to a
# plain string-equality check against $installed, which is silently wrong
# rather than an honest "I don't understand this spec" signal.

for my $spec ( '~1.2.0', '>=1.2.0', '<=1.2.0', '>1.2.0', '<1.2.0', '=1.2.0', '>=1.2.0 <2.0.0', '1.2.x', '1.2.3 || 2.0.0', '1.2.3 - 2.0.0' ) {
    eval { Browser::Runner::VersionCompare::version_satisfies_spec( '1.2.5', $spec ) };
    like( $@, qr/Unsupported version spec/, "version_satisfies_spec dies clearly on unsupported spec syntax '$spec' instead of silently mismatching" );
}

# Exact versions, '*', 'latest', and caret ranges must keep working exactly as before.
ok( Browser::Runner::VersionCompare::version_satisfies_spec( '1.2.5', '1.2.5' ), 'exact version specs still work' );
ok( !Browser::Runner::VersionCompare::version_satisfies_spec( '1.2.5', '1.2.6' ), 'exact version mismatches still rejected' );
ok( Browser::Runner::VersionCompare::version_satisfies_spec( '1.2.5', '*' ), 'wildcard specs still work' );
ok( Browser::Runner::VersionCompare::version_satisfies_spec( '1.2.5', 'latest' ), 'latest specs still work' );
ok( Browser::Runner::VersionCompare::version_satisfies_spec( '1.2.5', '^1.0.0' ), 'caret ranges still work' );

done_testing();
