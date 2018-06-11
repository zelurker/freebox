#!/usr/bin/perl

use strict;
use WWW::Mechanize;
use HTML::Entities;
use Ogg::Vorbis::Header;
use MP3::Tag;
use utf8;
use v5.10;
use search;

our $latin = ($ENV{LANG} !~ /UTF/i);

sub handle_lyrics {
	my ($mech,$u,$title) = @_;
	eval {
		$mech->get($u);
	};
	if ($@) {
		print "handle_lyrics: got error $!: $@\n";
		return undef;
	}

	$mech->save_content("page.html");
	# La gestion de l'utf par perl est HORRIBLE !
	# la solution est probablement de forcer un encodage pour contourner
	# ses détections d'encodage qui foirent tout le temps...
	# Au lieu de ça pour l'instant je vais tenter de juste demander de
	# retourner l'encodage du site web. Autrement ce crétin retourne un
	# texte latin1 venant d'un site utf8 même si la locale est utf ! Un
	# foirage de détection d'encodage assez monumental sur ce coup là !
	# Apparemment en utilisant ça les fichiers sont bien écrits en utf et
	# relus correctement.
	# Par contre si on le laisse faire sa conversion foireuse en latin1
	# bmovl appelle la fonction pour afficher du texte utf et ça foire !

	$_ = $mech->content(decoded_by_headers => 1);
	my $lyrics = "";
	my $start = undef;
	if ($u =~ /lyricsfreak.com/) {
		print "lyricsfreak.com\n";
		my $lyr = 0;
		foreach (split /\n/,$_) {
			s/\r//;
			if (/<!-- SONG LYRICS/) {
				$lyr = 1;
				next;
			}
			if ($lyr) {
				if (/<!-- \/SONG/) {
					$lyr = 0;
					last;
				}
				s/<div .+?>(.+)<\/div>/$1/;
				s/<br>/\n/g;
				$_ = decode_entities($_);
				$lyrics .= $_;
			}
		}
	} elsif ($u =~ /musique.ados.fr/) {
		my $lyr = 0;
		foreach (split /\n/,$_) {
			$lyr = 1 if (/<div class="contenu/);
			if ($lyr > 0 && $lyr < 2) {
				$lyr = 2 if (/<\/script/); # la pub collée !
				next;
			}
			if ($lyr == 2) {
				last if (/<\/div/);
				s/<br.+/\n/;
				$lyrics .= $_;
			}
		}
	} elsif ($u =~ /genius.com/) {
		my $lyr = 0;
		foreach (split /\n/,$_) {
			s/\r//;
			if (s/<div class="lyrics">//) {
				$lyr = 1;
			}
			if ($lyr) {
				last if (/<\/div>/);
				s/<br>/\n/g;
				# Filtrage des pubs en plein milieu de la chanson !!!
				$lyrics .= decode_entities($_);
			}
		}
	} elsif ($u =~ /paroles-musique.com/) {
		my $lyr = 0;
		foreach (split /\n/,$_) {
			s/\r//;
			if (s/<div id="lyrics">//) {
				$lyr = 1;
				next;
			}
			if ($lyr) {
				s/<br>/\n/g;
				$lyr = 0 if (s/<\/div>//); # collé à la dernière ligne !
				# Filtrage des pubs en plein milieu de la chanson !!!
				$lyrics .= decode_entities($_);
			}
		}
	} elsif ($u =~ /parolesmania.com/) {
		foreach (split /\n/,$_) {
			if (/<strong>Paroles/) {
				$start = 1;
				next;
			}
			if ($start) {
				s/\r//g;
				s/^[ \t]+//;
				s/<div.*>//;
				s/<br( \/)?>/\n/gs;
				s/[ \t]+$//s;
				$start = 0 if (s/<\/div.*>//);
				$lyrics .= decode_entities($_);
			}
		}
		$lyrics = "" if ($lyrics =~ /Les paroles de la chanson/);
		print "lyrics parolesmania.com : $lyrics\n";
	} elsif ($u =~ /flashlyrics.com/) {
		foreach (split /\n/,$_) {
			if (/<div.+padding\-horiz/) {
				$start = 1;
				next;
			}
			if ($start) {
				if (/<div/) {
					$start = 0;
					next;
				}
				s/\r//g;
				s/^[ \t]+//;
				s/<\/?(br|p)( \/)?>/\n/gs;
				s/[ \t]+$//s;
				$lyrics .= decode_entities($_);
			}
		}
		print "lyrics flashlyrics.com : $lyrics\n";
	} elsif ($u =~ /musixmatch.com/) {
		foreach (split /\n/,$_) {
			if (s/^.+p class=".+?lyrics.+?content ?">//) {
				$start = 1;
			}
			if ($start) {
				s/\r//g;
				s/^[ \t]+//;
				s/[ \t]+$//s;
				$start = 0 if (s/<\/p.+//);
				$lyrics .= decode_entities($_)."\n";
			}
		}
		print "lyrics musixmatch.com : $lyrics\n";
    } elsif ($u =~ /lyricsmania.com/) {
		foreach (split /\n/,$_) {
			if (/div class="fb-quotable"/) {
				$start = 1;
			} elsif ($start) {
				s/\r//g;
				s/^[ \t]+//;
				s/[ \t]+$//s;
				$start = 0 if (s/<\/div.+//);
                s/<br.*?>/\n/g;
                s/<.+?>//g;
				$lyrics .= decode_entities($_);
			}
		}
		print "lyrics lyricsmania.com : $lyrics\n";
	} elsif ($u =~ /greatsong.net/) {
		my $start = undef;
		foreach (split /\n/,$_) {
			next if (/^ *$/);
			s/^ +//;
			if (/<div class="share-lyrics/) {
				$start = 1;
			} elsif ($start) {
				last if (/<\/div>/);
				s/<br( \/)?>/\n/g;
				$lyrics .= decode_entities($_);
			}
		}
		say "lyrics greatsong.net $lyrics";
	} elsif ($u =~ /lyrics.wikia.com/) {
		foreach (split /\n/,$_) {
			if (s/<div class=.lyricbox.>//) {
				# Vraiment très particulier : tout en 1 seule ligne, et
				# encodé en ascii !
				s/<!.+//; # se termine par un commentaire
				s/&#(\d+);/chr($1)/eg;
				s/<\/?(br|p)( \/)?>/\n/gs;
				s/\r//sg;
				$lyrics .= decode_entities($_)."\n";
			}
		}
		if ($lyrics =~ /\xe9/ && !$latin) {
			say "y a du latin1...";
			eval {
				Encode::from_to($lyrics, "iso-8859-15","utf-8");
			};
			if ($@) {
				say "décodage utf8: $!: $@";
			}
		}
		print "lyrics lyrics.wikia.com : $lyrics\n";
	}
	$lyrics =~ s/<.+?>//g; # filtrage tags...
	if ($lyrics =~ /paroles ne sont plus dispo/i) {
		# paroles-musique.net renvoie ça de temps en temps !
		return undef;
	}
	my ($site) = $u =~ /https?:\/\/(.+?)\//;
	$site =~ s/^www\.//;
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime();
	$mon++;
	$year += 1900;
	$lyrics =~ s/^ +//;
	if ($lyrics eq "") {
		say "lyrics rejected - empty";
		return undef;
	}
	$lyrics .= "\nParoles provenant de $site, le $mday/$mon/$year";
	if ($site =~ /webcache/) {
		$lyrics =~ s/<b.+?>//g; # les marques de google cache
		$lyrics =~ s/<\/b>//g;
		# pour le cache google ajoute le site original
		$u =~ s/https?:\/\/(.+?)\///;
		($site) = $u =~ /https?:\/\/(.+?)\//;
		$site =~ s/^www\.//;
		$lyrics .= " (de $site)";
	}

	# ça c'est un mystère : pourquoi cette apostrophe n'apparait pas ?
	# Normalement c'est bien de l'utf8, et pourtant pas moyen de l'afficher
	# avec la fonction utf de freetype...
	$lyrics =~ s/\xe2\x80\x99/'/g;
	$lyrics;
}

sub pure_ascii {
	# Vire les accents et la ponctuation
	$_ = shift;
	$_ = lc($_);
	s/[()]//g;
	s/([àâ]|\xc3\xa0)/a/g;
	s/([éèêë]|\xc3\xa9)/e/g;
	s/ô/o/g;
	s/[ùû]/u/g;
	s/(ç|\xc3\xa7)/c/g;
	s/[!,?;\-]/ /g;
	s/ +/ /g;
	s/^ +//;
	s/ +$//;
	# Et pendant qu'on y est, on va virer les ponctuations...
	s/[\.,\?\;]//g;
	$_;
}

my $file = shift @ARGV || die "file ?\n";
my ($artist,$title);
my $lyrics = "";
my $ogg = $file =~ /ogg$/i;
my $mp3 = $file =~ /mp3$/i;
if ($ogg) {
	$ogg = Ogg::Vorbis::Header->new($file);
	($artist) = $ogg->comment("ARTIST");
   	($artist) = $ogg->comment("artist") if (!$artist);
	($title) = $ogg->comment("TITLE");
    ($title) = $ogg->comment("title") if (!$title);
}
if ($mp3) {
	$mp3 = MP3::Tag->new($file);

	# get some information about the file in the easiest way
	my ($track,$album,$comment,$year,$genre);
	($title, $track, $artist, $album, $comment, $year, $genre) = $mp3->autoinfo();
	if (!$comment) {
		$comment = $mp3->comment();
		print "compment fixed\n" if ($comment);
	}
	# On essaye de suivre le standard mp3 pour stocker les paroles mais vu
	# que je fais ça sans aucun fichier d'exemple je ne suis pas certain
	# d'être ok. Bah en tous cas ça peut être lit/écrit par ce script !
	# $lyrics = $mp3->select_id3v2_frame_by_descr('COMM(fre,fra,eng,#0)[USLT]');
	print "mp3: title $title track $track artist $artist album $album comment $comment year $year genre $genre\n";
	if ($lyrics) {
		print "mp3 lyrics : $lyrics\n";
		exit(0);
	}
}

$title = pure_ascii($title);
$title =~ s/ en duo.+//; # à tout hasard... !
if ($title =~ /jeanine medicament blues/i) {
	$artist = "Jean-jacques Goldman";
}
debut:
say "lyrics: envoie requête : lyrics $artist $title";
my $mech = search::search("lyrics $artist $title");
if ($@) {
	print "lyrics: foirage sur le submit $!: $@\n";
	return undef;
}
$mech->save_content("search.html");
foreach ($mech->links) {
	my $u = $_->url;
	next if ($u =~ /genius.com/ && $title =~ /^(nuit|c'est pas d'l'amour|il part|serre moi|des votres|des vies|juste apres)$/i);
	if ($u =~ /(musique.ados.fr|paroles-musique.com|genius.com|lyricsfreak.com|parolesmania.com|musixmatch.com|flashlyrics.com|lyrics.wikia.com|lyricsmania.com|greatsong.net)/) {
		my $old = $_;
		my $text = pure_ascii($_->text);
		say "considering link $text artist $artist title $title";
		if ($text =~ /$title/ || $u =~ /lyricsfreak.com/ || $text =~ /^En cache/i) {
			# exception sur lyricsfreak : ces cons mélangent titre,
			# artiste et la mention lyrics dans le titre de la page
			# ce qui la rend très difficile à identifier !
			if ($text =~ /^En cache/i) {
				say "Traitement du cache...";
				$u =~ s/\%(..)/chr(hex($1))/ge;
			}
			say "calling handle_lyrics url $u";
			$lyrics = handle_lyrics($mech,$u);
			last if ($lyrics);
		} else {
			print "lyrics: rejet sur le titre, texte : $text, title $title, artist $artist.\n";
		}
		$_ = $old;
	}
	next if ($_->text =~ /youtube/i || $u =~ /youtube/);
}
if (!$lyrics && $artist eq "Fredericks Goldman Jones") {
	$artist = "Jean-jacques Goldman";
	goto debut;
}
say "got lyrics $lyrics" if ($lyrics);

