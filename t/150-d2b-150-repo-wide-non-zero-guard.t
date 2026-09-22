use strict;
use warnings;

use Test::More;
use Cwd qw(abs_path);
use File::Find qw(find);
use File::Spec;
use File::Basename qw(dirname basename);

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

my @unreadable_files;

my $repo_root = abs_path( File::Spec->catdir( dirname(__FILE__), '..' ) );

# Changes is a historical changelog - each dated entry is a record of
# what was true (and how it was worded) at that release, not something
# to retroactively edit. t/148/149's own doc-consistency tests
# legitimately contain the literal phrase "non-zero" as the pattern they
# check for ABSENCE of - scanning them for it would be circular. This
# file excludes itself via __FILE__ rather than hardcoding its own name.
my %excluded_files = map { $_ => 1 } (
    File::Spec->catfile( $repo_root, 'Changes' ),
    File::Spec->catfile( $repo_root, 't', '148-d2b-148-exit-status-pod-names-code.t' ),
    File::Spec->catfile( $repo_root, 't', '149-d2b-149-non-zero-wording-fixed.t' ),
    abs_path(__FILE__),
);

my @offending_files;
for my $dir (qw(cli docs lib t)) {
    my $full_dir = File::Spec->catdir( $repo_root, $dir );
    next if !-d $full_dir;
    find(
        {
            no_chdir => 1,
            wanted   => sub {
                return unless -f $_;
                return if $excluded_files{$_};
                my $path = $_;
                open my $fh, '<', $path or do { push @unreadable_files, "$path: $!"; return; };
                my $text = do { local $/; <$fh> };
                close $fh;
                push @offending_files, $path if $text =~ /non-zero/i;
            },
        },
        $full_dir
    );
}
for my $top_level_file (qw(README.md SKILLS.md)) {
    my $path = File::Spec->catfile( $repo_root, $top_level_file );
    next if $excluded_files{$path};
    open my $fh, '<', $path or do { push @unreadable_files, "$path: $!"; next; };
    my $text = do { local $/; <$fh> };
    close $fh;
    push @offending_files, $path if $text =~ /non-zero/i;
}

is( scalar @unreadable_files, 0, 'every file scanned could actually be opened for reading' )
  or diag( 'Unreadable files: ' . join( ', ', @unreadable_files ) );

is_deeply( \@offending_files, [], 'no file under cli/, docs/, lib/, t/, README.md, or SKILLS.md still says the vague "non-zero" (Changes and the doc-consistency test files themselves are the only allowed exceptions)' )
  or diag( "Files still containing 'non-zero': " . join( ', ', map { basename($_) } @offending_files ) );

done_testing();
