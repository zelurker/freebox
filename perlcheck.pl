#!/usr/bin/perl

use strict;
use v5.10;

my $r;
do {
	$r = system("perl -c $ARGV[0] 2> log");
	my $handled = 0;
	if ($r >> 8) {
		open(F,"<log") || die "can't open log";
		while(<F>) {
			if (/Can't locate (.+?) in/) {
				$handled = 1;
				say "must install $1";
				my $r2 = system("cpan -T $1");
				die "cpan call failed" if ($r2);
			}
		}
		close(F);
		if (!$handled) {
			system("cat log");
			die "can't handle this error ($ARGV[0])";
		}
	}
} while ($r);

