#!/usr/bin/perl

# Récupération des liens mms ou autres à partir d'une page web

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
	my $suffixe = $1; # suffixe éventuel au nom
	my $img = "img$suffixe";
	my $artiste = "artiste$suffixe";
	my $titre = "titre$suffixe";
	my $album = "album$suffixe";
	print "filter: prog $prog suffixe $suffixe\n";
	my $response = $browser->get($prog);
	if (! $response->is_success) {
		print "filter: pas pu récupérer le prog en $prog\n";
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
						# ça passerait peut-être sans filtre, mais vaut mieux
						# filtrer quand même !
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
		# mfm minimum, peut-être d'autres...

		print "format xml reconnu\n";

		my %hash;
		while ($res =~ s/(.+?)[\n\r]//) {
			$_ = $1;
			if (/^<\?xml/ && /encoding=\'(.+?)\'/) {
				if ($1 eq "UTF-8") {
					print "réencodage latin9\n";
					Encode::from_to($res, "utf-8", "iso-8859-15");
				} else {
					print "encoding $1\n";
				}
			} elsif (/<morceau/) {
				%hash = ();
			} elsif (/<(.+?)><\!\[CDATA\[(.+?)\]/) {
				$hash{$1} = $2 if ($2 && $2 ne "]");
			} elsif (/<\/morceau/) {
				$fa = $hash{chanteur} if (!$fa);
				$ft = $hash{chanson} if (!$ft);
				print "morceau $fa $ft\n";
				push @tracks,
				($hash{pochette} ? "pic:$hash{pochette} " : "").
				"$hash{chanteur} : $hash{chanson}";
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

