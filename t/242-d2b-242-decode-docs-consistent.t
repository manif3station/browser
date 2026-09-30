use strict;
use warnings;

use Test::More;

# D2B-242: the D2B-238..240 edits left three statements wrong or misplaced,
# each about which command-line values are decoded (D2B-239, D2B-240):
#   1. the comment above Browser::CLI::_decode_argv_text still said "Only
#      these two positional values are decoded" - five values are;
#   2. README.md item 41 said "Only the positional URL and query are
#      decoded", contradicting item 42 directly below it;
#   3. SKILLS.md's "--help/--version still win over a malformed -o value"
#      sentence, the tail of the "-o table" bullet, ended up after the
#      --data/--script/--file bullet that was inserted in front of it.
# This pins all three. Each check first asserts that what it looks at was
# actually found, so a moved or renamed block fails loudly instead of
# passing on nothing.

sub _slurp {
    my ($path) = @_;
    open my $fh, '<:encoding(UTF-8)', $path or die "Unable to open $path: $!";
    local $/;
    my $text = <$fh>;
    close $fh;
    return $text;
}

# 1. The comment above _decode_argv_text.
{
    my $cli = _slurp('lib/Browser/CLI.pm');
    my ($comment) = $cli =~ /((?:^#[^\n]*\n)+)sub _decode_argv_text\b/m;
    ok( defined $comment, 'found the comment block above _decode_argv_text' );
    unlike( $comment // q{}, qr/Only these two positional values/i, 'the comment does not claim that only two values are decoded' );
    like( $comment // q{}, qr/data,[\s#]+script[\s#]+and[\s#]+file/i, 'the comment says that data, script and file are decoded too (the # allows for a wrapped comment line)' );
}

# 2. README items 41 and 42 agree.
{
    my $readme = _slurp('README.md');
    my ($item41) = $readme =~ /^41\. ([^\n]*)/m;
    my ($item42) = $readme =~ /^42\. ([^\n]*)/m;
    ok( defined $item41, 'found README edge case 41' );
    ok( defined $item42, 'found README edge case 42' );
    unlike( $item41 // q{}, qr/\bOnly the positional URL and query\b/, 'item 41 does not say that only the positional URL and query are decoded' );
    like( $item42 // q{}, qr/--data.*--script.*--file/s, 'item 42 says that --data, --script and --file are decoded' );
}

# 3. The --help/--version sentence sits in the "-o table" bullet.
{
    my $skills = _slurp('SKILLS.md');
    my ($section) = $skills =~ /^## Output format[^\n]*\n(.*?)^## /ms;
    ok( defined $section, 'found the Output format section of SKILLS.md' );

    my @bullets = split /^(?=- )/m, $section // q{};
    cmp_ok( scalar @bullets, '>=', 4, 'the Output format section has its bullets (json, table, url/query, data/script/file)' );

    my ($table)   = grep { /^- `-o table`/ } @bullets;
    my ($options) = grep { /`--data`, `--script` and `--file`/ } @bullets;
    ok( defined $table,   'found the -o table bullet' );
    ok( defined $options, 'found the --data/--script/--file bullet' );

    my $priority = qr/`--help`\/`--version` still win/;
    like( $table // q{}, $priority, 'the --help/--version priority sentence is in the -o table bullet it belongs to' );
    unlike( $options // q{}, $priority, 'the --help/--version priority sentence is not in the --data/--script/--file bullet' );
}

done_testing();
