#!/usr/bin/perl

# Gère les programmes de certaines stations de radio web (lien http)

use LWP 5.64;
use strict;
use Encode;

our $browser = LWP::UserAgent->new(keep_alive => 0);
$browser->timeout(5);
$browser->default_header(
	[ 'Accept-Language' => "fr-fr"
	]
);

our %codage = (
	'\u00e0' => 'à',
	'\u00e2' => 'â',
	'\u00e4' => 'ä',
	'\u00e7' => 'ç',
	'\u00e8' => 'è',
	'\u00e9' => 'é',
	'\u00ea' => 'ê',
	'\u00eb' => 'ë',
	'\u00ee' => 'î',
	'\u00ef' => 'ï',
	'\u00f4' => 'ô',
	'\u00f6' => 'ö',
	'\u00f9' => 'ù',
	'\u00fb' => 'û',
	'\u00fc' => 'ü',
);

sub handle_prog {
	my ($prog,$info) = @_;
	$prog =~ s/ (.+)//;
	my $suffixe = $1; # suffixe éventuel au nom
	my $img = "img$suffixe";
	my $artiste = "artiste$suffixe";
	my $titre = "titre$suffixe";
	my $album = "album$suffixe";
	print "filter: prog $prog suffixe $suffixe\n";
	my ($site) = $prog =~ /^(http:\/\/.+?\/)/;
	my $response = $browser->get($prog);
	if (! $response->is_success) {
		print "filter: pas pu récupérer le prog en $prog\n";
		return;
	}
	my $res = $response->content;
	my @tracks;
	my ($fa,$ft);
	if ($prog =~ /euradionantes.eu/) {
		# Top naze, y a juste un script php pour accèder au programme, pas
		# de balises dans le mp3, pas d'xml en vue... !!!
		($fa,$ft) = $res =~ /<b>(.+)<\/b> \- (.+)<\/span/m;
		$fa =~ s/ +$//;
		$ft =~ s/ +$//;
		@tracks = ("$fa - $ft");
	} elsif ($res =~ s/^\{//) { # format oui fm
		my $t = time();
		my @list = split(/\],/,$res);
		foreach (@list) {
			my %hash = ();

			next if (!(/^"last$suffixe":\[(.+)/));
			my $c = $1;
			$c =~ s/^{//;
			$c =~ s/}$//;
			my @tab = split /\},\{/,$c;
			foreach (@tab) {
				my %hash = ();
				my @tab2 = split /","/;
				foreach (@tab2) {
					s/ +$//g;
					s/" */"/g;
					/^"?(.+?)"\:"(.+) */;
					my $val = $2;
					my $key = $1;
					if ($key eq "$img") {
						# Pour je ne sais quelle raison ils backslashent les slashes
						# ça passerait peut-être sans filtre, mais vaut mieux
						# filtrer quand même !
						$val =~ s/\\\//\//g;
					}
					$val =~ s/"$//;
					$hash{$key} = $val;
				}
				push @tracks,($hash{$img} ? "pic:$hash{$img} " : "")."$hash{$artiste} - $hash{$titre} ($hash{$album})";
				$ft = $hash{$titre} if (!$ft);
				$fa = $hash{$artiste} if (!$fa);
			}
			last;
		}

	} elsif ($res =~ /^<\?xml/) {
		# mfm minimum, peut-être d'autres...
		print "xml reconnu\n";

		my %hash;
		while ($res =~ s/(.+?)[\n\r]//) {
			$_ = $1;
			if (/^<\?xml/ && /encoding=[\'"](.+?)[\'"]/) {
				if ($1 =~ /UTF-8/i) {
					print "réencodage latin9\n";
					Encode::from_to($res, "utf-8", "iso-8859-15");
				}
			} elsif (/<(morceau|item)/) {
				%hash = ();
			} elsif (/<(.+?)><\!\[CDATA\[(.+?)\]/) {
				$hash{$1} = $2 if ($2 && $2 ne "]");
			} elsif (/<(.+?)>(.+?)<\/(.+?)>/ && $1 eq $3) {
				$hash{$1} = $2 if ($2 && $2 ne "]");
			} elsif (/<\/(morceau|item)/) {
				my $chanteur = $hash{chanteur} || $hash{artist};
				my $chanson = $hash{chanson} || $hash{title};
				my $pochette = $hash{pochette} || $hash{img_png};
				$fa = $chanteur if (!$fa);
				$ft = $chanson if (!$ft);
				push @tracks,
				($pochette ? "pic:$pochette " : "").
				"$chanteur - $chanson";
			}
		}

	} elsif ($res =~ /^updateData/) {
		# le format rtl2, de loin le + merdique carrément du code js !
		# Super top : l'encodage utf à la con sur plusieurs caractères
		# voir la page http://www.eteks.com/tips/tip3.html pour le détail du
		# codage. Pas trouvé de méthode automatique pour dégager ça...
		foreach (keys %codage) {
			# Ce crétin ne remplace pas le \ dans la source avec la 1ère regexp
			$res =~ s/\\$_/$codage{$_}/gi;
		}
		if ($res =~ /"songs"\:\[(.+?)\]/) {
			foreach (split /\},\{/,$1) {
				my %hash = ();
				foreach (split /\"?\,\"/) {
					s/^"//;
					s/"$//;
					my ($k,$v) = split(/"\:"/);
					$hash{$k} = $v;
				}
				$fa = $hash{artist} if (!$fa);
				$ft = $hash{title} if (!$ft);
				push @tracks,
				($hash{cover} ? "pic:$hash{cover} " : "").
				"$hash{artist} - $hash{title}".
			   	($hash{album} ? " ($hash{album})" : "");
			}
		}
	} else {
		print "format inconnu $res\n";
	}
	if (@tracks) {
		if (open(F,">stream_info")) {
			print F "$info\n";
			foreach (reverse @tracks) {
				print F "$_\n";
			}
			close(F);
		}
		if ($ft && $fa) {
			return "$fa - $ft"; # Renvoie la chaine pour google images
		} elsif ($ft) {
			return $ft;
		} else {
			die "pas de titre à renvoyer dans ft\n";
		}
	}
	print "*** no tracks ***\n";
	return 0;
}

1;

