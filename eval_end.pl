#!/usr/bin/perl

if (open(F,"<id")) {
	while (<F>) {
		if (/ID_LENGTH=(\d+)/) {
			my $len = $1;
			$len -= 0.75;
			$len = 0 if ($len < 0);
			print "$len\n";
			last;
		}
	}
	close(F);
} else {
	print "0\n";
}


