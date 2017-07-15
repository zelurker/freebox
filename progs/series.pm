package progs::series;

use strict;
use warnings;
use progs::telerama;
use WWW::Mechanize;
use HTML::Entities;

@progs::series::ISA = ("progs::telerama");

our $debug = 0;

sub find_actor($) {
	my $mech = shift;
	$_ = $mech->content;
	my $first = 0;
	my ($actor,$img,$cast);
	foreach (split /\n/,$_) {
		if (/itemprop="actor"/ || /div class=".*Actors/) {
			$actor = 1;
			next;
		} elsif ($actor) {
			if (/\/li/) {
				$actor = 0;
				next;
			}
			if (/img src='(http.+?)'/) {
				$img = $1 if (!$img);
			} elsif (/alt='(.+?)'/) {
				$cast .= "/ " if ($cast);
				$cast .= decode_entities("$1 ");
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
	$episode =~ s/^0//; # tronque le 0 éventuel de l'épisode, pour allocine
	$saison =~ s/^0//;
	my $sum = "";
	my $img = "";
	my $cast = "";
	my $sub;

	if (!-f "cache/$channel.info") {
		if (!open(F,">:encoding(utf8)","cache/$channel.info")) {
			print STDERR "séries : impossible de créer cache/$channel.info\n";
			return undef;
		}
		my $mech = WWW::Mechanize->new();
		$mech->agent_alias("Linux Mozilla");
		$mech->timeout(12);
		$mech->default_header('Accept-Encoding' => scalar HTTP::Message::decodable());
		$mech->get("https://www.google.fr/");
		my $r = $mech->submit_form(
			form_number => 1,
			fields      => {
				q => "allocine $titre saison $saison",
			}
		);
		# On récupère le lien du haut du résultat :
		my $dump = 0;
		my $actor = 0;
		my $u;
		$u = $mech->find_link( text_regex => qr/Episodes /);
		return undef if (!$u);
#		foreach ($mech->links) {
			$u = $u->url;
			if ($u =~ /url.q=(http.+?)&/) {
				$u = $1;
				# last;
			} else {
				print STDERR "series: pas trouvé lien Episodes\n";
				return undef;
			}
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
			my $first = 0;
			foreach (split /\n/,$_) {
				if (/Ep\. $episode /) {
					s/\<.+?\>//g;
					$sum .= decode_entities($_);
					$dump = 1;
					next;
				} elsif ($dump) {
					if (/\/td/) {
						$dump = 0;
						next;
					}
					s/\<.+?\>//g;
					if ($sum =~ /\w$/) {
						if (!$first) {
							$first = 1;
							$sub = $sum;
							print STDERR "sub $sub\n";
							$sum = "";
						} else {
							$sum .= "\n";
						}
					}
					$sum .= decode_entities($_);
				}
			} # foreach
			($cast,$img) = find_actor($mech);
			last if ($sum ne "");
		}
		if (!$cast) {
			# La page est incroyablement encodée avec des span transformés en
			# liens par du css, du coup c'est impossible à gérer en utilisant
			# find_link / follow_link. A priori toutes les urls respectent
			# qu'il faut insérer /casting dedans pour obtenir le casting, donc
			# on va faire ça...
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
