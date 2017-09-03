#!/usr/bin/env perl

# use progs::podcasts;
use progs::telerama;
use strict;
use warnings;
use out;
use chaines;
use Encode;
use v5.10;

my $net = out::have_net();
my $p = progs::telerama->new($net) || die "création prog\n";
# my $channel = "Cérémonie des Gamekult Awards 2013";
# my $channel = "Geek Inc HD Podcast 162 : 2014 ! le 6/01/2014, 23:05";
my $channel = "tf1";
my $sub = $p->get($channel) || die "die récupération prog $@\n";

my $n = 1;
my $show = 0;
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
	print dateheure($$sub[3])," à ",dateheure($$sub[4])," $$sub[2] desc:$$sub[6] détails:$$sub[7]\n";
	if ($$sub[9] && !$show) {
		$show = 1;
		my $c = chaines::request($$sub[9]);
		open(F,">image.jpg");
		print F $c;
		close(F);
		system("feh image.jpg");
		unlink("image.jpg");
	} elsif ($$sub[9]) {
		say "image $$sub[9]";
	}
}

