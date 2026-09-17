use strict;
use warnings;

use Test::More;

use lib 'lib';
use Browser::Search;

# D2B-028: Browser::Search::search must always launch the runner headless,
# matching browser.get/post/png's own default. Browser::CLI::execute sets
# headless => 1 explicitly before calling the runner; Browser::Search::search
# never set it at all, and Browser::Runner::BrowserPath::_launch_options
# treats an unset headless as false ('headless => $args{headless} ? 1 : 0'),
# so every browser.search call launched a visible browser.

{
    package RecordingRunner;
    sub new { my ( $class, $code ) = @_; return bless { calls => [], code => $code }, $class; }
    sub request {
        my ( $self, %args ) = @_;
        push @{ $self->{calls} }, {%args};
        return $self->{code} ? $self->{code}->(%args) : { is_captcha => 0, body => q{} };
    }
}

my $runner = RecordingRunner->new();
eval {
    Browser::Search::search(
        query   => 'test query',
        engines => [
            { name => 'bing', url => sub { 'https://www.bing.com/search?q=' . $_[0] } },
        ],
        runner => $runner,
    );
};

is( scalar @{ $runner->{calls} }, 1, 'sanity check: the runner was called exactly once' );
is( $runner->{calls}[0]{headless}, 1, "search()'s request() call passes headless => 1" );

# Fallback case: every engine attempted (walled or not) must be launched headless.
my $call_count = 0;
$runner = RecordingRunner->new(
    sub {
        $call_count++;
        return { is_captcha => 1, body => q{} } if $call_count == 1;
        return { is_captcha => 0, body => q{} };
    }
);
eval {
    Browser::Search::search(
        query   => 'test query',
        engines => [
            { name => 'bing',   url => sub { 'https://www.bing.com/search?q=' . $_[0] } },
            { name => 'google', url => sub { 'https://www.google.com/search?q=' . $_[0] } },
        ],
        runner => $runner,
    );
};
is( scalar @{ $runner->{calls} }, 2, 'sanity check: both engines were attempted (first walled, second clean)' );
is( $runner->{calls}[0]{headless}, 1, "the walled engine's own call still passes headless => 1" );
is( $runner->{calls}[1]{headless}, 1, "the fallback engine's call also passes headless => 1" );

done_testing();
