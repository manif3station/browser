use strict;
use warnings;

use Test::More;
use Encode qw(decode encode FB_CROAK LEAVE_SRC);

use lib 'lib';
use Browser::CLI;
use Browser::Runner;

# D2B-243: D2B-240 decoded the script option for every mode. That is right
# for a page script (JS the browser evaluates, sent to Playwright as
# characters) but wrong for a Perl CONTROLLER script (--playwright, --agent,
# --flow): Browser::Runner string-evals it as Perl source, so decoding turned
# its literals into characters and an accented literal it printed came out as
# a lone invalid byte (c3 a9 became e9). Controller mode now receives the
# script exactly as given on the command line.

my @warnings;
local $SIG{__WARN__} = sub { push @warnings, @_ };

{
    package RecordingRunner;

    sub new { bless { calls => [] }, shift }

    sub request {
        my ( $self, %args ) = @_;
        push @{ $self->{calls} }, {%args};
        return {
            method        => $args{method},
            requested_url => $args{url},
            final_url     => $args{url},
            status        => 200,
            title         => 'Title',
            content_type  => 'text/html',
            headers       => {},
            body          => q{},
            body_text     => q{},
            is_captcha    => 0,
        };
    }
}

sub _call {
    my (@argv) = @_;
    my $runner = RecordingRunner->new();
    my ( $output, $error ) = ( q{}, q{} );
    open my $output_fh, '>', \$output or die "Unable to open output scalar: $!";
    open my $error_fh,  '>', \$error  or die "Unable to open error scalar: $!";
    my $rc = Browser::CLI::main( method => 'GET', argv => \@argv, runner => $runner, output_fh => $output_fh, error_fh => $error_fh );
    close $output_fh;
    close $error_fh;
    return ( $rc, $error, $runner->{calls}[0] );
}

my $cafe_bytes = encode( 'UTF-8', "caf\x{e9}" );
my $script     = qq{print "$cafe_bytes\\n"; 1};

# 1. Controller mode: the runner gets the original bytes.
for my $flag (qw(--playwright --agent --flow)) {
    my ( $rc, $error, $call ) = _call( 'https://example.test', $flag, '--script', $script );
    is( $rc, 0, "$flag with an accented --script exits 0" ) or diag($error);
    ok( $call->{controller}, "$flag puts the runner in controller mode" );
    is( $call->{script}, $script, "$flag: the runner receives the script exactly as given, as bytes" );
}

# 2. A page script (no controller flag) is still decoded.
{
    my ( undef, undef, $call ) = _call( 'https://example.test', '--script', "document.title = '$cafe_bytes'" );
    ok( !$call->{controller}, 'without a controller flag the runner is not in controller mode' );
    is( $call->{script}, "document.title = 'caf\x{e9}'", 'a page script is still decoded to characters' );
}

# 3. The behavior this protects: a controller script handed the original
#    bytes prints its accented literal as valid UTF-8.
{
    my $out = q{};
    open my $fh, '>', \$out or die "open: $!";
    my $old = select($fh);
    eval { Browser::Runner::_run_controller_script( undef, script => $script ) };
    my $err = $@;
    select($old);
    close $fh;
    is( $err, q{}, 'the controller script ran without error' );
    is( $out, "$cafe_bytes\n", 'a controller script given the original bytes prints its accented literal as valid UTF-8' );
    ok( defined( eval { decode( 'UTF-8', $out, FB_CROAK | LEAVE_SRC ) } ), 'what it printed is valid UTF-8' );
}

is_deeply( \@warnings, [], 'no warnings were emitted' ) or diag( join q{}, @warnings );

done_testing();
