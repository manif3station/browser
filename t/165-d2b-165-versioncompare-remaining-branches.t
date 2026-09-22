use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Runner::VersionCompare;

# D2B-165: closes 2 reachable branches in
# lib/Browser/Runner/VersionCompare.pm found by a branch-coverage
# sweep extending the D2B-160/161/162/163/164 pattern. Branch coverage
# was 93.3% before this ticket. No behavioral change - each branch
# already does the right thing; these tests prove and document it.

ok( !Browser::Runner::VersionCompare::version_satisfies_spec( undef, '1.2.3' ), 'version_satisfies_spec returns false for an undef installed version' );
ok( !Browser::Runner::VersionCompare::version_satisfies_spec( '1.2.3', undef ), 'version_satisfies_spec returns false for an undef spec' );
ok( !Browser::Runner::VersionCompare::version_satisfies_spec( q{}, '1.2.3' ), 'version_satisfies_spec returns false for an empty-string installed version' );
ok( !Browser::Runner::VersionCompare::version_satisfies_spec( '1.2.3', q{} ), 'version_satisfies_spec returns false for an empty-string spec' );

ok( !Browser::Runner::VersionCompare::version_satisfies_spec( 'abc', '^1.2.3' ), 'version_satisfies_spec returns false for a non-numeric installed version under a caret-range spec' );

done_testing();
