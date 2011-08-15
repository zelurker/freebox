#!/usr/bin/perl

if (open(F,"mplayer -frames 1 -vo null -ao null -identify stream.dump|")) {
	while (<F>) {
		if (/ID_LENGTH=(\d+)/) {
			my $len = $1;
			$len -= 0.5;
			$len = 0 if ($len < 0);
			print "$len\n";
			last;
		}
	}
	close(F);
} else {
	print "0\n";
}


