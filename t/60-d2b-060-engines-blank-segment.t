use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::CLI;

# D2B-060: a leading/trailing/doubled comma in --engines produced a blank
# entry in @requested_names, dying with an unhelpful "Unknown engine: "
# (no name shown) instead of silently dropping the empty segment.

{
    package FakeSearchRunner;
    sub new { bless { calls => [] }, shift }
    sub request {
        my ( $self, %args ) = @_;
        push @{ $self->{calls} }, {%args};
        return { is_captcha => 0, body => q{} };
    }
}

my $runner = FakeSearchRunner->new();
my $result = Browser::CLI::execute_search( argv => [ 'query', '--engines', ',bing' ], runner => $runner );
ok( $result, 'a leading comma in --engines does not die with a blank "Unknown engine:" error' );
is( $runner->{calls}[0]{url}, 'https://www.bing.com/search?q=query', 'the leading empty segment is dropped and bing is the only engine actually selected' );

$runner = FakeSearchRunner->new();
$result = Browser::CLI::execute_search( argv => [ 'query', '--engines', 'bing,,google' ], runner => $runner );
ok( $result, 'a doubled comma (empty segment) in --engines does not die' );
is( $result->{engine_used}, 'bing', 'the doubled-comma segment is dropped, leaving bing and google as the only two engines tried, bing first' );

$runner = FakeSearchRunner->new();
$result = Browser::CLI::execute_search( argv => [ 'query', '--engines', 'bing,' ], runner => $runner );
ok( $result, 'a trailing comma in --engines does not die' );
is( $result->{engine_used}, 'bing', 'the trailing empty segment is dropped, leaving only bing selected' );

$runner = FakeSearchRunner->new();
$result = Browser::CLI::execute_search( argv => [ 'query', '--engines', 'bing, ,google' ], runner => $runner );
ok( $result, 'a whitespace-only segment (trims to empty) in --engines does not die' );
is( $result->{engine_used}, 'bing', 'the whitespace-only segment is dropped after trimming, leaving bing and google selected' );

eval { Browser::CLI::execute_search( argv => [ 'query', '--engines', ',,' ], runner => FakeSearchRunner->new() ) };
like( $@, qr/--engines/, '--engines naming only empty segments still refuses with the "named no engines at all" message' );

eval { Browser::CLI::execute_search( argv => [ 'query', '--engines', '  ,  ' ], runner => FakeSearchRunner->new() ) };
like( $@, qr/--engines/, '--engines naming only whitespace-only segments still refuses with the "named no engines at all" message' );

eval { Browser::CLI::execute_search( argv => [ 'query', '--engine', 'bing', '--engines', ',google' ], runner => FakeSearchRunner->new() ) };
like( $@, qr/--engine and --engines cannot both be given/, '--engine and --engines together are still refused even when --engines has a blank segment' );

done_testing();
