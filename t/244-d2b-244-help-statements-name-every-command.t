use strict;
use warnings;

use Test::More;

# D2B-244: browser.pdf (D2B-196) accepts --help like every other command -
# Browser::CLI::execute() answers --help for GET, POST, PNG and PDF before it
# parses a single option - but three statements in the docs still listed only
# get, post, png and search. docs/usage.md, a few lines earlier, already said
# "any of the five commands". This pins every statement about which commands
# accept --help: it must either name every command that has a cli/ script or
# give the right count of them. Each file first asserts that the statements
# were found, so a reworded sentence fails loudly instead of passing on
# nothing.

sub _slurp {
    my ($path) = @_;
    open my $fh, '<:encoding(UTF-8)', $path or die "Unable to open $path: $!";
    local $/;
    my $text = <$fh>;
    close $fh;
    return $text;
}

# Every command that accepts --help is a cli/ script, except browser.skills,
# which only prints the manual.
my @commands = sort map { m{/([^/]+)\z} ? "browser.$1" : () } grep { !m{/skills\z} } glob 'cli/*';
cmp_ok( scalar @commands, '>=', 5, 'found the cli/ scripts that accept --help (get, post, png, pdf, search)' );

my %number = ( four => 4, five => 5, six => 6, seven => 7 );
my $count = scalar @commands;

# The sentence shapes that say which commands accept --help.
my $statement = qr/`--help` (?:is recognized on|prints usage text and exits 0 for any of)\b/;

my %expected = ( 'README.md' => 2, 'docs/usage.md' => 2 );

for my $file ( sort keys %expected ) {
    my @statements = grep { /$statement/ } split /\n/, _slurp($file);
    cmp_ok( scalar @statements, '>=', $expected{$file}, "found the --help statements in $file" );

    for my $line (@statements) {
        my ($start) = $line =~ /($statement[^\n]*)/;
        my @missing = grep { index( $start, "`$_`" ) < 0 } @commands;
        my ($word)  = $start =~ /\bthe (\w+) commands\b/;
        my $counted = defined $word && ( $number{ lc $word } // 0 ) == $count;

        ok( !@missing || $counted, "$file: the statement '" . substr( $start, 0, 60 ) . "...' names every command or counts them correctly" )
          or diag( 'does not name: ' . join( ', ', @missing ) );
    }
}

done_testing();
