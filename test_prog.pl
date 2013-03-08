#!/usr/bin/env perl 
#===============================================================================
#
#         FILE: test_prog.pl
#
#        USAGE: ./test_prog.pl  
#
#  DESCRIPTION: test module progs/telerama
#
#      OPTIONS: ---
# REQUIREMENTS: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Emmanuel Anne (), emmanuel.anne@gmail.com
# ORGANIZATION: 
#      VERSION: 1.0
#      CREATED: 07/03/2013 15:20:43
#     REVISION: ---
#===============================================================================

use progs::telerama;
use strict;
use warnings;
use out;
use chaines;

my $browser = chaines::get_browser();
my $net = out::have_net();
my $p = progs::telerama->new($net) || die "création prog\n";
my $sub = $p->get("France 2") || die "récupération prog france 2\n";

my $n = 1;
print "Les 45 programmes d'avant (france 2) :\n";
while ($n < 45 && $sub) {
	print dateheure($$sub[3])," à ",dateheure($$sub[4])," $$sub[2]\n";
	if ($$sub[9]) {
		my $c = chaines::request($$sub[9]);
		open(F,">image.jpg");
		print F $c;
		close(F);
		system("feh image.jpg");
		unlink("image.jpg");
		exit(0);
	}
	$sub = $p->prev("France 2");
	$n++;
}

sub dateheure {
	# Affiche une date à partir d'un champ time()
	my $_ = shift;
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime($_);
	sprintf("%d/%d/%d %d:%02d",$mday,$mon+1,$year+1900,$hour,$min);
}



