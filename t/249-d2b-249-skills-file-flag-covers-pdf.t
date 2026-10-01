use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use Test::More;

# D2B-249: SKILLS.md - the agent manual that browser.skills prints verbatim -
# described --file in its flag list as "PNG-only screenshot destination", but
# browser.pdf (D2B-196) reads it too: the CLI accepts --file for PNG and PDF
# and refuses it on GET and POST, the usage text says "Screenshot/PDF
# destination path (browser.png/browser.pdf only)", and two other places in
# SKILLS.md already describe pdf's --file. The flag list contradicted all of
# that and was the only "PNG-only" wording in the repo. This pins the bullet.
# Each check first asserts that what it looks at was found, so a moved or
# renamed section fails loudly instead of passing on nothing.

sub _slurp {
    my ($path) = @_;
    open my $fh, '<:encoding(UTF-8)', $path or die "Unable to open $path: $!";
    local $/;
    my $text = <$fh>;
    close $fh;
    return $text;
}

my $skills = _slurp('SKILLS.md');
my ($section) = $skills =~ m{^## Flags \(browser\.get/post/png/pdf\)[^\n]*\n(.*?)^## }ms;
ok( defined $section, 'found the "Flags (browser.get/post/png/pdf)" section of SKILLS.md' );

my @bullets = split /^(?=- )/m, $section // q{};
cmp_ok( scalar @bullets, '>=', 8, 'the flags section has its bullets' );

my ($file) = grep { /^- `--file PATH`/ } @bullets;
ok( defined $file, 'found the --file bullet' );
$file //= q{};

# 1. It covers both commands.
like( $file, qr/browser\.png/, 'the --file bullet names browser.png' );
like( $file, qr/browser\.pdf/, 'the --file bullet names browser.pdf' );
like( $file, qr/\.pdf\b/, 'the --file bullet says the PDF suffix is .pdf' );
unlike( $file, qr/PNG-only/i, 'the --file bullet no longer calls --file PNG-only' );

# 2. The rest of it is unchanged in meaning.
like( $file, qr{refused\s+on\s+(?:browser\.)?GET/POST}i, 'the --file bullet still says it is refused on GET/POST' );
like( $file, qr/\.PNG/, 'the --file bullet keeps the letter-case sentence for .png (D2B-248)' );
like( $file, qr/\.png\s+appended|appended/i, 'the --file bullet still says a missing suffix is appended' );

# 3. Nothing else in the flags section calls --file PNG-only.
my @others = grep { $_ ne $file && /PNG-only/i && /--file/ } @bullets;
is( scalar @others, 0, 'no other bullet in the flags section calls --file PNG-only' );

done_testing();
