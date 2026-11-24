package Browser::Runner::Persistent;

use strict;
use warnings;

use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempfile);
use JSON::PP qw(encode_json decode_json);
use Time::HiRes qw(sleep);
use Digest::SHA qw(sha256_hex);

use Browser::Runner::BrowserPath ();
use Browser::Runner::Capture ();
use Browser::Runner::NodeRuntime ();

sub request {
    my (%args) = @_;
    die "--profile/--keep-it-on cannot be combined with Perl controller mode (--playwright/--agent/--flow)"
      if $args{controller};

    my $method = uc( $args{method} || q{} );
    my $file;
    my $owns_file = 0;
    if ( $method eq 'PNG' || $method eq 'PDF' ) {
        my $extension = lc $method;
        Browser::Runner::Capture::check_output_name( $args{file} );
        $owns_file = !( defined $args{file} && $args{file} ne q{} );
        $file = Browser::Runner::Capture::reserved_output_path( $args{file}, $extension );
        if ( -d $file ) {
            unlink $file if $owns_file;
            die "--file points at an existing directory: $file";
        }
        my $dir = dirname($file);
        if ( $dir ne q{} && !-d $dir ) {
            eval { make_path($dir); 1 } or do {
                my $error = $@ || "Unable to create output directory $dir";
                unlink $file if $owns_file;
                die $error;
            };
        }
    }

    Browser::Runner::NodeRuntime::_ensure_node_runtime();
    my %launch = Browser::Runner::BrowserPath::_launch_options(%args);
    my $home = Browser::Runner::NodeRuntime::_home_root( context => 'browser skill persistent profile runtime' );
    my $worker = File::Spec->catfile( Browser::Runner::NodeRuntime::skill_root(), 'libexec', 'persistent-browser.js' );
    my $playwright = File::Spec->catfile( $home, 'node_modules', 'playwright' );
    my $jquery = File::Spec->catfile( $home, 'node_modules', 'jquery', 'dist', 'jquery.min.js' );
    my $profile = defined $args{profile} ? File::Spec->rel2abs( $args{profile} ) : undef;
    my $session_dir = File::Spec->catdir( $home, '.developer-dashboard', 'cache', 'browser-sessions' );
    make_path($session_dir) if !-d $session_dir;
    chmod 0700, $session_dir;
    my $session_key = defined $profile ? "profile:$profile" : 'default';
    my $session_file = File::Spec->catfile( $session_dir, sha256_hex($session_key) . '.json' );

    my ( $input_fh, $input_path ) = tempfile( 'browser-profile-input-XXXXXX', DIR => File::Spec->tmpdir(), UNLINK => 1 );
    my ( $output_fh, $output_path ) = tempfile( 'browser-profile-output-XXXXXX', DIR => File::Spec->tmpdir(), UNLINK => 1 );
    my %payload = (
        method      => $method,
        url         => $args{url},
        browser     => $args{browser} || 'chrome',
        headless    => $args{headless} ? JSON::PP::true : JSON::PP::false,
        keepItOn    => $args{keep_it_on} ? JSON::PP::true : JSON::PP::false,
        profile     => $profile,
        current     => $args{current} ? JSON::PP::true : JSON::PP::false,
        script      => $args{script},
        jquery      => $args{jquery} ? JSON::PP::true : JSON::PP::false,
        jqueryPath  => $jquery,
        data        => $args{data},
        waitUntil   => $args{wait_until} || ( $args{interactive} ? 'load' : 'networkidle' ),
        timeout     => defined $args{timeout_ms} ? $args{timeout_ms} : ( $args{interactive} ? 0 : undef ),
        interactive => $args{interactive} ? JSON::PP::true : JSON::PP::false,
        file        => $file,
        executablePath => $launch{executablePath},
        channel     => $launch{channel},
        playwrightPath => $playwright,
        sessionFile => $session_file,
    );
    print {$input_fh} encode_json(\%payload) or die "Unable to write persistent browser request: $!";
    close $input_fh or die "Unable to close persistent browser request: $!";
    close $output_fh or die "Unable to close persistent browser response: $!";
    unlink $output_path or die "Unable to prepare persistent browser response path: $!";

    my $status = 0;
    if ( $args{keep_it_on} ) {
        my $pid = fork();
        die "Unable to start persistent browser worker: $!" if !defined $pid;
        if ( !$pid ) {
            require POSIX;
            POSIX::setsid();
            open STDIN,  '<', '/dev/null';
            open STDOUT, '>', '/dev/null';
            open STDERR, '>', '/dev/null';
            exec 'node', $worker, $input_path, $output_path;
            exit 127;
        }
        while ( !-s $output_path ) {
            last if waitpid( $pid, 1 ) == $pid;
            sleep 0.05;
        }
    }
    else {
        $status = system( 'node', $worker, $input_path, $output_path );
    }
    open my $result_fh, '<', $output_path or do {
        unlink $file if $owns_file && defined $file;
        die "Unable to read persistent browser response: $!";
    };
    local $/;
    my $decoded = eval { decode_json(<$result_fh>) };
    close $result_fh;
    if ( !$decoded || ref $decoded ne 'HASH' || !$decoded->{ok} ) {
        unlink $file if $owns_file && defined $file;
        my $error = ref $decoded eq 'HASH' && $decoded->{error} ? $decoded->{error}
          : $status == -1 ? 'Persistent browser worker could not be started'
          : $status != 0 ? "Persistent browser worker failed (exit status " . ( $status >> 8 ) . ")"
          : 'Persistent browser worker returned an invalid response';
        die $error;
    }
    die "Persistent browser worker exited unexpectedly (exit status " . ( $status >> 8 ) . ")" if $status != 0;
    my $result = $decoded->{result};
    if ( ( $method eq 'GET' || $method eq 'POST' ) && ref $result eq 'HASH' ) {
        $result->{is_captcha} = Browser::Runner::_is_captcha_page(
            title     => $result->{title},
            body      => $result->{body},
            body_text => $result->{body_text},
        );
    }
    print { $args{prompt_fh} || \*STDERR } "Browser is open in a separate window and will stay open until you close it.\n"
      if $args{keep_it_on};
    return $result;
}

1;
