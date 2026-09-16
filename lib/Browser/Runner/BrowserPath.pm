package Browser::Runner::BrowserPath;

use strict;
use warnings;

use File::Spec;

use Browser::Runner::NodeRuntime ();

sub _launch_options {
    my (%args) = @_;
    my $type = ( $args{browser} || 'chrome' ) eq 'chromium' ? 'chrome' : ( $args{browser} || 'chrome' );
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
    my %seen;

    for my $command (qw(chromium chromium-browser google-chrome google-chrome-stable chrome)) {
        my $path = _find_in_path($command);
        next if !defined $path || $path eq q{};
        next if $seen{$path}++;
        push @candidates, $path;
    }

    for my $path (
        '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
        File::Spec->catfile( $ENV{HOME} || q{}, 'Applications', 'Google Chrome.app', 'Contents', 'MacOS', 'Google Chrome' ),
        '/Applications/Chromium.app/Contents/MacOS/Chromium',
        File::Spec->catfile( $ENV{HOME} || q{}, 'Applications', 'Chromium.app', 'Contents', 'MacOS', 'Chromium' ),
      )
    {
        next if !defined $path || $path eq q{};
        next if $seen{$path}++;
        push @candidates, $path;
    }

    return @candidates;
}

sub _browser_path_is_usable {
    my ($path) = @_;
    return 0 if !defined $path || $path eq q{};
    return 0 if !File::Spec->file_name_is_absolute($path);
    return 0 if !-x $path || -d $path;

    my $exit = eval { Browser::Runner::NodeRuntime::_run_quiet_command( $path, '--version' ) };
    return 0 if $@;
    return 0 if $exit != 0;
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
