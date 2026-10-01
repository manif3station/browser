use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use Test::More;

use Browser::CLI ();

# D2B-247: Browser::CLI::sanitize_error (D2B-015, D2B-180) strips every
# "at FILE line N." suffix from an error before the CLI prints it, but an error
# raised through Playwright's request code is a Carp-style backtrace: the message,
# then tab-indented lines such as
#     Playwright::Base::_do(Playwright::Page=HASH(0x...), "command", ...) called at FILE line N
# Those lines do not end in a period, so they were left in and the whole trace
# was printed - 14 lines and 2327 bytes of stderr for a mistyped --script (a
# JavaScript syntax error) in the test container, naming internal files, object
# addresses and the user's own arguments. Only the backtrace lines go; every
# other message is printed exactly as before.

# The trace captured from the container for: browser.get <page> --script 'return 1+'
my $trace = join q{},
  "Unexpected token '}' at /usr/local/share/perl/5.40.1/Playwright/Util.pm line 138.\n",
  "\tPlaywright::Util::request(\"POST\", \"command\", \"localhost\", 33819, LWP::UserAgent=HASH(0x5759398076d8), \"object\", \"page\\\@0831f520336b669b5f0240b932b881d0\", \"args\", ...) called at /usr/local/share/perl/5.40.1/Playwright/Base.pm line 94\n",
  "\tPlaywright::Base::_do(Playwright::Page=HASH(0x57593af8aac0), \"command\", \"evaluate\", \"type\", \"Page\", \"args\", ARRAY(0x57593a54ff60), \"object\", ...) called at /usr/local/share/perl/5.40.1/Playwright/Base.pm line 120\n",
  "\tPlaywright::Page::evaluate(Playwright::Page=HASH(0x57593af8aac0), \"return 1+\") called at /work/cli/../lib/Browser/Runner.pm line 248\n",
  "\teval {...} called at /work/cli/../lib/Browser/Runner.pm line 72\n",
  "\tBrowser::Runner::request(Browser::Runner=HASH(0x575938ea4e30), \"method\", \"GET\", \"url\", \"data:text/html,<title>T</title><h1>hi</h1>\", \"script\", \"return 1+\", ...) called at /work/cli/../lib/Browser/CLI.pm line 22\n",
  "\tBrowser::CLI::main(\"method\", \"GET\", \"argv\", ARRAY(0x575938a08428)) called at cli/get line 10\n";

# 1. An error with a backtrace is printed as its message only.
{
    my $clean = Browser::CLI::sanitize_error($trace);
    is( $clean, "Unexpected token '}'", 'a backtrace is reduced to the message alone' );
    unlike( $clean, qr/called at/, 'no "called at" lines are left' );
    unlike( $clean, qr{/usr/local|/work/|\.pm\b}, 'no file path is left' );
    unlike( $clean, qr/HASH\(0x|ARRAY\(0x/, 'no object address is left' );
    unlike( $clean, qr/return 1\+|data:text/, 'none of the caller\'s arguments are left' );
}

# 2. A backtrace inside a longer message goes too, and the rest of the message stays.
{
    my $message = "All search engines failed: bing (request failed: Boom\n\tFoo::bar(1) called at /x/Foo.pm line 3\n\teval {...} called at /x/Foo.pm line 9), google (CAPTCHA/bot-check wall)";
    is( Browser::CLI::sanitize_error($message), 'All search engines failed: bing (request failed: Boom), google (CAPTCHA/bot-check wall)', 'a backtrace inside a longer message is removed and the rest is kept' );
}

# 3. Every other message is unchanged.
{
    is( Browser::CLI::sanitize_error("Boom at /tmp/x.pl line 7.\n"), 'Boom', 'the existing "at FILE line N." suffix is still removed' );
    is( Browser::CLI::sanitize_error('Missing URL'), 'Missing URL', 'a plain message is unchanged' );

    my $multi = "Command could not be run: npx --yes npm install (No such file or directory)\ncaptured stdout:\n\ncaptured stderr:\nCan't exec \"npx\": No such file or directory\n";
    my $clean = Browser::CLI::sanitize_error($multi);
    like( $clean, qr/\ACommand could not be run: npx --yes npm install \(No such file or directory\)\ncaptured stdout:\n\ncaptured stderr:\nCan't exec "npx": No such file or directory\z/, 'a multi-line message with captured sections keeps every line' );

    is( Browser::CLI::sanitize_error("Two lines\n\tan indented note"), "Two lines\n\tan indented note", 'a tab-indented line that is not a backtrace line is kept' );
    is( Browser::CLI::sanitize_error('it was called at noon'), 'it was called at noon', 'the words "called at" without a file and line are kept' );
}

done_testing();
