use strict;
use warnings;

use Test::More;

use lib 'lib';

use_ok('Browser::CLI');
use_ok('Browser::Runner');
use_ok('Browser::Search');
use_ok('Browser::Runner::NodeRuntime');
use_ok('Browser::Runner::BrowserPath');

done_testing();
