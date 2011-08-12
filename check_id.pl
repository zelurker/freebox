#!/usr/bin/perl

use strict;
use Time::HiRes qw(usleep);

open(F,"<id") || die "no id file\n";
my $tries = 0;
while ($tries++ < 10000) {
	while (<F>) {
		chomp;
		if (/FAAD/) {
			die "horrible FAAD found, return immediately\n";
		} elsif (/ID_VIDEO_ASPECT=(.+)/) {
			if ($1 != 0) {
				print "ratio found $1\n";
				exit 0;
			}
		}
	}
	usleep(1000);
	seek F,0,1; # reset eof (1 = SEEK_CUR)
}
print "didn't find ratio after 10000 tries, assuming everything ok\n";
exit 0;




