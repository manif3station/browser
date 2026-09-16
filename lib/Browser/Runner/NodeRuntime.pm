package Browser::Runner::NodeRuntime;

use strict;
use warnings;

use Config;
use Cwd qw(getcwd);
use Digest::SHA qw(sha256_hex);
use Fcntl qw(:flock);
use File::Basename qw(dirname);
use File::Path qw(remove_tree);
use File::Spec;
use File::Temp qw(tempdir);
use JSON::PP ();

my %PACKAGE_JSON_CACHE;

sub _ensure_node_runtime {
    my $skill_root = _skill_root();
    my $home_root = $ENV{HOME} || die 'HOME is required for browser skill Node dependencies';
    my $package_json = File::Spec->catfile( $skill_root, 'package.json' );
    die "Missing package.json in $skill_root" if !-f $package_json;

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

    $ENV{NODE_PATH} = join _path_list_separator(), grep { defined && $_ ne q{} } $node_modules, $ENV{NODE_PATH};
    return $node_modules;
}

sub _node_runtime_lock_path {
    my (%args) = @_;
    my $home_root = $args{home_root} || die 'home_root is required';
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
    my $home_root = $args{home_root} || die 'home_root is required';
    my $package_json = $args{package_json} || die 'package_json is required';
    my $fingerprint = $args{fingerprint} || _package_json_fingerprint($package_json);
    my $node_modules = File::Spec->catdir( $home_root, 'node_modules' );

    for my $module ( _required_node_modules() ) {
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
    return qw(express jquery playwright uuid);
}

sub _install_node_runtime {
    my (%args) = @_;
    my $home_root = $args{home_root} || die 'home_root is required';
    my $package_json = $args{package_json} || die 'package_json is required';
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
    _run_quiet_command( 'cp', '-R', "$workspace_modules/.", $target_root );
    return 1;
}

sub _clear_installed_node_modules {
    my (%args) = @_;
    my $home_root = $args{home_root} || die 'home_root is required';
    my $package_json = $args{package_json} || die 'package_json is required';
    my %specs = _package_json_dependency_map($package_json);
    my $target_root = File::Spec->catdir( $home_root, 'node_modules' );

    for my $module ( sort keys %specs ) {
        my $path = File::Spec->catdir( $target_root, $module );
        next if !-e $path;
        remove_tree($path);
    }

    return 1;
}

sub _installed_modules_satisfy_package_json {
    my (%args) = @_;
    my $home_root = $args{home_root} || die 'home_root is required';
    my $package_json = $args{package_json} || die 'package_json is required';
    my %specs = _package_json_dependency_map($package_json);

    for my $module ( sort keys %specs ) {
        my $installed = _installed_node_module_version(
            home_root => $home_root,
            module    => $module,
        );
        return 0 if !defined $installed;
        return 0 if !_version_satisfies_spec( $installed, $specs{$module} );
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
    my $home_root = $args{home_root} || die 'home_root is required';
    my $module = $args{module} || die 'module is required';
    my $package_json = File::Spec->catfile( $home_root, 'node_modules', $module, 'package.json' );
    return if !-f $package_json;
    open my $fh, '<', $package_json or die "Unable to read $package_json: $!";
    local $/;
    my $content = <$fh>;
    close $fh;
    my $decoded = eval { JSON::PP::decode_json($content) };
    die "Unable to parse $package_json: $@" if !$decoded || $@;
    return $decoded->{version};
}

sub _version_satisfies_spec {
    my ( $installed, $spec ) = @_;
    return 0 if !defined $installed || !defined $spec || $installed eq q{} || $spec eq q{};
    return 1 if $spec eq '*' || $spec eq 'latest';
    return $installed eq $spec if $spec !~ /^\^/;

    my $minimum = substr $spec, 1;
    my @installed = _version_parts($installed);
    my @minimum   = _version_parts($minimum);
    return 0 if !@installed || !@minimum;
    return 0 if $installed[0] != $minimum[0];

    if ( $minimum[0] == 0 ) {
        if ( $minimum[1] == 0 ) {
            return $installed[1] == $minimum[1] && $installed[2] == $minimum[2] ? 1 : 0;
        }
        return 0 if $installed[1] != $minimum[1];
    }

    return _compare_version_parts( \@installed, \@minimum ) >= 0 ? 1 : 0;
}

sub _version_parts {
    my ($value) = @_;
    return if !defined $value;
    my ($numeric) = $value =~ /\A([0-9]+(?:\.[0-9]+){0,2})/;
    return if !defined $numeric;
    my @parts = split /\./, $numeric;
    push @parts, 0 while @parts < 3;
    return @parts[ 0 .. 2 ];
}

sub _compare_version_parts {
    my ( $left, $right ) = @_;
    for my $idx ( 0 .. 2 ) {
        my $cmp = ( $left->[$idx] || 0 ) <=> ( $right->[$idx] || 0 );
        return $cmp if $cmp != 0;
    }
    return 0;
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
    my $home_root = $args{home_root} || die 'home_root is required';
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

sub _skill_root {
    return $ENV{DEVELOPER_DASHBOARD_SKILL_ROOT} if $ENV{DEVELOPER_DASHBOARD_SKILL_ROOT};
    return getcwd() if -d File::Spec->catdir( getcwd(), 'cli' ) && -d File::Spec->catdir( getcwd(), 'lib' );
    return File::Spec->catdir( dirname( dirname( dirname( dirname(__FILE__) ) ) ) );
}

sub _run_quiet_command {
    my (@command) = @_;
    open my $stdout_save, '>&', \*STDOUT or die "Unable to save STDOUT: $!";
    open my $stderr_save, '>&', \*STDERR or die "Unable to save STDERR: $!";
    open my $null_fh, '>', File::Spec->devnull() or die "Unable to open devnull: $!";

    open STDOUT, '>&', $null_fh or die "Unable to redirect STDOUT: $!";
    open STDERR, '>&', $null_fh or die "Unable to redirect STDERR: $!";

    my $ok = system(@command) == 0;
    my $exit = $? >> 8;

    open STDOUT, '>&', $stdout_save or die "Unable to restore STDOUT: $!";
    open STDERR, '>&', $stderr_save or die "Unable to restore STDERR: $!";

    die "Command failed: @command" if !$ok;
    return $exit;
}

1;
