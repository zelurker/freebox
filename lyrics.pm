#!/usr/bin/perl

package lyrics;

use strict;
use Coro::LWP;
use WWW::Mechanize;
use HTML::Entities;
use Ogg::Vorbis::Header;
use MP3::Tag;
use utf8;
use v5.10;

sub handle_lyrics {
	my ($mech,$u) = @_;
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
				s/<.+?>//g; # filtrage tags...
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
				s/<.+?>//g; # filtrage tags...
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
			if (s/^.+p class=".+?lyrics.+?content".+?>//) {
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
		print "lyrics lyrics.wikia.com : $lyrics\n";
	}
	my ($site) = $u =~ /https?:\/\/(.+?)\//;
	$site =~ s/^www\.//;
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime();
	$mon++;
	$year += 1900;
	$lyrics .= "\nParoles provenant de $site, le $mday/$mon/$year";

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

sub get_lyrics {
	my ($file,$artist,$title) = @_;
	my $lyrics = "";
	my $ogg = $file =~ /ogg$/i;
	my $mp3 = $file =~ /mp3$/i;
	if ($file =~ /^http/) {
		$mp3 = $ogg = 0;
	}
	if ($ogg) {
		$ogg = Ogg::Vorbis::Header->new($file);
		($artist) = $ogg->comment("ARTIST");
		($artist) = $ogg->comment("artist") if (!$artist);
		($title) = $ogg->comment("TITLE");
		($title) = $ogg->comment("title") if (!$title);
		# Normalement on devrait pouvoir stocker les paroles dans un tag
		# vorbis, sauf qu'ils sont supers intolérants, on a le droit qu'à
		# de l'ascii standard. Pour les retours charriots ça va encore,
		# mais pour les accents c'est un merdier sans nom (possibilité de
		# le faire à partir des définitions des accents html en recopiant à
		# partir de la table, mais c'est trop chiant), donc on laisse
		# tomber les tags vorbis pour les paroles, .lyrics uniquement !
		print "ogg artist $artist title $title\n";
	}
	if ($mp3) {
		$mp3 = MP3::Tag->new($file);

		# get some information about the file in the easiest way
		my ($track,$album,$comment,$year,$genre);
		($title, $track, $artist, $album, $comment, $year, $genre) = $mp3->autoinfo();
		if (!$comment) {
			$comment = $mp3->comment();
			print "comment fixed\n" if ($comment);
		}
		# On essaye de suivre le standard mp3 pour stocker les paroles mais vu
		# que je fais ça sans aucun fichier d'exemple je ne suis pas certain
		# d'être ok. Bah en tous cas ça peut être lit/écrit par ce script !
		$lyrics = $mp3->select_id3v2_frame_by_descr('COMM(fre,fra,eng,#0)[USLT]');
		print "mp3: title $title track $track artist $artist album $album comment $comment year $year genre $genre\n";
		if ($lyrics) {
			return $lyrics;
		}
	}
	if (!$lyrics && open(F,"<","$file.lyrics")) {
		while (<F>) {
			$lyrics .= $_;
		}
		close(F);
	}
	if ($lyrics) {
		print "got lyrics from .lyrics\n";
		return $lyrics;
	}

	my $mech = WWW::Mechanize->new();
	$mech->agent_alias("Linux Mozilla");
	# $mech->agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_5) AppleWebKit/537.71 (KHTML, like Gecko) Version/6.1 Safari/537.71");
	$mech->timeout(10);
	# $mech->default_header('Accept-Encoding' => scalar HTTP::Message::decodable());
	eval {
		$mech->get("https://www.google.fr/");
	};
	if ($@) {
		print "lyrics: got error $!: $@\n";
		return undef;
	}
	my $r;
	my $orig = $title;
	$title = pure_ascii($title);
	say "lyrics: envoie requête : lyrics $artist - $title";
	eval {
		$r = $mech->submit_form(
			form_number => 1,
			fields      => {
				q => "lyrics $artist - $title",
			}
		);
	};
	if ($@) {
		print "lyrics: foirage sur le submit $!: $@\n";
		return undef;
	}

	my $u;
	foreach ($mech->links) {
		$u = $_->url;
		if ($u =~ /url.q=(http.+?)&/) {
			$u = $1;
			print $_->text,"\n$u\n";
			if ($u =~ /(musique.ados.fr|paroles-musique.com|genius.com|lyricsfreak.com|parolesmania.com|musixmatch.com|flashlyrics.com|lyrics.wikia.com|lyricsmania.com)/) {
				my $old = $_;
				my $text = pure_ascii($_->text);
				if ($text =~ /$title/ || $u =~ /lyricsfreak.com/ || $text =~ /^En cache/i) {
					# exception sur lyricsfreak : ces cons mélangent titre,
					# artiste et la mention lyrics dans le titre de la page
					# ce qui la rend très difficile à identifier !
					if ($text =~ /^En cache/i) {
						say "Traitement du cache...";
						$u =~ s/\%(..)/chr(hex($1))/ge;
					}
					$lyrics = handle_lyrics($mech,$u);
					last if ($lyrics);
				} else {
					print "lyrics: rejet sur le titre, texte : $text, title $title, artist $artist.\n";
				}
				$_ = $old;
			}
			next if ($_->text =~ /youtube/i || $u =~ /youtube/);
		}
	}
	if (!$lyrics) {
		print "get_lyrics: url inconnue : $u pas de paroles ?\n";
		return undef;
	}

	# Pour corriger l'apostrophe à la con de krosoft !
	$lyrics =~ s/\x{2019}/'/g;
	$lyrics =~ s/\x{0153}/oe/g; # bizarre c'est sensé être supporté par perl5...

	if ($mp3) {
		my $lang;
		# Les paroles dans le mp3 c'est pourquoi faire simple quand on peut
		# faire compliqué ! En gros y a un commité de standardisation qui s'est
		# penché là-dessus et ça se voit !
		if ($lyrics =~ /[éèêàù]/) {
			# Déjà le langage, idiot comme info, on est obligé de deviner
			# ici...
			$lang = "fre";
		} else {
			$lang = "eng";
		}
		# Ensuite ils veulent de la normalization !
		eval 'require Normalize::Text::Music_Fields';
		for my $elt ( qw( title track artist album comment year genre
			title_track artist_collection person ) ) {
			no strict 'refs';
			MP3::Tag->config("translate_$elt", \&{"Normalize::Text::Music_Fields::normalize_$elt"})
			if defined &{"Normalize::Text::Music_Fields::normalize_$elt"};
		}
		MP3::Tag->config("short_person", \&Normalize::Text::Music_Fields::short_person)
		if defined &Normalize::Text::Music_Fields::short_person;
		# Enfin c'est mieux de lui dire d'autoriser l'écriture du v24 même si
		# normalement c'est du 2.3 apparemment ! Note les caractères utf8 ne
		# sont pas lus correctement par la commande id3v2 mais bon elle a des
		# lacunes il parait... !
		$mp3->config(write_v24 => 1);
		$mp3->select_id3v2_frame_by_descr("COMM($lang)[USLT]", $lyrics);
		$mp3->update_tags();
	} elsif ($file !~ /^http/) {
		# Sans déconner, vu la complexité des tags mp3 je me demande si je
		# devrais pas plutôt stocker dans un fichier .lyrics pour tout le
		# monde ? Enfin bon...
		if (open(F,">","$file.lyrics")) {
			print F "$lyrics";
			close(F);
			print "lyrics file created\n";
			# Exception pour paroles.net : le décodage interne habituel
			# foire pour celui là, si on le laisse retourner les $lyrics
			# normales on obtient un warning wide character sur Coro au
			# moment de les transmettre et ça interrompt mplayer2. Donc
			# contournement : on relit ce qu'on vient juste d'écrire ! De
			# cette façon le wide character disparait, il y a probablement
			# une fonction très obscure et qui marche une fois tous les 36
			# du mois qui sait faire ça aussi, mais là de cette façon on
			# est sûr que ça marchera tout le temps... enfin on espère !!!
			$lyrics = "";
			open(F,"<$file.lyrics");
			while (<F>) {
				$lyrics .= $_;
			}
			close(F);
		}
	}
	return $lyrics;
}

1;

