use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib 'lib';
use Browser::Runner;

# D2B-006: _find_in_path must split PATH using the platform separator
# (reusing D2B-005's _path_list_separator seam) and, on Windows, also try
# a .exe suffix when the bare command name isn't found.

{
    my $temp_root = tempdir( CLEANUP => 1 );
    my $bin_dir = File::Spec->catdir( $temp_root, 'bin' );
    make_path($bin_dir);
    my $exe_path = File::Spec->catfile( $bin_dir, 'chrome.exe' );
    open my $fh, '>', $exe_path or die "Unable to write fake chrome.exe: $!";
    print {$fh} "#!/bin/sh\nexit 0\n";
    close $fh;
    chmod 0755, $exe_path or die "Unable to chmod fake chrome.exe: $!";

    no warnings 'redefine';
    local *Browser::Runner::NodeRuntime::_path_list_separator = sub { return ';' };
    local *Browser::Runner::BrowserPath::_platform_is_windows = sub { return 1 };
    local $ENV{PATH} = $bin_dir;

    is(
        Browser::Runner::BrowserPath::_find_in_path('chrome'), $exe_path,
        '_find_in_path finds chrome.exe on a Windows-style PATH when the bare name is not present'
    );
}

{
    my $temp_root = tempdir( CLEANUP => 1 );
    my $dir1 = File::Spec->catdir( $temp_root, 'first' );
    my $dir2 = File::Spec->catdir( $temp_root, 'second' );
    make_path($dir1);
    make_path($dir2);
    my $target = File::Spec->catfile( $dir2, 'chromium' );
    open my $fh, '>', $target or die "Unable to write fake chromium: $!";
    print {$fh} "#!/bin/sh\nexit 0\n";
    close $fh;
    chmod 0755, $target or die "Unable to chmod fake chromium: $!";

    no warnings 'redefine';
    local *Browser::Runner::NodeRuntime::_path_list_separator = sub { return ';' };
    local $ENV{PATH} = "$dir1;$dir2";

    is(
        Browser::Runner::BrowserPath::_find_in_path('chromium'), $target,
        '_find_in_path splits PATH using the platform separator (";" here), not a hardcoded ":"'
    );
}

is_deeply(
    [ Browser::Runner::BrowserPath::_command_lookup_names('chrome') ],
    ['chrome'],
    '_command_lookup_names returns just the bare name on non-Windows platforms'
) if !Browser::Runner::BrowserPath::_platform_is_windows();

done_testing();
