use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use Browser::Runner ();
use Browser::Runner::Capture ();

# D2B-248: reserved_output_path keeps a --file name that already ends in the
# extension, matched case-insensitively (so 'shot.PNG' does not become
# 'shot.PNG.png'). run_png then gave Playwright's page->screenshot only a path
# and fullPage, so Playwright inferred the image type from the extension - and
# it does not recognise '.PNG' or '.Png': 'browser.png --file shot.PNG' exited
# 2 with 'path: unsupported mime type "null"' and wrote nothing (reproduced in
# the test container with a data: URL; '.png' worked, and browser.pdf with
# '.PDF' worked). The file name always ends in .png in some case, so png is
# always the right type: it is now passed explicitly.
#
# The stub page records the options each call receives, so no browser is needed.

{
    package StubPage;
    sub new      { return bless { shots => [], pdfs => [] }, shift }
    sub goto     { return undef }
    sub url      { return 'about:blank' }
    sub title    { return 'T' }
    sub screenshot { my ( $self, $options ) = @_; push @{ $self->{shots} }, $options; return 1 }
    sub evaluate { return { width => 100, height => 100 } }
    sub emulateMedia { return 1 }
    sub pdf      { my ( $self, $options ) = @_; push @{ $self->{pdfs} }, $options; return 1 }
}

my $dir = tempdir( CLEANUP => 1 );

# Every spelling of the extension gets png as the type, and the path is the one the user asked for.
my @cases = (
    [ 'shot.png' => 'shot.png' ],
    [ 'shot.PNG' => 'shot.PNG' ],
    [ 'shot.Png' => 'shot.Png' ],
    [ 'shot'     => 'shot.png' ],
    [ 'shot.jpg' => 'shot.jpg.png' ],
);
for my $case (@cases) {
    my ( $given, $expected ) = @{$case};
    my $page   = StubPage->new;
    my $result = Browser::Runner::Capture::run_png( $page, url => 'http://example.invalid/', file => File::Spec->catfile( $dir, $given ) );
    my $options = $page->{shots}[0] || {};

    is( scalar @{ $page->{shots} }, 1, "--file $given: screenshot is called once" );
    is( $options->{type}, 'png', "--file $given: the image type is given to Playwright as png" );
    is( $options->{path}, File::Spec->catfile( $dir, $expected ), "--file $given: the path is the one the user asked for" );
    ok( $options->{fullPage}, "--file $given: fullPage is still on" );
    is( $result->{file}, File::Spec->catfile( $dir, $expected ), "--file $given: the printed path matches" );
}

# The generated temporary path is unchanged, and also gets the type.
{
    my $page   = StubPage->new;
    my $result = Browser::Runner::Capture::run_png( $page, url => 'http://example.invalid/' );
    my $options = $page->{shots}[0] || {};
    like( $options->{path}, qr/\.png\z/, 'the generated temporary path still ends in .png' );
    is( $options->{type}, 'png', 'the generated temporary path gets the png type too' );
    unlink $result->{file};
}

# browser.pdf is untouched: it was never given a type and still is not.
{
    my $page = StubPage->new;
    Browser::Runner::Capture::run_pdf( $page, url => 'http://example.invalid/', file => File::Spec->catfile( $dir, 'doc.PDF' ) );
    my $options = $page->{pdfs}[0] || {};
    is( join( ',', sort keys %{$options} ), 'height,path,printBackground,width', 'pdf is given exactly the options it was given before' );
    is( $options->{path}, File::Spec->catfile( $dir, 'doc.PDF' ), 'pdf keeps an uppercase .PDF path as typed' );
}

done_testing();
