use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::CLI;

# D2B-163: closes 3 reachable branches in lib/Browser/CLI.pm found by a
# branch-coverage sweep extending the D2B-160/161/162 pattern. Branch
# coverage was 92.8% before this ticket. No behavioral change - each
# branch already does the right thing; these tests prove and document
# it.

eval {
    Browser::CLI::execute(
        method => 'DELETE',
        argv   => ['https://example.test'],
    );
};
like( $@, qr/Unsupported method: DELETE/, 'execute() refuses an unsupported method' );

eval {
    Browser::CLI::execute(
        method => 'GET',
        argv   => [ 'https://example.test', 'extra' ],
    );
};
like( $@, qr/Unexpected arguments/, 'execute() refuses extra positional arguments after the URL' );

eval {
    Browser::CLI::execute_search(
        argv => [ 'query', 'extra' ],
    );
};
like( $@, qr/Unexpected arguments/, 'execute_search() refuses extra positional arguments after the query' );

done_testing();
