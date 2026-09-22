use strict;
use warnings;

use Test::More;
use File::Temp qw(tempdir);
use File::Spec;
use File::Copy;
use File::Basename qw(dirname);
use File::Find qw(find);
use File::Path qw(make_path);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

sub copy_tree {
    my ( $from, $to ) = @_;
    find(
        {
            no_chdir => 1,
            wanted   => sub {
                return unless -f $_;
                ( my $dest = $_ ) =~ s/\A\Q$from\E/$to/;
                make_path( dirname($dest) );
                copy( $_, $dest ) or die "Unable to copy $_ to $dest: $!";
            },
        },
        $from
    );
    return 1;
}

# D2B-147: cli/skills (unlike cli/get/post/png/search, which all delegate
# to Browser::CLI::main's shared sanitize_error()/exit-2 convention) died
# on open/close failure with a raw, uncaught Perl death - its exit code
# was whatever errno happened to produce (2 for ENOENT, 21 for EISDIR),
# not the fixed exit 2 every other command guarantees. Run as a real
# subprocess since cli/skills is a standalone script, not a lib/ module.

my $repo_root = File::Spec->catdir( dirname(__FILE__), '..' );

sub run_cli_skills_in {
    my ($scratch_dir) = @_;

    # Codex review round: the earlier version relied on the real
    # checkout's lib/ being reachable via an ambient PERL5LIB rather
    # than copying it into the scratch tree - copy the real lib/ so the
    # scratch script's `use lib "$Bin/../lib"` resolves independently
    # of the test's own invocation environment.
    my $scratch_cli = File::Spec->catdir( $scratch_dir, 'cli' );
    mkdir $scratch_cli or die "Unable to create $scratch_cli: $!";
    copy( File::Spec->catfile( $repo_root, 'cli', 'skills' ), File::Spec->catfile( $scratch_cli, 'skills' ) )
      or die "Unable to copy cli/skills: $!";
    chmod 0755, File::Spec->catfile( $scratch_cli, 'skills' );
    copy_tree( File::Spec->catdir( $repo_root, 'lib' ), File::Spec->catdir( $scratch_dir, 'lib' ) );

    # Codex review round: the earlier version captured stderr through a
    # predictable /tmp/...$$ file via shell redirection in backticks -
    # replaced with IPC::Open3, which runs the interpreter directly (no
    # shell) and captures both streams without any on-disk temp file.
    my ( $stdin, $stdout, $stderr ) = ( gensym(), gensym(), gensym() );
    my $pid = open3( $stdin, $stdout, $stderr, $^X, File::Spec->catfile( $scratch_cli, 'skills' ) );
    close $stdin;
    my $out = do { local $/; <$stdout> };
    my $err = do { local $/; <$stderr> };
    close $stdout;
    close $stderr;
    waitpid $pid, 0;
    my $exit_code = $? >> 8;

    return ( $exit_code, $out, $err );
}

{
    my $scratch_dir = tempdir( CLEANUP => 1 );
    # SKILLS.md missing entirely (ENOENT).
    my ( $exit_code, $stdout, $stderr ) = run_cli_skills_in($scratch_dir);
    is( $exit_code, 2, 'D2B-147: cli/skills exits 2 when SKILLS.md is missing (ENOENT), not an errno-derived code' );
    is( $stdout, q{}, 'D2B-147: no partial output printed on this failure' );
    ok( length $stderr, 'D2B-147: a sanitized error message is printed to stderr' );
}

{
    my $scratch_dir = tempdir( CLEANUP => 1 );
    mkdir File::Spec->catdir( $scratch_dir, 'SKILLS.md' ) or die $!;    # SKILLS.md replaced by a directory (EISDIR).
    my ( $exit_code, $stdout, $stderr ) = run_cli_skills_in($scratch_dir);
    is( $exit_code, 2, 'D2B-147: cli/skills exits 2 when SKILLS.md is a directory (EISDIR) - the SAME exit code as the missing-file case' );
    is( $stdout, q{}, 'D2B-147: no partial output printed on this failure' );
    ok( length $stderr, 'D2B-147: a sanitized error message is printed to stderr' );
}

# Regression guard: the success path is completely unaffected.
{
    my $scratch_dir = tempdir( CLEANUP => 1 );
    open my $fh, '>', File::Spec->catfile( $scratch_dir, 'SKILLS.md' ) or die $!;
    print {$fh} "test manual content\n";
    close $fh;
    my ( $exit_code, $stdout, $stderr ) = run_cli_skills_in($scratch_dir);
    is( $exit_code, 0, 'D2B-147 regression guard: cli/skills still exits 0 on success' );
    is( $stdout, "test manual content\n", 'D2B-147 regression guard: cli/skills still prints the manual content verbatim on success' );
    is( $stderr, q{}, 'D2B-147 regression guard: no stderr output on success' );
}

done_testing();
