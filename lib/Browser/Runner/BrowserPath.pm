package Browser::Runner::BrowserPath;

use strict;
use warnings;

use File::Spec;

use Browser::Runner::NodeRuntime ();

my @SUPPORTED_BROWSER_TYPES = qw(chrome chromium firefox webkit);

sub _launch_options {
    my (%args) = @_;
    my $requested = defined $args{browser} ? $args{browser} : 'chrome';
    die "Unsupported browser type: $requested (expected one of: @SUPPORTED_BROWSER_TYPES)"
      if !grep { $_ eq $requested } @SUPPORTED_BROWSER_TYPES;
    my $type = $requested eq 'chromium' ? 'chrome' : $requested;
    my %launch = (
        headless => $args{headless} ? 1 : 0,
        type     => $type,
    );
    if ( $type eq 'chrome' ) {
        if ( my $path = _validated_browser_path() ) {
            $launch{executablePath} = $path;
        }
    }
    return %launch;
}

sub _validated_browser_path {
    my $configured = $ENV{CHROMIUM_BIN};
    if ( defined $configured && $configured ne q{} ) {
        return $configured if _browser_path_is_usable($configured);
        warn "CHROMIUM_BIN=$configured is not a usable browser executable - falling back to Playwright's own bundled browser\n";
        return;
    }

    return _default_chromium_bin();
}

sub _default_chromium_bin {
    for my $path ( _browser_candidates() ) {
        next if !_browser_path_is_usable($path);
        return $path;
    }
    return;
}

sub _browser_candidates {
    my @candidates;

    # D2B-162: %seen's dedup-skip branch (below, and at the two other
    # "next if $seen{$path}++" sites in this function) is deliberately
    # kept even though forcing it to fire in a test would need a real
    # filesystem where two different command names resolve to the
    # identical absolute path - impractical to mock reliably, the same
    # class of hard-to-force defensive branch as NodeRuntime.pm's
    # filesystem-open-failure paths. t/162-...t proves the function
    # never returns a duplicate in practice instead.
    my %seen;

    for my $command (qw(chromium chromium-browser google-chrome google-chrome-stable chrome)) {
        my $path = _find_in_path($command);
        next if !defined $path || $path eq q{};
        next if $seen{$path}++;
        push @candidates, $path;
    }

    if ( !_platform_is_windows() ) {
        my @paths = (
            '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
            '/Applications/Chromium.app/Contents/MacOS/Chromium',
        );
        if ( defined $ENV{HOME} && $ENV{HOME} ne q{} ) {
            push @paths,
              File::Spec->catfile( $ENV{HOME}, 'Applications', 'Google Chrome.app', 'Contents', 'MacOS', 'Google Chrome' ),
              File::Spec->catfile( $ENV{HOME}, 'Applications', 'Chromium.app', 'Contents', 'MacOS', 'Chromium' );
        }
        for my $path (@paths) {
            next if $seen{$path}++;
            push @candidates, $path;
        }
    }

    # D2B-126: Chrome/Chromium's Windows installers typically do not add
    # themselves to PATH, so - mirroring the macOS fallback above -
    # Windows gets the same absolute-path safety net appended after PATH
    # lookup, instead of falling straight through to Playwright's own
    # bundled browser with no fallback at all when PATH lookup finds
    # nothing usable. PATH candidates are still tried first (see order
    # above), so these only end up mattering when PATH lookup fails.
    if ( _platform_is_windows() ) {
        for my $root ( $ENV{PROGRAMFILES}, $ENV{'PROGRAMFILES(X86)'}, $ENV{LOCALAPPDATA} ) {
            next if !defined $root || $root eq q{};
            for my $browser_dir ( File::Spec->catdir( 'Google', 'Chrome' ), 'Chromium' ) {
                my $path = File::Spec->catfile( $root, $browser_dir, 'Application', 'chrome.exe' );
                next if $seen{$path}++;
                push @candidates, $path;
            }
        }
    }

    return @candidates;
}

sub _browser_path_is_usable {
    my ($path) = @_;
    return 0 if !defined $path || $path eq q{};
    return 0 if !File::Spec->file_name_is_absolute($path);
    return 0 if !-x $path || -d $path;

    # _run_quiet_command dies on any nonzero exit and only ever returns
    # on success, so it only ever returns 0 here - checking $@ alone
    # already covers every failure case.
    eval { Browser::Runner::NodeRuntime::_run_quiet_command( $path, '--version' ) };
    return 0 if $@;
    return 1;
}

sub _find_in_path {
    my ($command) = @_;
    return if !defined $command || $command eq q{};
    my $sep = quotemeta Browser::Runner::NodeRuntime::_path_list_separator();
    for my $dir ( split /$sep/, ( $ENV{PATH} || q{} ) ) {
        next if !defined $dir || $dir eq q{};
        for my $name ( _command_lookup_names($command) ) {
            my $path = File::Spec->catfile( $dir, $name );
            next if !File::Spec->file_name_is_absolute($path);
            return $path if -x $path && !-d $path;
        }
    }
    return;
}

sub _platform_is_windows {
    return $^O eq 'MSWin32' ? 1 : 0;
}

sub _command_lookup_names {
    my ($command) = @_;
    return ($command) if !_platform_is_windows();
    return ($command) if $command =~ /\.[^.\/\\]+\z/;
    return ( $command, "$command.exe" );
}

1;
