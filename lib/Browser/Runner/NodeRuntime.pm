package Browser::Runner::NodeRuntime;

use strict;
use warnings;

use Config;
use Cwd qw(getcwd);
use Digest::SHA qw(sha256_hex);
use Fcntl qw(:flock);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Find ();
use File::Path qw(remove_tree);
use File::Spec;
use File::Temp qw(tempdir tempfile);
use JSON::PP ();

use Browser::Runner::VersionCompare ();

my %PACKAGE_JSON_CACHE;

sub _ensure_node_runtime {
    my $skill_root = skill_root();
    my $home_root = $ENV{HOME} || die 'HOME is required for browser skill Node dependencies';
    my $package_json = File::Spec->catfile( $skill_root, 'package.json' );
    die "Missing package.json in $skill_root" if !-f $package_json;

    _check_node_version();

    my $node_modules = File::Spec->catdir( $home_root, 'node_modules' );

    # Cleared at the start of every call: the package.json read-cache is
    # never carried over from a previous _ensure_node_runtime pass, since
    # a long-lived process (a persistent dashboard, not this skill's own
    # one-shot CLI) could otherwise be served a stale decoded snapshot if
    # the file changed between two calls without its mtime changing too.
    %PACKAGE_JSON_CACHE = ();

    _with_node_runtime_lock(
        $home_root,
        sub {
            my $fingerprint = _package_json_fingerprint($package_json);

            if ( !_node_runtime_is_current( home_root => $home_root, package_json => $package_json, fingerprint => $fingerprint ) ) {
                _install_node_runtime(
                    home_root    => $home_root,
                    package_json => $package_json,
                );
                _write_node_runtime_stamp(
                    home_root    => $home_root,
                    fingerprint  => $fingerprint,
                );
            }
        }
    );

    my $sep = _path_list_separator();
    my @existing = defined $ENV{NODE_PATH} && $ENV{NODE_PATH} ne q{} ? split /\Q$sep\E/, $ENV{NODE_PATH}, -1 : ();
    $ENV{NODE_PATH} = join $sep, $node_modules, grep { $_ ne $node_modules } @existing;
    return $node_modules;
}

# D2B-179: this file repeated $args{X} || die "X is required" 12
# times across 3 distinct argument names (home_root x7, package_json
# x4, module x1) - this shared helper centralizes that guard, so
# every call site now shares one place to change the message format.
sub _required_arg {
    my ( $args, $name ) = @_;
    return $args->{$name} || die "$name is required";
}

sub _node_runtime_lock_path {
    my (%args) = @_;
    my $home_root = _required_arg( \%args, 'home_root' );
    return File::Spec->catfile( $home_root, '.developer-dashboard', 'cache', 'browser-skill-node-runtime.lock' );
}

sub _with_node_runtime_lock {
    my ( $home_root, $code ) = @_;
    my $lock_path = _node_runtime_lock_path( home_root => $home_root );
    _make_path_if_missing( dirname($lock_path) );

    open my $lock_fh, '>>', $lock_path or die "Unable to open lock file $lock_path: $!";
    flock( $lock_fh, LOCK_EX ) or die "Unable to lock $lock_path: $!";

    my $result = eval { $code->(); 1 };
    my $error = $@;

    flock( $lock_fh, LOCK_UN );
    close $lock_fh;

    die $error if !$result;
    return 1;
}

sub _path_list_separator {
    return $Config{path_sep};
}

# Exposed purely for tests to verify the cache is actually preventing
# repeat disk reads (D2B-024) - incremented only on a genuine cache miss.
our $PACKAGE_JSON_READ_COUNT = 0;

# Shared decode-once reader for the skill's own package.json: fingerprint,
# dependency-specs, and dependency-map all need the same file's content,
# so this is the one place that actually opens and JSON-decodes it. Keyed
# by path+mtime rather than just path, so a package.json that changes on
# disk between calls (a skill upgrade) is never served stale cached data.
sub _read_package_json {
    my ($package_json) = @_;
    my $mtime = ( stat $package_json )[9];
    my $cache_key = "$package_json:" . ( defined $mtime ? $mtime : 0 );
    return $PACKAGE_JSON_CACHE{$cache_key} if $PACKAGE_JSON_CACHE{$cache_key};

    $PACKAGE_JSON_READ_COUNT++;
    open my $fh, '<', $package_json or die "Unable to read $package_json: $!";
    local $/;
    my $content = <$fh>;
    close $fh;

    my $decoded = eval { JSON::PP::decode_json($content) };
    die "Unable to parse $package_json: $@" if !$decoded || $@;

    return $PACKAGE_JSON_CACHE{$cache_key} = { content => $content, decoded => $decoded };
}

sub _package_json_dependency_specs {
    my ($package_json) = @_;
    my $decoded = _read_package_json($package_json)->{decoded};

    my @specs;
    for my $section ( qw(dependencies devDependencies optionalDependencies peerDependencies) ) {
        my $entries = $decoded->{$section};
        next if ref($entries) ne 'HASH';
        for my $name ( sort keys %{$entries} ) {
            my $version = $entries->{$name};
            push @specs, defined $version && $version ne q{} ? "$name\@$version" : $name;
        }
    }

    return @specs;
}

