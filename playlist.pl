#!/usr/bin/perl

# R�cup�ration des liens mms ou autres � partir d'une page web

use LWP 5.64;
use strict;
use Encode;

our $browser = LWP::UserAgent->new(keep_alive => 0);
$browser->timeout(5);
$browser->default_header(
	[ 'Accept-Language' => "fr-fr"
	]
);

sub handle_prog($) {
	my ($prog,$info) = @_;
	$prog =~ s/ (.+)//;
	my $suffixe = $1; # suffixe �ventuel au nom
	my $img = "img$suffixe";
	my $artiste = "artiste$suffixe";
	my $titre = "titre$suffixe";
	my $album = "album$suffixe";
	print "filter: prog $prog suffixe $suffixe\n";
	my $response = $browser->get($prog);
	if (! $response->is_success) {
		print "filter: pas pu r�cup�rer le prog en $prog\n";
		return;
	}
	my $res = $response->content;
	my @tracks;
	my ($fa,$ft);
	if ($res =~ s/^\{//) { # format oui fm
		foreach (split /\],/,$res) {
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
						# �a passerait peut-�tre sans filtre, mais vaut mieux
						# filtrer quand m�me !
						$val =~ s/\\\//\//g;
					}
					$val =~ s/"$//;
					$hash{$key} = $val;
				}
				push @tracks,($hash{$img} ? "pic:$hash{$img} " : "")."$hash{$artiste} : $hash{$titre} ($hash{$album})";
				$ft = $hash{$titre} if (!$ft);
				$fa = $hash{$artiste} if (!$fa);
			}
			last;
		}

	} elsif ($res =~ /^<\?xml/) {
		# mfm minimum, peut-�tre d'autres...

		my %hash;
		while ($res =~ s/(.+?)[\n\r]//) {
			$_ = $1;
			if (/^<\?xml/ && /encoding=\'(.+?)\'/) {
				if ($1 eq "UTF-8") {
					print "r�encodage latin9\n";
					Encode::from_to($res, "utf-8", "iso-8859-15");
				}
			} elsif (/<morceau/) {
				%hash = ();
			} elsif (/<(.+?)><\!\[CDATA\[(.+?)\]/) {
				$hash{$1} = $2 if ($2 && $2 ne "]");
			} elsif (/<\/morceau/) {
				$fa = $hash{chanteur} if (!$fa);
				$ft = $hash{chanson} if (!$ft);
				push @tracks,
				($hash{pochette} ? "pic:$hash{pochette} " : "").
				"$hash{chanteur} : $hash{chanson}";
			}
		}

	} elsif ($res =~ /^updateData/) {
		# le format rtl2, de loin le + merdique carr�ment du code js !
		# Super top : l'encodage utf � la con sur plusieurs caract�res
		# voir la page http://www.eteks.com/tips/tip3.html pour le d�tail du
		# codage. Pas trouv� de m�thode automatique pour d�gager �a...
		my %codage = (
			'\u00e0' => '�',
			'\u00e2' => '�',
			'\u00e4' => '�',
			'\u00e7' => '�',
			'\u00e8' => '�',
			'\u00e9' => '�',
			'\u00ea' => '�',
			'\u00eb' => '�',
			'\u00ee' => '�',
			'\u00ef' => '�',
			'\u00f4' => '�',
			'\u00f6' => '�',
			'\u00f9' => '�',
			'\u00fb' => '�',
			'\u00fc' => '�',
		);
		foreach (keys %codage) {
			# Ce cr�tin ne remplace pas le \ dans la source avec la 1�re regexp
			$res =~ s/$_/$codage{$_}/gi;
			# donc on est oblig� de faire un 2�me tour !
			$res =~ s/\\$codage{$_}/$codage{$_}/g;
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
				"$hash{artist} : $hash{title}".
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
		return "$fa : $ft"; # Renvoie la chaine pour google images
	}
	return 0;
}

1;
