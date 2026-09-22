use strict;
use warnings;

use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib 'lib';
use Browser::Runner;

# D2B-196: mirrors t/109-d2b-109-png-file-directory-guard.t for
# browser.pdf - --file resolving to an existing directory must fail
# clearly at the Perl level, before ever reaching Playwright's pdf()
# call or running --script, exactly like browser.png already does.

{
    package FakePage;

    sub new { bless $_[1], $_[0] }
    sub goto { $_[0]{goto_args} = [ @_[ 1 .. $#_ ] ]; return $_[0]{response} }
    sub url { $_[0]{url} }
    sub title { $_[0]{title} }
    sub pdf { die "pdf() must not be called when --file is a directory\n" }
    sub evaluate { die "evaluate() must not be called when --file is a directory (D2B-131)\n" }
    sub emulateMedia { die "emulateMedia() must not be called when --file is a directory\n" }
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
}

{
    package FakePlaywright;
    sub new { bless $_[1], $_[0] }
    sub launch { return $_[0]{browser} }
    sub quit { $_[0]{quit_count}++; return 1 }
}

my $temp = tempdir( CLEANUP => 1 );
my $dir_as_pdf = File::Spec->catdir( $temp, 'report.pdf' );
mkdir $dir_as_pdf or die "Unable to create test fixture directory $dir_as_pdf: $!";

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
        method => 'PDF',
        url    => 'https://example.test',
        file   => $dir_as_pdf,
        script => 'return 1',
    );
};
like( $@, qr/\Q$dir_as_pdf\E/, 'browser.pdf dies naming the directory path when --file resolves to an existing directory' );
like( $@, qr/directory/i, 'browser.pdf\'s die message says the problem is a directory' );
unlike( $@, qr/pdf\(\) must not be called/, 'the fake pdf() guard never fires - the die happens before reaching Playwright at all' );
unlike( $@, qr/evaluate\(\) must not be called/, '--file validation happens before --script runs, so a bad --file never triggers a real script side effect' );
unlike( $@, qr/emulateMedia\(\) must not be called/, '--file validation happens before media emulation, so a bad --file never reaches Playwright at all' );

# D2B-196: also cover the default-tmp-path branch (no --file given) and
# the "response is falsy" branch, closing the coverage gaps a directory-
# collision-only test would otherwise leave in run_pdf.
{
    my $default_page = FakePage->new(
        {
            response => undef,
            url      => 'https://example.test/final',
            title    => 'Default Path',
        }
    );
    no warnings 'redefine';
    local *FakePage::pdf = sub {
        my ( $self, $options ) = @_;
        open my $fh, '>', $options->{path} or die "Unable to write fake pdf $options->{path}: $!";
        print {$fh} "%PDF-1.4 fake\n";
        close $fh;
        return 1;
    };
    local *FakePage::evaluate = sub { return { width => 10, height => 20 } };
    local *FakePage::emulateMedia = sub { return 1 };
    my $default_playwright = FakePlaywright->new( { browser => FakeBrowser->new( { page => $default_page } ) } );
    my $default_runner = Browser::Runner->new( playwright_factory => sub { return $default_playwright } );
    my $default_result = $default_runner->request(
        method => 'PDF',
        url    => 'https://example.test',
    );
    like( $default_result->{file}, qr/\.pdf\z/, 'PDF request with no --file given still writes to a generated tmp path ending in .pdf' );
    is_deeply( $default_result->{headers}, {}, 'PDF payload degrades headers to an empty hashref when the response is falsy' );
    unlink $default_result->{file};
}

done_testing();
