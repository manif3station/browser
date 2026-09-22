use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Runner::VersionCompare ();

# D2B-004: version_satisfies_spec must implement npm's caret semantics
# correctly for 0.x.y specs. Per npm semver: a caret range on 0.y.z (y>0)
# only allows patch bumps (same y, z>=given z); a caret range on 0.0.z
# allows no bumps at all (exact z match only). The pre-fix implementation
# only checked the major version, so both of these boundaries were wrong.

ok( !Browser::Runner::VersionCompare::version_satisfies_spec( '0.9.9', '^0.2.3' ), '^0.2.3 does not accept installed 0.9.9 (different minor)' );
ok( Browser::Runner::VersionCompare::version_satisfies_spec( '0.2.3', '^0.2.3' ), '^0.2.3 accepts an exact match' );
ok( Browser::Runner::VersionCompare::version_satisfies_spec( '0.2.9', '^0.2.3' ), '^0.2.3 accepts a later patch within the same minor' );
ok( !Browser::Runner::VersionCompare::version_satisfies_spec( '0.2.2', '^0.2.3' ), '^0.2.3 rejects an earlier patch within the same minor' );
ok( !Browser::Runner::VersionCompare::version_satisfies_spec( '0.3.0', '^0.2.3' ), '^0.2.3 rejects a later minor version' );

ok( !Browser::Runner::VersionCompare::version_satisfies_spec( '0.0.9', '^0.0.3' ), '^0.0.3 does not accept installed 0.0.9 (0.0.x caret allows no bumps)' );
ok( !Browser::Runner::VersionCompare::version_satisfies_spec( '0.1.0', '^0.0.3' ), '^0.0.3 does not accept installed 0.1.0' );
ok( Browser::Runner::VersionCompare::version_satisfies_spec( '0.0.3', '^0.0.3' ), '^0.0.3 accepts an exact match' );

# Unchanged behaviour for major versions 1 and above.
ok( Browser::Runner::VersionCompare::version_satisfies_spec( '1.9.9', '^1.2.3' ), '^1.2.3 still accepts installed 1.9.9 (unchanged for major >= 1)' );
ok( !Browser::Runner::VersionCompare::version_satisfies_spec( '2.0.0', '^1.2.3' ), '^1.2.3 still rejects a different major version' );

done_testing();
