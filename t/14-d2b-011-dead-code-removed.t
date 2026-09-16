use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Runner;

# D2B-011: _run_command and _run_in_dir were defined but never called
# anywhere in the codebase - untestable-by-real-use dead code that cannot
# satisfy the project's 100% coverage gate honestly. They must be removed.

ok( !Browser::Runner->can('_run_command'), '_run_command has been removed as dead code' );
ok( !Browser::Runner->can('_run_in_dir'), '_run_in_dir has been removed as dead code' );

done_testing();