sub _package_json_fingerprint {
    my ($package_json) = @_;
    return sha256_hex( _read_package_json($package_json)->{content} );
}

sub _node_runtime_is_current {
    my (%args) = @_;
    my $home_root = _required_arg( \%args, 'home_root' );
    my $package_json = _required_arg( \%args, 'package_json' );
    my $fingerprint = $args{fingerprint} || _package_json_fingerprint($package_json);
    my $node_modules = File::Spec->catdir( $home_root, 'node_modules' );

    for my $module ( _required_node_modules($package_json) ) {
        return 0 if !-d File::Spec->catdir( $node_modules, $module );
    }

    my $stamp = _read_node_runtime_stamp( home_root => $home_root );
    return 1 if defined $stamp && $stamp eq $fingerprint;

    return _installed_modules_satisfy_package_json(
        home_root    => $home_root,
        package_json => $package_json,
    );
}

sub _required_node_modules {
    my ($package_json) = @_;
    my %specs = _package_json_dependency_map($package_json);
    return sort keys %specs;
}

sub _install_node_runtime {
    my (%args) = @_;
    my $home_root = _required_arg( \%args, 'home_root' );
    my $package_json = _required_arg( \%args, 'package_json' );
    my @specs = _package_json_dependency_specs($package_json);
    return 1 if !@specs;

    my $workspace_parent = File::Spec->catdir( $home_root, '.developer-dashboard', 'cache', 'node-package-installs' );
    my $target_root      = File::Spec->catdir( $home_root, 'node_modules' );
    _make_path_if_missing($workspace_parent);
    _make_path_if_missing($target_root);
    my $workspace = tempdir( 'npm-install-XXXXXX', DIR => $workspace_parent, CLEANUP => 1 );
    my $workspace_package_json = File::Spec->catfile( $workspace, 'package.json' );
    open my $workspace_fh, '>', $workspace_package_json or die "Unable to write $workspace_package_json: $!";
    print {$workspace_fh} qq|{"name":"browser-skill-runtime","version":"1.0.0","private":true}\n|;
    close $workspace_fh;

    my $cwd = getcwd();
    local $ENV{PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD} = 1;
    eval {
        chdir $workspace or die "Unable to chdir to $workspace for browser skill package.json dependency install: $!";
        _run_quiet_command( 'npx', '--yes', 'npm', 'install', @specs );
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
    my $home_root = _required_arg( \%args, 'home_root' );
    my $package_json = _required_arg( \%args, 'package_json' );
    my %specs = _package_json_dependency_map($package_json);
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

sub _installed_modules_satisfy_package_json {
    my (%args) = @_;
    my $home_root = _required_arg( \%args, 'home_root' );
    my $package_json = _required_arg( \%args, 'package_json' );
    my %specs = _package_json_dependency_map($package_json);

    for my $module ( sort keys %specs ) {
        my $installed = _installed_node_module_version(
            home_root => $home_root,
            module    => $module,
        );
        return 0 if !defined $installed;
        return 0 if !Browser::Runner::VersionCompare::version_satisfies_spec( $installed, $specs{$module} );
    }

    return 1;
}

sub _package_json_dependency_map {
    my ($package_json) = @_;
    my $decoded = _read_package_json($package_json)->{decoded};

    my %specs;
    for my $section ( qw(dependencies devDependencies optionalDependencies peerDependencies) ) {
        my $entries = $decoded->{$section};
        next if ref($entries) ne 'HASH';
        @specs{ keys %{$entries} } = values %{$entries};
    }

    return %specs;
}

sub _installed_node_module_version {
    my (%args) = @_;
    my $home_root = _required_arg( \%args, 'home_root' );
    my $module = _required_arg( \%args, 'module' );
    my $package_json = File::Spec->catfile( $home_root, 'node_modules', $module, 'package.json' );
    return if !-f $package_json;
    return _read_package_json($package_json)->{decoded}{version};
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
                    _make_path_if_missing( dirname($destination) );
                    unlink $destination if -e $destination || -l $destination;
                    my $link_target = readlink($_);
                    symlink( $link_target, $destination )
                      or die "Unable to symlink $destination -> $link_target: $!";
                    return;
                }

                if ( -d $_ ) {
                    _make_path_if_missing($destination);
                    return;
                }

                _make_path_if_missing( dirname($destination) );
                copy( $_, $destination ) or die "Unable to copy $_ to $destination: $!";
                my $mode = ( stat $_ )[2];
                chmod( $mode & 07777, $destination ) if defined $mode;
            },
        },
        $source,
    );
    return 1;
}

sub _make_path_if_missing {
    my ($path) = @_;
    return 1 if -d $path;
    require File::Path;
    File::Path::make_path($path);
    return 1;
}

