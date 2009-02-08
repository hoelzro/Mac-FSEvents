#!/usr/bin/perl

use strict;

use FindBin;
use File::Path;
use File::Temp;
use IO::Select;
use Mac::FSEvents;

use Test::More tests => 3;

my $tmpdir = "$FindBin::Bin/tmp";

# clean up
rmtree $tmpdir if -d $tmpdir;

# create tmpdir
mkdir $tmpdir;

my $since;

# Test a simple event
{	
	my $fs = Mac::FSEvents->new( {
		path    => $tmpdir,
		latency => 0.5,
	} );
	
	$fs->watch;
	
	my $tmp = File::Temp->new( DIR => $tmpdir );
	
	eval {
		local $SIG{ALRM} = sub { die "alarm\n" };
		alarm 3;
	
		READ:
		while ( my @events = $fs->read_events ) {
			for my $event ( @events ) {
				my $path = $event->path;
				$since   = $event->id;
				if ( $tmp->filename =~ /^$path/ ) {
					ok( 1, 'event received (poll interface)' );
					last READ;
				}
			}
		}
		
		alarm 0;
	};
	
	if ( $@ ) {
		die $@ unless $@ eq "alarm\n";
		ok( 0, 'event received (poll interface)' );
	}
	
	$fs->stop;
}

# Test select interface
{
	my $fs = Mac::FSEvents->new( {
		path    => $tmpdir,
		latency => 0.5,
	} );
	
	my $fh = $fs->watch;
	
	my $tmp = File::Temp->new( DIR => $tmpdir );
	
	eval {
		local $SIG{ALRM} = sub { die "alarm\n" };
		alarm 3;
		
		my $sel = IO::Select->new($fh);
	
		READ:
		while ( $sel->can_read ) {
			for my $event ( $fs->read_events ) {
				my $path = $event->path;
				if ( $tmp->filename =~ /^$path/ ) {
					ok( 1, 'event received (select interface)' );
					last READ;
				}
			}
		}
		
		alarm 0;
	};
	
	if ( $@ ) {
		die $@ unless $@ eq "alarm\n";
		ok( 0, 'event received (select interface)' );
	}
	
	$fs->stop;
}

# Test since param and that we receive a history_done flag
{
	my $fs = Mac::FSEvents->new( {
		path    => $tmpdir,
		since   => $since,
		latency => 0.5,
	} );
	
	$fs->watch;
	
	eval {
		local $SIG{ALRM} = sub { die "alarm\n" };
		alarm 3;
	
		READ:
		while ( my @events = $fs->read_events ) {
			for my $event ( @events ) {
				if ( $event->history_done ) {
					ok( 1, 'history event received' );
					last READ;
				}
			}
		}
		
		alarm 0;
	};
	
	if ( $@ ) {
		die $@ unless $@ eq "alarm\n";
		ok( 0, 'history event received' );
	}
	
	$fs->stop;
}

# clean up
rmtree $tmpdir if -d $tmpdir;