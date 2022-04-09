#!/usr/bin/env perl

# use progs::podcasts;
use lib ".";
use progs::finter;
use common::sense;

my $net = out::have_net();
my $p = progs::finter->new($net) || die "creation prog\n";
my $channel = "France inter";
my $sub = $p->get($channel) || die "die rcupration prog $@\n";
say "got sub $sub";

my $n = 1;
my $show = 0;
$n = 1;
print "Les 40 programmes d'après :\n";
while ($n < 40 && $sub) {
	core($sub);
	$sub = $p->next($channel);
	$n++;
}

sub dateheure {
	# Affiche une date  partir d'un champ time()
	$_ = shift;
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime($_);
	sprintf("%d/%d/%d %d:%02d",$mday,$mon+1,$year+1900,$hour,$min);
}

sub core {
	my $sub = shift;
	print dateheure($$sub[3]),"  ",dateheure($$sub[4])," $$sub[2] desc:$$sub[6] dtails:$$sub[7]\n";
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

