#!/usr/bin/perl

use strict;
use v5.10;

my $r;
do {
	$r = system("perl -c $ARGV[0] 2> /tmp/logpcheck");
	my $handled = 0;
	if ($r >> 8) {
		open(F,"</tmp/logpcheck") || die "can't open /tmp/logpcheck";
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
			system("cat /tmp/logpcheck");
			die "can't handle this error ($ARGV[0])";
		}
	}
} while ($r);
unlink "/tmp/logpcheck";

