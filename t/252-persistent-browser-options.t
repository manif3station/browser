use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::CLI;
use Browser::Runner;

{
    package PersistentOptionsRunner;
    sub new { bless {}, shift }
    sub request { my ( $self, %args ) = @_; return \%args }
}

my $profile_result = Browser::CLI::execute(
    method => 'GET',
    argv   => [ 'https://example.test', '--profile=/tmp/browser-profile', '--keep-it-on', '--headless' ],
    runner => PersistentOptionsRunner->new(),
);
is( $profile_result->{profile}, '/tmp/browser-profile', 'CLI forwards the profile directory' );
is( $profile_result->{keep_it_on}, 1, 'CLI forwards --keep-it-on' );
is( $profile_result->{headless}, 0, '--keep-it-on forces a visible browser even with --headless' );

my $current_result = Browser::CLI::execute(
    method => 'GET',
    argv   => [ '--current', '--script', 'return document.title' ],
    runner => PersistentOptionsRunner->new(),
);
ok( $current_result->{current}, '--current is forwarded without a URL' );
is( $current_result->{url}, undef, '--current leaves URL unset so the active page is reused' );

my $ask_error = eval {
    Browser::CLI::execute(
        method => 'GET',
        argv   => [ 'https://example.test', '--keep-it-on', '--ask' ],
        runner => PersistentOptionsRunner->new(),
    );
    q{};
};
like( $@, qr/--keep-it-on cannot be combined with --ask\/--askme/, 'CLI rejects the unsupported keep-open and ask combination' );

my $dispatch_args;
{
    no warnings 'redefine';
    local *Browser::Runner::Persistent::request = sub { $dispatch_args = { @_ }; return { persistent => 1 } };
    my $runner = Browser::Runner->new( playwright_factory => sub { die 'regular launch should not run' } );
    my $result = $runner->request(
        method  => 'GET',
        url     => 'https://example.test',
        browser => 'chrome',
        profile => '/tmp/browser-profile',
    );
    is( $result->{persistent}, 1, 'profile requests use the persistent-context path' );
    is( $dispatch_args->{profile}, '/tmp/browser-profile', 'persistent path receives profile arguments' );
}

done_testing();
