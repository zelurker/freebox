#!/usr/bin/perl

use strict;

# estime la position de fin de fichier pour reprise de lecture
# + facile à faire en perl qu'en shell

my $name=`head -n 7 current|tail -n 1`;
chomp $name;
if (open(F,"mplayer -frames 1 -vo null -ao null -identify '$name'|")) {
	while (<F>) {
		if (/ID_LENGTH=(\d+)/) {
			my $len = $1;
			$len -= 0.9;
			$len = 0 if ($len < 0);
			print "$len\n";
			last;
		}
	}
	close(F);
} else {
	print "0\n";
}


