use strict;
use warnings;

use Test::More;
use File::Spec;
use File::Basename qw(dirname);
use lib File::Spec->catdir( dirname(__FILE__), '..', 'lib' );

use Browser::Search ();
use Browser::CLI ();

# D2B-153: Browser::Search::_default_engines() (underscore-prefixed,
# private by this codebase's own convention) was called from outside its
# defining module - lib/Browser/CLI.pm:317, and two test files. Identical
# pattern to D2B-147's _sanitize_error -> public sanitize_error promotion.
# This is TDD red: default_engines() (public) does not exist yet.

ok( Browser::Search->can('default_engines'), 'Browser::Search exposes a public default_engines sub' );

my @engines = Browser::Search::default_engines();
is( scalar @engines, 3, 'default_engines() returns the 3 configured engines' );
my @names = sort map { $_->{name} } @engines;
is_deeply( \@names, [qw(bing duckduckgo google)], 'default_engines() returns bing/duckduckgo/google' );

ok( !Browser::Search->can('_default_engines'), 'the old private _default_engines no longer exists' );

my $repo_root = File::Spec->catdir( dirname(__FILE__), '..' );
for my $file (qw(lib/Browser/CLI.pm lib/Browser/Search.pm t/63-d2b-063-064-070-search-fixes.t t/24-d2b-027-duckduckgo-direct-url.t)) {
    my $path = File::Spec->catfile( $repo_root, $file );
    open my $fh, '<', $path or die "Unable to open $path: $!";
    my $text = do { local $/; <$fh> };
    close $fh;
    unlike( $text, qr/\b_default_engines\b/, "$file no longer references the private _default_engines name" );
}

done_testing();
