use strict;
use warnings;

use Mac::FSEvents;
use Test::More;

my @FLAGS = qw{
    NONE
    WATCH_ROOT
    IGNORE_SELF
    FILE_EVENTS
};

foreach my $flag (@FLAGS) {
    ok !__PACKAGE__->can($flag), 'flags should not be imported unless :flags is specified';
}

done_testing;
