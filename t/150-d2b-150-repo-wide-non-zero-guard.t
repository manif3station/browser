use strict;
use warnings;

use Test::More;
use Cwd qw(abs_path);
use File::Find qw(find);
use File::Spec;
use File::Basename qw(dirname basename);
use File::Temp qw(tempdir);

# D2B-150: README.md's Edge Cases list (line 442) was a third remaining
# instance of the "non-zero" wording D2B-148/D2B-149 already fixed
# elsewhere - missed by D2B-149's own closing grep because that check's
# --include glob pattern did not actually match README.md. This test
# replaces that fragile shell-glob check with a genuinely repo-wide
# File::Find scan, so a future instance can't slip through the same way.
#
# Codex review round: matched case-sensitively (missed "Non-zero"/
# "NON-ZERO") and hardcoded this file's own path in the exclusion list
# rather than deriving it from __FILE__ - fixed both. A second round
# caught that an open() failure (e.g. a permission-denied file) used
# die, which would abort the whole test program uncleanly rather than
# recording a single test failure - replaced with fail()+next/return.
#
# D2B-234: the scan could pass vacuously - a missing directory was
# skipped silently and nothing asserted any file was actually visited, so
# an empty scan looked identical to a clean one (the same class of
# weakness as D2B-232). The scan now lives in scan_for_non_zero(), which
# reports how many files it read and which directories were missing, and
# the assertions at the bottom check both.

my $repo_root = abs_path( File::Spec->catdir( dirname(__FILE__), '..' ) );
my $this_file = abs_path(__FILE__);

# Changes is a historical changelog - each dated entry is a record of
# what was true (and how it was worded) at that release, not something
# to retroactively edit. t/148/149's own doc-consistency tests
# legitimately contain the literal phrase "non-zero" as the pattern they
# check for ABSENCE of - scanning them for it would be circular. This
# file excludes itself via __FILE__ rather than hardcoding its own name.
sub scan_for_non_zero {
    my ($root) = @_;

    my %excluded_files = map { $_ => 1 } (
        File::Spec->catfile( $root, 'Changes' ),
        File::Spec->catfile( $root, 't', '148-d2b-148-exit-status-pod-names-code.t' ),
        File::Spec->catfile( $root, 't', '149-d2b-149-non-zero-wording-fixed.t' ),
        $this_file,
    );

    my ( @offending_files, @unreadable_files, @missing_dirs, @empty_dirs );
    my $scanned = 0;

    my $check = sub {
        my ($path) = @_;
        open my $fh, '<', $path or do { push @unreadable_files, "$path: $!"; return; };
        my $text = do { local $/; <$fh> };
        close $fh;
        $scanned++;
        push @offending_files, $path if $text =~ /non-zero/i;
    };

    for my $dir (qw(cli docs lib t)) {
        my $full_dir = File::Spec->catdir( $root, $dir );
        if ( !-d $full_dir ) {
            push @missing_dirs, $dir;
            next;
        }
        my $scanned_before = $scanned;
        find(
            {
                no_chdir => 1,
                wanted   => sub {
                    return unless -f $_;
                    return if $excluded_files{$_};
                    $check->($_);
                },
            },
            $full_dir
        );
        push @empty_dirs, $dir if $scanned == $scanned_before;
    }
    for my $top_level_file (qw(README.md SKILLS.md)) {
        my $path = File::Spec->catfile( $root, $top_level_file );
        next if $excluded_files{$path};
        $check->($path);
    }

    return {
        scanned      => $scanned,
        offending    => \@offending_files,
        unreadable   => \@unreadable_files,
        missing_dirs => \@missing_dirs,
        empty_dirs   => \@empty_dirs,
    };
}

my $result = scan_for_non_zero($repo_root);

is( scalar @{ $result->{unreadable} }, 0, 'every file scanned could actually be opened for reading' )
  or diag( 'Unreadable files: ' . join( ', ', @{ $result->{unreadable} } ) );

is_deeply( $result->{offending}, [], 'no file under cli/, docs/, lib/, t/, README.md, or SKILLS.md still says the vague "non-zero" (Changes and the doc-consistency test files themselves are the only allowed exceptions)' )
  or diag( "Files still containing 'non-zero': " . join( ', ', map { basename($_) } @{ $result->{offending} } ) );

cmp_ok( $result->{scanned}, '>', 0, 'the scan visited at least one file (so a clean result is not vacuous)' );
is_deeply( $result->{missing_dirs}, [], 'cli/, docs/, lib/ and t/ all exist under the repo root' );

my $empty_root = tempdir( CLEANUP => 1 );
my $none       = scan_for_non_zero($empty_root);
is( $none->{scanned}, 0, 'scanning a tree with nothing in it visits no files' );
is_deeply( [ sort @{ $none->{missing_dirs} } ], [qw(cli docs lib t)], 'an empty tree is reported as missing every scanned directory' );

# D2B-235: the scanned > 0 check above is satisfied by README.md and
# SKILLS.md alone (they are counted too), so a directory that exists but
# holds nothing scannable would still pass. empty_dirs closes that gap.
is_deeply( $result->{empty_dirs}, [], 'cli/, docs/, lib/ and t/ each contributed at least one scanned file' );

my $hollow_root = tempdir( CLEANUP => 1 );
mkdir File::Spec->catdir( $hollow_root, $_ ) for qw(cli docs lib t);
my $hollow = scan_for_non_zero($hollow_root);
is_deeply( [ sort @{ $hollow->{empty_dirs} } ], [qw(cli docs lib t)], 'directories that exist but hold no scannable files are reported as empty' );
is_deeply( $hollow->{missing_dirs}, [], 'existing-but-empty directories are not reported as missing' );

done_testing();