sub _node_runtime_stamp_path {
    my (%args) = @_;
    my $home_root = _required_arg( \%args, 'home_root' );
    return File::Spec->catfile( $home_root, '.developer-dashboard', 'cache', 'browser-skill-node-runtime.sha256' );
}

sub _read_node_runtime_stamp {
    my (%args) = @_;
    my $path = _node_runtime_stamp_path(%args);
    return if !-f $path;
    open my $fh, '<', $path or die "Unable to read $path: $!";
    my $value = <$fh>;
    close $fh;
    chomp $value if defined $value;
    return $value;
}

sub _write_node_runtime_stamp {
    my (%args) = @_;
    my $path = _node_runtime_stamp_path(%args);
    my $dir = dirname($path);
    _make_path_if_missing($dir);
    open my $fh, '>', $path or die "Unable to write $path: $!";
    print {$fh} $args{fingerprint}, "\n";
    close $fh;
    return 1;
}

# D2B-154: public (not underscore-prefixed) since Browser::CLI, a
# standalone module outside this module's own dependency-install flow,
# reuses it to resolve .env's path for --version.
sub skill_root {
    return $ENV{DEVELOPER_DASHBOARD_SKILL_ROOT} if $ENV{DEVELOPER_DASHBOARD_SKILL_ROOT};
    return getcwd()
      if -d File::Spec->catdir( getcwd(), 'cli' )
      && -d File::Spec->catdir( getcwd(), 'lib' )
      && -f File::Spec->catfile( getcwd(), 'lib', 'Browser', 'CLI.pm' );
    return File::Spec->catdir( dirname( dirname( dirname( dirname(__FILE__) ) ) ) );
}

# D2B-095: package.json's playwright ^1.55.1 dependency itself declares
# "engines": { "node": ">=20" } (verified in the installed package's own
# package.json). Nothing here checked the system's actual node binary
# version before this - an outdated Node would only surface as whatever
# cryptic native error Playwright/require produced deep in its own
# module-loading chain, with no indication that upgrading Node is the
# real fix.
sub _minimum_node_major_version { return 20 }

sub _node_major_version {
    my $version_output = qx{node --version 2>&1};
    $version_output = defined $version_output ? $version_output : q{};
    my ($major) = $version_output =~ /^v(\d+)/;
    return $major;
}

sub _check_node_version {
    my $major = _node_major_version();
    my $minimum = _minimum_node_major_version();
    die "Node.js v$minimum+ is required (Playwright's own declared minimum) - found "
      . ( defined $major ? "v$major" : "an unrecognized 'node --version' output" )
      . ". Please upgrade Node.js.\n"
      if !defined $major || $major < $minimum;
    return 1;
}

sub _restore_std_handle {
    my ( $glob_ref, $saved_fh, $label ) = @_;
    open $glob_ref, '>&', $saved_fh or die "Unable to restore $label: $!";
    return 1;
}

sub _run_quiet_command {
    my (@command) = @_;
    open my $stdout_save, '>&', \*STDOUT or die "Unable to save STDOUT: $!";
    open my $stderr_save, '>&', \*STDERR or die "Unable to save STDERR: $!";

    my ( $stdout_fh, $stdout_path ) = tempfile( UNLINK => 1 );
    my ( $stderr_fh, $stderr_path ) = tempfile( UNLINK => 1 );

    # D2B-129: redirect-and-run runs inside eval so a mid-sequence failure
    # still reaches the restore below instead of stranding real STDOUT/STDERR.
    my ( $ok, $exit );
    my $run_ok = eval {
        open STDOUT, '>&', $stdout_fh or die "Unable to redirect STDOUT: $!";
        open STDERR, '>&', $stderr_fh or die "Unable to redirect STDERR: $!";

        $ok   = system(@command) == 0;
        $exit = $? >> 8;
        1;
    };
    my $redirect_error = $@;

    # Restores run independently, so a STDOUT restore failure doesn't skip
    # the STDERR restore attempt.
    my @restore_errors;
    for my $pair ( [ \*STDOUT, $stdout_save, 'STDOUT' ], [ \*STDERR, $stderr_save, 'STDERR' ] ) {
        eval { _restore_std_handle( @{$pair} ); 1 } or push @restore_errors, $@;
    }

    if ( !$run_ok ) { unlink $stdout_path, $stderr_path; die $redirect_error; }
    if (@restore_errors) { unlink $stdout_path, $stderr_path; die join( q{}, @restore_errors ); }

    if ( !$ok ) {
        my $captured_stdout = _slurp_captured_output($stdout_path);
        my $captured_stderr = _slurp_captured_output($stderr_path);
        unlink $stdout_path, $stderr_path;
        die "Command failed: @command (exit code $exit)\n"
          . "captured stdout:\n$captured_stdout\n"
          . "captured stderr:\n$captured_stderr\n";
    }
    unlink $stdout_path, $stderr_path;
    return $exit;
}

sub _slurp_captured_output {
    my ($path) = @_;
    open my $fh, '<', $path or return q{};
    local $/;
    my $content = <$fh>;
    close $fh;
    return defined $content ? $content : q{};
}

1;
