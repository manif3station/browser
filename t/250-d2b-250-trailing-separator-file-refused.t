use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use Browser::Runner ();
use Browser::Runner::Capture ();

# D2B-250: reserved_output_path appends the extension to any requested name
# that does not already end in it, so '--file /tmp/shots/' became
# '/tmp/shots/.png'; _capture then made the parent directory if it was missing
# and wrote the file. In the test container 'browser.png --file /tmp/d2b-dir/'
# exited 0 and left a hidden file named .png inside the directory, and a
# missing directory was created on the way - for browser.pdf too. The D2B-109
# guard ('--file points at an existing directory') tests the path after the
# extension is appended, so it only fires for a directory whose own name already
# ends in .png or .pdf. A trailing separator is the unmistakable way to name a
# directory, so it is now refused before the page is loaded and before anything
# is created or written. Every other spelling is unchanged.
#
# The stub page records every call, so no browser is needed.

{
    package StubPage;
    sub new          { return bless { gotos => 0, shots => [], pdfs => [] }, shift }
    sub goto         { $_[0]{gotos}++; return undef }
    sub url          { return 'about:blank' }
    sub title        { return 'T' }
    sub screenshot   { my ( $self, $options ) = @_; push @{ $self->{shots} }, $options; return 1 }
    sub evaluate     { return { width => 100, height => 100 } }
    sub emulateMedia { return 1 }
    sub pdf          { my ( $self, $options ) = @_; push @{ $self->{pdfs} }, $options; return 1 }
}

my $dir = tempdir( CLEANUP => 1 );
my $sep = '/';

# 1. A trailing separator is refused, for both commands, before anything happens.
for my $command (qw(png pdf)) {
    my $run = $command eq 'png' ? \&Browser::Runner::Capture::run_png : \&Browser::Runner::Capture::run_pdf;

    for my $given ( 'out' . $sep, 'a' . $sep . 'b' . $sep, $sep ) {
        my $path = $given eq $sep ? $sep : File::Spec->catdir( $dir, $given );
        $path .= $sep if $path !~ m{/\z};

        my $page  = StubPage->new;
        my $ok    = eval { $run->( $page, url => 'http://example.invalid/', file => $path ); 1 };
        my $error = $@;

        ok( !$ok, "$command: --file '$path' is refused" );
        like( $error, qr/--file ends with a path separator/, "$command: '$path' gets the new message" );
        like( $error, qr/\Q$path\E/, "$command: '$path' is named in the message" );
        is( $page->{gotos}, 0, "$command: '$path' is refused before the page is loaded" );
        is( scalar( @{ $page->{shots} } ) + scalar( @{ $page->{pdfs} } ), 0, "$command: '$path' is refused before anything is written" );
    }

    ok( !-e File::Spec->catdir( $dir, 'out' ), "$command: no directory was created for a refused path" );
    ok( !-e File::Spec->catdir( $dir, 'a' ), "$command: no nested directory was created for a refused path" );
}

# 2. Every other spelling is unchanged.
{
    my $page   = StubPage->new;
    my $result = Browser::Runner::Capture::run_png( $page, url => 'http://example.invalid/', file => File::Spec->catfile( $dir, 'out' ) );
    is( $result->{file}, File::Spec->catfile( $dir, 'out.png' ), 'a bare name still gets .png appended' );
    is( $page->{gotos}, 1, 'a bare name still loads the page' );
}
for my $name (qw(shot.png shot.PNG)) {
    my $page   = StubPage->new;
    my $result = Browser::Runner::Capture::run_png( $page, url => 'http://example.invalid/', file => File::Spec->catfile( $dir, $name ) );
    is( $result->{file}, File::Spec->catfile( $dir, $name ), "'$name' is kept as typed" );
}
{
    my $page   = StubPage->new;
    my $result = Browser::Runner::Capture::run_pdf( $page, url => 'http://example.invalid/', file => File::Spec->catfile( $dir, 'doc.PDF' ) );
    is( $result->{file}, File::Spec->catfile( $dir, 'doc.PDF' ), 'pdf keeps doc.PDF as typed' );
}
{
    my $page   = StubPage->new;
    my $result = Browser::Runner::Capture::run_png( $page, url => 'http://example.invalid/' );
    like( $result->{file}, qr/\.png\z/, 'the generated temporary path still ends in .png' );
    unlink $result->{file};
}

# 3. The D2B-109 guard for a directory that is named like the file is unchanged.
{
    my $named = File::Spec->catdir( $dir, 'shots.png' );
    mkdir $named or die "Unable to create $named: $!";
    my $page  = StubPage->new;
    my $ok    = eval { Browser::Runner::Capture::run_png( $page, url => 'http://example.invalid/', file => $named ); 1 };
    ok( !$ok, 'a directory literally named shots.png is still refused' );
    like( $@, qr/--file points at an existing directory/, 'and it keeps its own message' );
}

# 4. A backslash is only a separator on Windows; elsewhere it is a legal file-name character.
SKIP: {
    skip 'a trailing backslash is a separator on Windows', 2 if $^O eq 'MSWin32';
    my $page   = StubPage->new;
    my $ok     = eval { Browser::Runner::Capture::run_png( $page, url => 'http://example.invalid/', file => File::Spec->catfile( $dir, 'odd\\' ) ); 1 };
    ok( $ok, 'a trailing backslash is not refused outside Windows' ) or diag($@);
    is( $page->{gotos}, 1, 'and the page is loaded as usual' );
}

done_testing();
