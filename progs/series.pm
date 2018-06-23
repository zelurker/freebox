package progs::series;

use strict;
use warnings;
use progs::telerama;
use HTML::Entities;
use v5.10;
use search;

@progs::series::ISA = ("progs::telerama");

our $debug = 0;

sub find_actor($) {
	my $mech = shift;
	$_ = $mech->content;
	my $first = 0;
	my ($actor,$img,$cast);
	my $div;
	foreach (split /\n/,$_) {
		if (/div class=".*card-person/) {
			$actor = 1;
			$div = 0;
			next;
		} elsif ($actor) {
			$div++ if (/<div/i);
			if (/<\/div/i) {
				$div--;
				if ($div < 0) {
					$actor = 0;
					next;
				}
			}
			if (/<img .*data-src="(http.+?)"/i) {
				$img = $1 if (!$img);
				if (/alt="(.+?)"/i) {
					$cast .= "/ " if ($cast);
					$cast .= decode_entities("$1 ");
				}
			} elsif (/(Rôle .+?)<\//) {
				$cast .= decode_entities("$1 ");
			}
		}
	}
	return ($cast, $img);
}

sub get {
	my ($p,$channel,$source,$base_flux) = @_;
	return undef if ($source !~ /Fichiers v/);

	$channel =~ s/\[.+\] ?//g;
	if ($channel !~ /^(.+)[ \.]s(\d+)e(\d+)/i) {
		print STDERR "series: format de nom incorrect $channel\n";
		return undef;
	}
	my ($titre,$saison,$episode) = ($1,$2,$3);
	$titre =~ s/[\. ]us$//i;
	$episode =~ s/^0//; # tronque le 0 éventuel de l'épisode, pour allocine
	$saison =~ s/^0//;
	my $sum = "";
	my $img = "";
	my $cast = "";
	my $sub;

	if (!-f "cache/$channel.info") {
		my $mech = search::search("allocine $titre saison $saison");
		if ($@) {
			$p->error("error google : $@ status ".$mech->res()->status_line);
			return;
		}
		# On récupère le lien du haut du résultat :
		my $dump = 0;
		my $actor = 0;
		my $u;
		$u = $mech->find_link( url_regex => qr/allocine.fr/);
		if (!$u) {
			say "series : pas trouvé de regex, on sauve";
			$mech->save_content("goog.html");
		}
		return undef if (!$u);
#		foreach ($mech->links) {
			$u = $u->url;
			# avec duckduckgo, plus la peine de traiter les liens, c'est du
			# lien direct !
#		}
		for (my $page=1; $page<=2; $page++) {
			print STDERR "url $u page $page\n" if ($debug);
			# passer ajax avant ?page pour une version text only
			# mais si on veut les images il faut la totale...
			eval {
				$mech->get($u."?page=$page");
			};
			if ($@) {
				print STDERR "mechanize error $@\n";
				return undef;
			}
			$_ = $mech->content;
			my $search = sprintf("s%02de%02d",$saison,$episode);
			my $syn = 0;
			foreach (split /\n/,$_) {
				if (/<img.*data-src="(http.+?)"/i) {
					$img = $1;
				} elsif (/$search/i) {
					s/\<.+?\>//g;
					$sub = decode_entities($_);
					$dump = 1;
					next;
				} elsif ($dump && /<div class="synopsis/i) {
					$syn = 1;
					next;
				} elsif ($syn) {
					if (/<\/div/i) {
						$syn = 0;
						last;
					} else {
						$sum .= decode_entities($_);
					}
				}
			} # foreach
			my $img2;
			($cast,$img2) = find_actor($mech);
			$img = $img2 if (!$img);
			last if ($sum ne "");
		}
		if (!$cast) {
			# La page est incroyablement encodée avec des span transformés en
			# liens par du css, du coup c'est impossible à gérer en utilisant
			# find_link / follow_link. A priori toutes les urls respectent
			# qu'il faut insérer /casting dedans pour obtenir le casting, donc
			# on va faire ça...
			say STDERR "series: pas de cast, il y a surement des problèmes !!!";
			my $s = $u;
			$s =~ s/\/saison/\/casting\/saison/;
			eval {
				$mech->get($s);
			};
			if ($@) {
				print STDERR "mechanize error geting casting page $@\n";
			} else {
				($cast,$img) = find_actor($mech);
			}
		}
		if (!open(F,">:encoding(utf8)","cache/$channel.info")) {
			print STDERR "séries : impossible de créer cache/$channel.info\n";
			return undef;
		}
		print F "$titre Saison $saison Episode $episode\n$sub\n";
		if ($img) {
			print F "img:$img\n";
		}
		print F "$sum\n\n";
		if ($cast) {
			print F "Casting :\n";
			print F $cast;
		}
		close(F);
	} else {
		open(F,"<:encoding(utf8)","cache/$channel.info");
		<F>; # title
		$sub = <F>;
		$sum = "";
		chomp $sub;
		while (<F>) {
			$sum .= decode_entities($_);
			if ($sum =~ /^img:/) {
				chomp $sum;
				$sum =~ /img:(.+)/;
				$img = $1;
				$sum = "";
			}
		}
		close(F);
	}
	my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
		$atime,$mtime,$ctime,$blksize,$blocks) = stat($channel);
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
	localtime($mtime);
	my $date = sprintf("%02d/%02d/%d",$mday,$mon+1,$year+1900);

	my @tab = (undef, # chan id
		"$source", "$titre Saison $saison Episode $episode",
		undef, # début
		undef, "", # fin
		$sub, # desc
		$sum, # details
		"",
		$img, # img
		0,0,
		$date);
	return \@tab;
}

1;
