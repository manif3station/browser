use strict;
use warnings;

use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib 'lib';
use Browser::Runner;

# D2B-109: browser.png's --file silently attempted to write a screenshot to
# an existing directory path when that path happened to already end in
# '.png' - _screenshot_path only appends '.png' if the path doesn't already
# end in it, so an existing directory named e.g. 'shot.png' passed through
# unchanged and reached Playwright's screenshot() call directly, instead of
# failing with a clear Perl-level message.

{
    package FakePage;

    sub new { bless $_[1], $_[0] }
    sub goto { $_[0]{goto_args} = [ @_[ 1 .. $#_ ] ]; return $_[0]{response} }
    sub url { $_[0]{url} }
    sub title { $_[0]{title} }
    sub screenshot { die "screenshot() must not be called when --file is a directory\n" }
    sub evaluate { die "evaluate() must not be called when --file is a directory (D2B-131)\n" }
}

{
    package FakeResponse;
    sub new { bless $_[1], $_[0] }
    sub status { $_[0]{status} }
}

{
    package FakeBrowser;
    sub new { bless $_[1], $_[0] }
    sub newPage { return $_[0]{page} }
    sub close { $_[0]{closed} = 1; return 1 }
}

{
    package FakePlaywright;
    sub new { bless $_[1], $_[0] }
    sub launch { return $_[0]{browser} }
    sub quit { $_[0]{quit_count}++; return 1 }
}

my $temp = tempdir( CLEANUP => 1 );
my $dir_as_png = File::Spec->catdir( $temp, 'shot.png' );
mkdir $dir_as_png or die "Unable to create test fixture directory $dir_as_png: $!";

my $page = FakePage->new(
    {
        response => FakeResponse->new( { status => 200 } ),
        url      => 'https://example.test/final',
        title    => 'Example',
    }
);
my $playwright = FakePlaywright->new(
    {
        browser => FakeBrowser->new( { page => $page } ),
    }
);
my $runner = Browser::Runner->new(
    playwright_factory => sub { return $playwright },
);

eval {
    $runner->request(
        method => 'PNG',
        url    => 'https://example.test',
        file   => $dir_as_png,
        script => 'return 1',
    );
};
like( $@, qr/\Q$dir_as_png\E/, 'browser.png dies naming the directory path when --file resolves to an existing directory' );
like( $@, qr/directory/i, 'browser.png\'s die message says the problem is a directory' );
unlike( $@, qr/screenshot\(\) must not be called/, 'the fake screenshot() guard never fires - the die happens before reaching Playwright at all' );
unlike( $@, qr/evaluate\(\) must not be called/, 'D2B-131: --file validation happens before --script runs, so a bad --file never triggers a real script side effect' );

done_testing();
