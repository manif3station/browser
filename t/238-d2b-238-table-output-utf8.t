use strict;
use warnings;

use Test::More;
use Encode qw(decode FB_CROAK LEAVE_SRC);

use lib 'lib';
use Browser::CLI::TableOutput;

# D2B-238: the -o table printers wrote character strings straight to the
# output handle with no encoding, while the json path emits UTF-8 bytes
# via encode_json. A title with a character in U+0080-U+00FF (an accented
# letter, copyright sign, nbsp) came out as a single raw byte - invalid
# UTF-8, so a UTF-8 terminal showed a replacement character - and a
# character above U+00FF printed a "Wide character in print" warning.
#
# An in-memory filehandle has no layer, exactly like the bare STDOUT the
# CLI prints to, so capturing through one reproduces the real behavior.

my @warnings;
local $SIG{__WARN__} = sub { push @warnings, @_ };

sub capture {
    my ($code) = @_;
    my $out = q{};
    open my $fh, '>', \$out or die "Unable to open output scalar: $!";
    $code->($fh);
    close $fh;
    return $out;
}

sub decoded_or_undef {
    my ($bytes) = @_;
    return eval { decode( 'UTF-8', $bytes, FB_CROAK | LEAVE_SRC ) };
}

for my $case (
    [ 'an accented Latin-1-range character', "Caf\x{e9}" ],
    [ 'a character above U+00FF (em dash)',  "Foo \x{2014} Bar" ],
  )
{
    my ( $label, $title ) = @$case;

    my $get = capture(
        sub {
            Browser::CLI::TableOutput::print_table_result(
                'GET',
                {
                    method        => 'GET',
                    requested_url => 'http://example.test/',
                    final_url     => 'http://example.test/',
                    status        => 200,
                    content_type  => 'text/html',
                    is_captcha    => 0,
                    title         => $title,
                },
                $_[0]
            );
        }
    );
    my $get_text = decoded_or_undef($get);
    ok( defined $get_text, "get/post table output with $label is valid UTF-8" );
    like( $get_text // q{}, qr/\Q$title\E/, "get/post table output with $label decodes back to the original title" );

    my $search = capture(
        sub {
            Browser::CLI::TableOutput::print_search_table_result(
                {
                    query         => 'q',
                    engine_used   => 'bing',
                    engines_tried => ['bing'],
                    results       => [ { rank => 1, title => $title, url => 'http://example.test/' } ],
                },
                $_[0]
            );
        }
    );
    my $search_text = decoded_or_undef($search);
    ok( defined $search_text, "search table output with $label is valid UTF-8" );
    like( $search_text // q{}, qr/\Q$title\E/, "search table output with $label decodes back to the original title" );
}

is_deeply( \@warnings, [], 'no warnings (such as Wide character in print) were emitted while printing table output' )
  or diag( join q{}, @warnings );

done_testing();
