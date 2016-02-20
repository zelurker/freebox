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

# use progs::podcasts;
use progs::finter;
use strict;
use warnings;
use out;
use chaines;
use Encode;

my $browser = chaines::get_browser();
my $net = out::have_net();
my $p = progs::finter->new($net) || die "création prog\n";
# my $channel = "Cérémonie des Gamekult Awards 2013";
# my $channel = "Geek Inc HD Podcast 162 : 2014 ! le 6/01/2014, 23:05";
my $channel = "France inter";
my $sub = $p->get($channel) || die "die récupération prog finter: $@\n";

my $n = 1;
my $show = 0;
print "Les 2 programmes d'après :\n";
while ($n < 4 && $sub) {
	core($sub);
	$sub = $p->next($channel);
	$n++;
}
exit(0);
$sub = $p->get($channel) || die "die récupération prog finter: $@\n";
$n = 1;
print "Les 10 programmes d'après :\n";
while ($n < 10 && $sub) {
	core($sub);
	$sub = $p->next($channel);
	$n++;
}

sub dateheure {
	# Affiche une date à partir d'un champ time()
	$_ = shift;
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime($_);
	sprintf("%d/%d/%d %d:%02d",$mday,$mon+1,$year+1900,$hour,$min);
}

sub core {
	my $sub = shift;
	print dateheure($$sub[3])," à ",dateheure($$sub[4])," $$sub[2] desc:$$sub[6]\n";
	if ($$sub[9] && !$show) {
		$show = 1;
		my $c = chaines::request($$sub[9]);
		open(F,">image.jpg");
		print F $c;
		close(F);
		system("feh image.jpg");
		unlink("image.jpg");
	}
}

