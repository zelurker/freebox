#!/usr/bin/perl

# Teste les stations dans flux
# génère un nouveau fichier stations sur stdout à rediriger vers un autre
# fichier

use strict;
use v5.10;

open(F,"<flux/stations") || die "can't stations\n";
while (<F>) {
	chomp;
	if (/^encoding:/) {
		print;
		next;
	}
	my $name = $_;
	my $url = <F>;
	chomp $url;
	my $prog = undef;
	$prog = $1 if ($url =~ s/ (http.+)//);
	print STDERR "testing $name : $url ";
	# on utiliserait bien --network-timeout pour tester le timeout sauf que
	# ça marche très mal même sur un flux http !
	# du coup on en revient au bon vieux alarm... !
	my $g;
	my $pid;
	eval {
		local $SIG{ALRM} = sub { die "alarm"; };
		alarm(5);
		$pid = open($g,"mpv --network-timeout=5 '$url' 2> /dev/null|");
		if (!$pid) {
			die "pas de commande mpv ?!!!\n";
		}
		my $valid = 0;
		while (<$g>) {
			chomp;
			print STDERR "$_ " if (/Failed/);
			if (/ Audio /) {
				$valid = 1;
				last;
			}
		}
		close($g);
		$g = undef;
		if ($valid) {
			print "$name\n$url";
			print " $prog" if ($prog);
			print "\n";
			print STDERR "ok\n";
		} else {
			print STDERR "not ok\n";
		}
		alarm(0);
	};
	if ($g) {
		kill TERM => $pid;
		print STDERR "closing g... ";
		close($g);
	}
	if ($@) {
		print STDERR "not ok (timeout) \n";
	}
}
close(F);

