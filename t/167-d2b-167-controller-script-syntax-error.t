use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Runner;

# D2B-167: closes the one remaining untested branch in
# lib/Browser/Runner.pm's _run_controller_script - the compile-time
# eval that builds the user's --script text into a closure (line
# ~297-306). Only the runtime-die branch (script compiles, then dies
# when called) was previously tested, in t/04-runner-unit.t. No
# behavioral change - the branch already does the right thing; this
# test proves and documents it.

{
    package FakePage;
    sub new { bless $_[1], $_[0] }
    sub url { $_[0]{url} }
}

{
    package FakeBrowser;
    sub new { bless $_[1], $_[0] }
}

{
    package FakePlaywright;
    sub new { bless $_[1], $_[0] }
}

{
    package FakeResponse;
    sub new { bless $_[1], $_[0] }
    sub status { $_[0]{status} }
}

my $page = FakePage->new( {} );

eval {
    Browser::Runner::_run_controller_script(
        $page,
        browser    => FakeBrowser->new( {} ),
        playwright => FakePlaywright->new( {} ),
        response   => FakeResponse->new( { status => 200 } ),
        method     => 'GET',
        url        => 'https://example.test',
        script     => q{this is +++ not valid perl (((},
    );
};
like(
    $@,
    qr/Controller script failed: syntax error/,
    'a compile-time syntax error in --script is reported as "Controller script failed: syntax error..."'
);
unlike(
    $@,
    qr/bad flow/,
    'the compile-time failure message is distinguishable from a runtime-die failure message'
);

done_testing();
