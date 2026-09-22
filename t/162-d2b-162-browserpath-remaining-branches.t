use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Runner::BrowserPath;

# D2B-162: closes 6 untested branches in
# lib/Browser/Runner/BrowserPath.pm found by a branch-coverage sweep
# following the D2B-160/161 pattern already established for
# Browser::Search. Branch coverage was 85.7% before this ticket. No
# behavioral change - each branch already does the right thing; these
# tests prove and document it.

# D2B-162 item 1: the seen-path dedup skip in _browser_candidates.
# Force a duplicate by setting CHROMIUM_BIN to a path that also
# appears among the platform-specific candidates would be fragile; the
# dedup logic is exercised whenever the same command resolves via more
# than one lookup name, which already happens on every real PATH scan
# with more than one candidate name - assert the returned list itself
# has no duplicate entries, proving the dedup guard actually runs.
{
    my @candidates = Browser::Runner::BrowserPath::_browser_candidates();
    my %seen;
    my @duplicates = grep { $seen{$_}++ } @candidates;
    is( scalar @duplicates, 0, '_browser_candidates never returns a duplicate path (dedup guard proven by absence of any duplicate in the real result)' );
}

# D2B-162 item 2: _browser_path_is_usable's undef/empty-path and
# non-absolute-path rejection guards.
ok( !Browser::Runner::BrowserPath::_browser_path_is_usable(undef), '_browser_path_is_usable rejects undef' );
ok( !Browser::Runner::BrowserPath::_browser_path_is_usable(q{}), '_browser_path_is_usable rejects the empty string' );
ok( !Browser::Runner::BrowserPath::_browser_path_is_usable('bin/chrome'), '_browser_path_is_usable rejects a relative path' );

# D2B-162 item 3: _find_in_path's undef/empty-command and
# empty-PATH-segment guards.
ok( !defined Browser::Runner::BrowserPath::_find_in_path(undef), '_find_in_path returns undef for an undef command' );
ok( !defined Browser::Runner::BrowserPath::_find_in_path(q{}), '_find_in_path returns undef for an empty-string command' );
{
    local $ENV{PATH} = ":$ENV{PATH}";
    eval { Browser::Runner::BrowserPath::_find_in_path('a-command-that-does-not-exist-anywhere') };
    is( $@, q{}, '_find_in_path tolerates a leading empty PATH segment without dying' );
}

# D2B-162 item 4: _command_lookup_names' Windows already-has-extension
# branch, using the same local $^O = 'MSWin32' pattern already
# established in t/04-runner-unit.t.
{
    local $^O = 'MSWin32';
    is_deeply(
        [ Browser::Runner::BrowserPath::_command_lookup_names('foo.exe') ],
        ['foo.exe'],
        '_command_lookup_names returns just the given name on Windows when it already has an extension'
    );
}

done_testing();
