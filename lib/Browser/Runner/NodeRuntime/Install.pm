package Browser::Runner::NodeRuntime::Install;

use strict;
use warnings;

use Cwd qw(getcwd);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Find ();
use File::Path qw(remove_tree);
use File::Spec;
use File::Temp qw(tempdir);

# D2B-198: extracted from Browser::Runner::NodeRuntime (which was
# approaching this workspace's 500-line guideline after D2B-199's
# Windows fix) - the same extraction pattern as VersionCompare.pm
# (D2B-155) and Browser::Runner::Capture.pm (D2B-196).
# _required_arg/_make_path_if_missing/_run_quiet_command/
# _package_json_dependency_specs/_package_json_dependency_map remain
# private to NodeRuntime.pm and are called back into fully-qualified,
# the same cross-module private-call pattern this codebase already
# relies on throughout.

sub install_node_runtime {
    my (%args) = @_;
    my $home_root = Browser::Runner::NodeRuntime::_required_arg( \%args, 'home_root' );
    my $package_json = Browser::Runner::NodeRuntime::_required_arg( \%args, 'package_json' );
    my @specs = Browser::Runner::NodeRuntime::_package_json_dependency_specs($package_json);
    return 1 if !@specs;

    my $workspace_parent = File::Spec->catdir( $home_root, '.developer-dashboard', 'cache', 'node-package-installs' );
    my $target_root      = File::Spec->catdir( $home_root, 'node_modules' );
    Browser::Runner::NodeRuntime::_make_path_if_missing($workspace_parent);
    Browser::Runner::NodeRuntime::_make_path_if_missing($target_root);
    my $workspace = tempdir( 'npm-install-XXXXXX', DIR => $workspace_parent, CLEANUP => 1 );
    my $workspace_package_json = File::Spec->catfile( $workspace, 'package.json' );
    open my $workspace_fh, '>', $workspace_package_json or die "Unable to write $workspace_package_json: $!";
    print {$workspace_fh} qq|{"name":"browser-skill-runtime","version":"1.0.0","private":true}\n|;
    close $workspace_fh;

    # D2B-187: no longer skips Playwright's own postinstall browser
    # download - this was the only install path, so skipping it left
    # firefox/webkit and the CHROMIUM_BIN fallback unable to launch.
    my $cwd = getcwd();
    eval {
        chdir $workspace or die "Unable to chdir to $workspace for browser skill package.json dependency install: $!";
        Browser::Runner::NodeRuntime::_run_quiet_command( 'npx', '--yes', 'npm', 'install', @specs );
        chdir $cwd or die "Unable to chdir back to $cwd after browser skill package.json dependency install: $!";
        1;
    } or do {
        my $error = $@;
        chdir $cwd if getcwd() ne $cwd;
        die $error;
    };

    my $workspace_modules = File::Spec->catdir( $workspace, 'node_modules' );
    return 1 if !-d $workspace_modules;
    _clear_installed_node_modules(
        home_root    => $home_root,
        package_json => $package_json,
    );
    _recursive_copy_dir( $workspace_modules, $target_root );
    return 1;
}

sub _clear_installed_node_modules {
    my (%args) = @_;
    my $home_root = Browser::Runner::NodeRuntime::_required_arg( \%args, 'home_root' );
    my $package_json = Browser::Runner::NodeRuntime::_required_arg( \%args, 'package_json' );
    my %specs = Browser::Runner::NodeRuntime::_package_json_dependency_map($package_json);
    my $target_root = File::Spec->catdir( $home_root, 'node_modules' );

    # D2B-128 (investigated, not fixed as originally proposed): a
    # module directory from a dependency later removed from
    # package.json is never cleared by this loop and would survive
    # indefinitely - currently latent, since this skill's own
    # dependency set has never shrunk. A first attempt fixed this by
    # clearing every entry actually present under $target_root instead
    # of only the ones still in %specs, but $home_root is literally
    # $ENV{HOME} (see _ensure_node_runtime) - a real user's actual home
    # directory, not a directory this skill exclusively owns - so that
    # "clear everything" approach could destroy an unrelated
    # node_modules tree a user happens to keep directly under their own
    # $HOME for something else entirely. A genuinely safe fix needs a
    # persisted manifest of every module name this skill has ever
    # installed (not just the current spec) to know what is safe to
    # remove without guessing - out of scope for this ticket. Left as
    # a known, accepted limitation rather than shipping a fix whose
    # risk (arbitrary user data loss) is worse than the bug it solves
    # (a few stale MB under node_modules).
    for my $module ( sort keys %specs ) {
        my $path = File::Spec->catdir( $target_root, $module );
        next if !-e $path;
        remove_tree($path);
    }

    return 1;
}

# Portable replacement for shelling out to Unix 'cp -R', which does not
# exist on native Windows Perl. Recreates $source's directory structure
# (including empty directories) under $target, recreates symlinks as
# symlinks rather than dereferencing them (node_modules/.bin is exactly
# this - executable symlinks a broken copy would silently replace with a
# dereferenced regular file), and preserves each regular file's
# permission bits (including the executable bit npm-installed binaries
# rely on), which File::Copy::copy alone does not.
sub _recursive_copy_dir {
    my ( $source, $target ) = @_;
    File::Find::find(
        {
            no_chdir => 1,
            wanted   => sub {
                return if $_ eq $source;
                my $relative = File::Spec->abs2rel( $_, $source );
                my $destination = File::Spec->catfile( $target, $relative );

                if ( -l $_ ) {
                    Browser::Runner::NodeRuntime::_make_path_if_missing( dirname($destination) );
                    unlink $destination if -e $destination || -l $destination;
                    my $link_target = readlink($_);
                    symlink( $link_target, $destination )
                      or die "Unable to symlink $destination -> $link_target: $!";
                    return;
                }

                if ( -d $_ ) {
                    Browser::Runner::NodeRuntime::_make_path_if_missing($destination);
                    return;
                }

                Browser::Runner::NodeRuntime::_make_path_if_missing( dirname($destination) );
                copy( $_, $destination ) or die "Unable to copy $_ to $destination: $!";
                my $mode = ( stat $_ )[2];
                chmod( $mode & 07777, $destination ) if defined $mode;
            },
        },
        $source,
    );
    return 1;
}

1;
