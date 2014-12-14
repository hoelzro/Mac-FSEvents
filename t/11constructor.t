#!/usr/bin/perl

use strict;

use Mac::FSEvents;

use Test::More tests => 4;

# Path must be given
{
    eval {
        my $ev = Mac::FSEvents->new({});
    };
    ok $@, 'path must be given';
    like $@, qr{\Qpath argument to new() must be supplied};
}

# Path must be absolute
{
    {
        package
            stringified;
        use overload "" => sub { return $_[0]->{path} };
    }

    eval {
        my $ev = Mac::FSEvents->new({
            path => bless( { path => 'tmp' }, 'stringified' ),
        });
    };
    ok $@, 'path must be string';
    like $@, qr{\Qpath argument to new() must be plain string};
}

