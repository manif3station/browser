use strict;
use warnings;
use Test::More;
use JSON::PP qw(encode_json decode_json);

use lib 'lib';
use Browser::Search;

my @surrogates = ( 0xD800, 0xDBFF, 0xDC00, 0xDFFF );

for my $codepoint (@surrogates) {
    my $hex = sprintf( '%X', $codepoint );
    is( Browser::Search::_codepoint_to_char($codepoint), undef, "_codepoint_to_char rejects surrogate codepoint 0x$hex" );
}

is( Browser::Search::_codepoint_to_char(0xD7FF), chr(0xD7FF), '_codepoint_to_char still accepts the codepoint just below the surrogate range' );
is( Browser::Search::_codepoint_to_char(0xE000), chr(0xE000), '_codepoint_to_char still accepts the codepoint just above the surrogate range' );

my $decoded = Browser::Search::_strip_tags('bad &#xD800; surrogate entity');
is( $decoded, 'bad &#xD800; surrogate entity', '_strip_tags leaves a surrogate numeric entity as literal text instead of decoding it' );

my $decimal_decoded = Browser::Search::_strip_tags('bad &#56320; surrogate entity');
is( $decimal_decoded, 'bad &#56320; surrogate entity', '_strip_tags leaves a decimal surrogate numeric entity as literal text instead of decoding it' );

my $json;
{
    local $SIG{__WARN__} = sub { fail("unexpected warning while JSON-encoding: $_[0]") };
    $json = encode_json( { title => $decoded } );
}

my $round_tripped = decode_json($json);
is( $round_tripped->{title}, $decoded, 'JSON round-trip of a surrogate-entity-containing title is lossless (valid UTF-8, no corruption)' );

done_testing();
