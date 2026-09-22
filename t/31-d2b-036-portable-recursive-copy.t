use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib 'lib';
use Browser::Runner::NodeRuntime;

# D2B-036: _install_node_runtime's final copy step shelled out to Unix
# 'cp -R', which does not exist on native Windows Perl. A portable,
# Perl-native recursive copy must be used instead so the same code path
# works cross-platform.

my $source_root = tempdir( CLEANUP => 1 );
my $target_root = tempdir( CLEANUP => 1 );

make_path( File::Spec->catdir( $source_root, 'pkg-a' ) );
make_path( File::Spec->catdir( $source_root, 'pkg-b', 'nested' ) );

open my $fh1, '>', File::Spec->catfile( $source_root, 'pkg-a', 'index.js' ) or die $!;
print {$fh1} "module.exports = {};\n";
close $fh1;

open my $fh2, '>', File::Spec->catfile( $source_root, 'pkg-b', 'nested', 'deep.js' ) or die $!;
print {$fh2} "module.exports = 42;\n";
close $fh2;

# node_modules/.bin is exactly this shape: an executable script and a
# symlink pointing at another executable inside the same tree.
my $bin_dir = File::Spec->catdir( $source_root, '.bin' );
make_path($bin_dir);
my $executable = File::Spec->catfile( $source_root, 'pkg-a', 'cli.js' );
open my $fh3, '>', $executable or die $!;
print {$fh3} "#!/usr/bin/env node\n";
close $fh3;
chmod 0755, $executable;

my $symlink = File::Spec->catfile( $bin_dir, 'cli' );
symlink( File::Spec->catfile( '..', 'pkg-a', 'cli.js' ), $symlink )
  or plan skip_all => "symlink() not supported on this filesystem/platform: $!";

make_path( File::Spec->catdir( $source_root, 'pkg-a', 'empty-dir' ) );

Browser::Runner::NodeRuntime::Install::_recursive_copy_dir( $source_root, $target_root );

ok( -f File::Spec->catfile( $target_root, 'pkg-a', 'index.js' ), 'a top-level file is copied into the target' );
ok( -f File::Spec->catfile( $target_root, 'pkg-b', 'nested', 'deep.js' ), 'a nested file in a subdirectory is copied into the target, subdirectory included' );

open my $read_fh, '<', File::Spec->catfile( $target_root, 'pkg-a', 'index.js' ) or die $!;
my $content = do { local $/; <$read_fh> };
close $read_fh;
is( $content, "module.exports = {};\n", 'the copied file content is byte-identical to the source' );

my $copied_executable = File::Spec->catfile( $target_root, 'pkg-a', 'cli.js' );
ok( -x $copied_executable, "a regular file's executable permission bit is preserved on copy, not reset to the process umask" );

my $copied_symlink = File::Spec->catfile( $target_root, '.bin', 'cli' );
ok( -l $copied_symlink, 'a symlink (e.g. node_modules/.bin entries) is recreated as a symlink, not dereferenced into a plain file copy' );
is( readlink($copied_symlink), File::Spec->catfile( '..', 'pkg-a', 'cli.js' ), "the recreated symlink's target is preserved exactly" );

ok( -d File::Spec->catdir( $target_root, 'pkg-a', 'empty-dir' ), 'an empty directory in the source tree is still recreated in the target, matching cp -R' );

done_testing();
