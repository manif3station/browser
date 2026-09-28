use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Runner::VersionCompare ();

# D2B-212: a caret spec with fewer than 3 version segments (^0.0, ^0)
# must widen the OMITTED trailing segments per npm's real X-range rules,
# not pin them to 0 the way version_parts' zero-padding did pre-fix.
# ^0.0  := >=0.0.0 <0.1.0 (any 0.0.x)
# ^0    := >=0.0.0 <1.0.0 (any 0.x)

ok( Browser::Runner::VersionCompare::version_satisfies_spec( '0.0.5', '^0.0' ), '^0.0 (omitted patch) accepts 0.0.5, not just 0.0.0' );
ok( Browser::Runner::VersionCompare::version_satisfies_spec( '0.0.0', '^0.0' ), '^0.0 still accepts the exact 0.0.0 boundary' );
ok( Browser::Runner::VersionCompare::version_satisfies_spec( '0.0.99', '^0.0' ), '^0.0 accepts a much later patch too - the range is unbounded above, not just "one more than 0"' );
ok( !Browser::Runner::VersionCompare::version_satisfies_spec( '0.1.0', '^0.0' ), '^0.0 rejects 0.1.0 (outside the widened 0.0.x range)' );

# Codex review: contrast with a fully-specified, nonzero patch boundary,
# so the "^0.0.2 still pins exactly" case isn't only proven at patch 0.
ok( Browser::Runner::VersionCompare::version_satisfies_spec( '0.0.2', '^0.0.2' ), '^0.0.2 (fully-specified, nonzero patch) accepts an exact match' );
ok( !Browser::Runner::VersionCompare::version_satisfies_spec( '0.0.3', '^0.0.2' ), '^0.0.2 (fully-specified, nonzero patch) rejects a later patch - still pinned, unlike ^0.0' );

ok( Browser::Runner::VersionCompare::version_satisfies_spec( '0.5.0', '^0' ), '^0 (omitted minor+patch) accepts 0.5.0, not just 0.0.0' );
ok( Browser::Runner::VersionCompare::version_satisfies_spec( '0.0.0', '^0' ), '^0 still accepts the exact 0.0.0 boundary' );
ok( !Browser::Runner::VersionCompare::version_satisfies_spec( '1.0.0', '^0' ), '^0 rejects 1.0.0 (different major)' );

# Unchanged: an explicit 0 in a fully-specified spec still means exactly 0,
# not a widened range - this is what distinguishes "omitted" from "written".
ok( !Browser::Runner::VersionCompare::version_satisfies_spec( '0.0.5', '^0.0.0' ), '^0.0.0 (fully-specified) still rejects 0.0.5 - unchanged D2B-004 behavior' );

done_testing();
