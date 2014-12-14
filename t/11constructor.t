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
    eval {
        my $ev = Mac::FSEvents->new({
            path => 'tmp',
        });
    };
    ok $@, 'path must be absolute';
    like $@, qr{\Qpath argument to new() must be absolute};
}

