use strict;
use warnings;

use Test::More;
use Browser::CLI;

# D2B-186: _argv_requests_help/_argv_requests_version (lib/Browser/CLI.pm)
# run a blind grep for a literal --help/--version element anywhere in the
# raw argv, before GetOptionsFromArray is ever called - with no awareness
# of a preceding literal -- end-of-options separator. SKILLS.md documents
# escaping a leading-dash positional argument with -- (e.g.
# `dashboard browser.get -- -example.com`), and Getopt::Long itself
# correctly treats everything after -- as positional - but since the
# help/version pre-check runs its own raw scan first, escaping the
# positional value --help or --version still gets misdetected as a
# help/version request instead of the literal escaped value.

package FakeRunner;
sub new { bless {}, shift }
sub request {
    my ( $self, %args ) = @_;
    return { method => $args{method}, requested_url => $args{url}, status => 200 };
}
package main;

package FakeSearchRunner;
sub new { bless { calls => [] }, shift }
sub request {
    my ( $self, %args ) = @_;
    push @{ $self->{calls} }, $args{url};
    return { is_captcha => 0, body => '<div class="g"><a href="https://example.com/x"><h3>X</h3></a><span class="VwiC3b">Y</span></div>' };
}
package main;

my $get_result = Browser::CLI::execute(
    method => 'GET',
    argv   => [ '--', '--version' ],
    runner => FakeRunner->new(),
);
ok( !$get_result->{version}, 'browser.get -- --version treats --version as the literal escaped URL, not a version request' )
  or diag( 'Got version payload instead: ' . ( $get_result->{version_string} || q{} ) );
is( $get_result->{requested_url}, '--version', 'the literal escaped URL is passed through to the runner unchanged' )
  if !$get_result->{version};

my $get_help_result = Browser::CLI::execute(
    method => 'GET',
    argv   => [ '--', '--help' ],
    runner => FakeRunner->new(),
);
ok( !$get_help_result->{help}, 'browser.get -- --help treats --help as the literal escaped URL, not a help request' )
  or diag('Got a help payload instead');

my $search_runner = FakeSearchRunner->new();
my $search_result = Browser::CLI::execute_search(
    argv   => [ '--', '--version' ],
    runner => $search_runner,
);
ok( !$search_result->{version}, 'browser.search -- --version treats --version as the literal escaped query, not a version request' );
like( $search_runner->{calls}[0], qr/q=--version/, 'the literal escaped query --version was actually sent to the search backend, not just avoided-being-a-version-request' );

# Sanity: a genuine, unescaped --help/--version must still short-circuit exactly as before.
my $bare_help = Browser::CLI::execute( method => 'GET', argv => [ 'https://example.test', '--help' ] );
ok( $bare_help->{help}, 'a genuine unescaped --help is unaffected and still short-circuits' );

my $bare_version = Browser::CLI::execute( method => 'GET', argv => [ 'https://example.test', '--version' ] );
ok( $bare_version->{version}, 'a genuine unescaped --version is unaffected and still short-circuits' );

# Edge case: a trailing bare -- with nothing after it (no positional value
# escaped at all) must not itself be misdetected, and an entirely empty
# argv must not die walking off the end of the truncation loop.
my $trailing_dash_result = eval {
    Browser::CLI::execute( method => 'GET', argv => [ 'https://example.test', '--' ], runner => FakeRunner->new() );
};
ok( !$@, 'a trailing bare -- with no escaped value after it does not die in the truncation helper' ) or diag("Got: $@");

my $empty_argv_result = eval { Browser::CLI::execute( method => 'GET', argv => [], runner => FakeRunner->new() ) };
like( $@, qr/Missing URL/, 'an entirely empty argv still fails with the normal Missing URL error, not a truncation-helper crash' );

done_testing();
