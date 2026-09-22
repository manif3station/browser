package Browser::Runner::Capture;

use strict;
use warnings;

use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempfile);
use JSON::PP ();

# D2B-196: extracted from Browser::Runner (which was pushing past this
# workspace's 500-line-per-module guideline once PDF export was added) -
# mirrors the VersionCompare.pm precedent (extracted from NodeRuntime.pm
# for the same reason). _goto_options/_interact_and_run_script/
# _defined_or_empty remain private to Browser::Runner and are called
# back into fully-qualified, the same way any other cross-module private
# helper call works in Perl - there is no true privacy enforcement, only
# the leading-underscore naming convention this codebase already relies
# on throughout.

sub screenshot_path {
    my ($requested) = @_;
    return reserved_output_path( $requested, 'png' );
}

sub reserved_output_path {
    my ( $requested, $extension ) = @_;
    if ( defined $requested && $requested ne q{} ) {
        return $requested if $requested =~ /\.\Q$extension\E\z/i;
        return "$requested.$extension";
    }

    # D2B-134: reserve the default path atomically and exclusively via
    # File::Temp (O_CREAT|O_EXCL under the hood), instead of merely
    # computing a hash-derived path string for Playwright to write to -
    # closing the window where another process/symlink could pre-empt it.
    my ( $fh, $path ) = tempfile(
        'browser-' . ( 'X' x 16 ),
        SUFFIX => ".$extension",
        DIR    => File::Spec->tmpdir(),
        UNLINK => 0,
    );
    close $fh or die "Unable to close reserved $extension output path $path: $!";
    return $path;
}

# D2B-197: shared scaffolding for run_png/run_pdf - both need goto, a
# reserved output path, the existing-directory guard, make_path, running
# the script/jquery callback inside a protected eval, cleanup-on-failure
# of only the placeholder this call itself reserved (D2B-134/D2B-135), and
# an identical result hashref shape. Each caller supplies only its own
# extension and the Playwright call that actually produces the file.
sub _capture {
    my ( $page, %args ) = @_;

    # Codex review: pull these three out under distinct keys and delete
    # them from %args before %args is spread anywhere else - result_method/
    # extension/write must never collide with %args' own real 'method' key
    # (the caller's original, possibly-lowercase request method), or the
    # same duplicate-key hash-flattening bug D2B-195 already fixed once
    # would silently reappear: the controller script's $method argument
    # (see _run_controller_script's positional args) would see this
    # normalized PNG/PDF label instead of the caller's actual value.
    my $result_method = delete $args{result_method};
    my $extension = delete $args{extension};
    my $write = delete $args{write};

    my $response = $page->goto( $args{url}, Browser::Runner::_goto_options(%args) );

    # D2B-131 (review follow-up): validate --file before running the
    # script/jquery below, so a bad --file fails fast without ever
    # running a script with real side effects on the page.
    my $owns_file = !( defined $args{file} && $args{file} ne q{} );
    my $file = reserved_output_path( $args{file}, $extension );

    my $script_result;
    my $ok = eval {
        # D2B-135 (review follow-up): this validation and make_path also
        # run inside the protected block, so a failure here is cleaned
        # up the same way a later script/write failure is.
        die "--file points at an existing directory: $file" if -d $file;
        my $dir = dirname($file);
        make_path($dir) if defined $dir && $dir ne q{} && !-d $dir;

        # D2B-131: run --script/--jquery before writing the file, mirroring
        # _run_get/_run_post, instead of silently ignoring both flags.
        $script_result = Browser::Runner::_interact_and_run_script( $page, %args, response => $response );

        $write->( $page, $file );
        1;
    };
    if ( !$ok ) {
        my $error = $@;
        # D2B-135: only clean up the placeholder this call itself
        # reserved (D2B-134) - a user-supplied --file is never deleted
        # by this skill.
        unlink $file if $owns_file;
        die $error;
    }

    my $headers = $response ? ( $response->headers() || {} ) : {};

    my $result = {
        method        => $result_method,
        requested_url => $args{url},
        final_url     => $page->url(),
        status        => $response ? $response->status() : undef,
        title         => Browser::Runner::_defined_or_empty( eval { $page->title() } ),
        content_type  => $headers->{'content-type'},
        headers       => $headers,
        file          => $file,
    };
    $result->{script_result} = $script_result if defined $args{script};
    return $result;
}

sub run_png {
    my ( $page, %args ) = @_;
    return _capture(
        $page, %args,
        result_method => 'PNG',
        extension     => 'png',
        write     => sub {
            my ( $page, $file ) = @_;
            $page->screenshot(
                {
                    path     => $file,
                    fullPage => JSON::PP::true,
                }
            );
        },
    );
}

sub run_pdf {
    my ( $page, %args ) = @_;
    return _capture(
        $page, %args,
        result_method => 'PDF',
        extension     => 'pdf',
        write     => sub {
            my ( $page, $file ) = @_;

            # D2B-196 (fork-hunt follow-up, Codex round 1): page->pdf() renders
            # under the "print" CSS media by default, but the dimensions below
            # are measured under whatever media is currently emulated (Playwright
            # defaults new pages to "screen"). Forcing "screen" explicitly here
            # keeps the measured scrollWidth/scrollHeight in sync with what pdf()
            # actually renders, instead of letting a page's print stylesheet
            # reflow/hide content that was already measured under screen layout.
            $page->emulateMedia( { media => 'screen' } );

            # Playwright's page->pdf() has no "fullPage" option the way
            # screenshot() does - with no size options at all, it silently
            # defaults to paginated US-Letter output, chopping a tall page into
            # multiple discrete pages instead of capturing it as one continuous
            # document. Measuring the page's actual rendered size and passing it
            # as width/height (in px) is PDF's equivalent of screenshot()'s
            # fullPage=>true - a single page sized exactly to the content, not
            # paginated. printBackground is also enabled, since Playwright's PDF
            # export otherwise drops CSS background colors/images by default,
            # unlike screenshot() which always includes them.
            my $dimensions = $page->evaluate(
                'return { width: document.documentElement.scrollWidth, height: document.documentElement.scrollHeight };'
            );

            # Codex round 2: evaluate() is trusted to return a {width,height}
            # hashref, but nothing enforces that at the boundary - guard it
            # explicitly instead of letting a non-hashref (or undef) blow up
            # with Perl's generic "Can't use ... as a HASH reference" error.
            die 'browser.pdf could not measure the page (evaluate() did not return the expected {width,height} object)'
              unless ref $dimensions eq 'HASH';

            # Chromium's PDF export refuses paper sizes beyond roughly 200in
            # per side; capping here at that same practical limit (200in at
            # the standard 96px/in CSS-pixel ratio) turns a resource-hungry
            # native failure into a clear, immediate error instead.
            my $max_px = 19_200;
            for my $axis (qw(width height)) {
                my $value = $dimensions->{$axis};
                die "browser.pdf could not measure a usable page $axis (got "
                  . ( defined $value ? "'$value'" : 'undef' ) . ")"
                  unless defined $value && $value =~ /\A\d+(?:\.\d+)?\z/ && $value > 0;
                die "browser.pdf refuses to render a page $axis of ${value}px - exceeds the $max_px px practical PDF page-size limit"
                  if $value > $max_px;
            }
            $page->pdf(
                {
                    path            => $file,
                    width           => "$dimensions->{width}px",
                    height          => "$dimensions->{height}px",
                    printBackground => JSON::PP::true,
                }
            );
        },
    );
}

1;
