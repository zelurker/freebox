#!/usr/bin/perl

package lyrics;

use strict;
use Coro::LWP;
use WWW::Mechanize;
use HTML::Entities;
use MP3::Tag;
use utf8;
use v5.10;
use lib ".";
use search;
use myutf;
use Data::Dumper;

our $latin = ($ENV{LANG} !~ /UTF/i);

sub handle_lyrics {
	my ($mech,$u,$file) = @_;
	eval {
		$mech->get($u);
	};
	if ($@) {
		print "handle_lyrics: got error $!: $@\n";
		if ($u =~ /genius/) {
			return get_manual($file,$u);
		}
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
	my $lyr = 0;
	if ($u =~ /azlyrics/) {
		say "azlyrics url $u";
		foreach (split /\n/,$_) {
			s/\r//;
			if (s/Usage of azlyrics//i) {
				$lyr = 1;
			}
			if ($lyr) {
				s/\t+/    /;
				$_ = decode_entities($_);
				if (s/<\/div>//) {
					$lyr = 0;
				}
				$lyrics .= "$_\n";
				last if (!$lyr);
			}
		}
	} elsif ($u =~ /songlyrics.com/) {
		foreach (split /\n/,$_) {
			s/\r//;
			if (s/<p id="songLyrics.+?>//i) {
				$lyr = 1;
			}
			if ($lyr) {
				s/<br \/>/\n/;
				s/\t+/    /;
				$_ = decode_entities($_);
				if (s/<\/p>//) {
					$lyr = 0;
				}
				$lyrics .= $_;
				last if (!$lyr);
			}
		}
	} elsif ($u =~ /lyricsfreak.com/) {
		foreach (split /\n/,$_) {
			s/\r//;
			if (/class="lyrictxt/) {
				$lyr = 1;
				next;
			}
			if ($lyr) {
				if (s/<\/div>//) {
					$lyr = 0;
				}
				s/^ +//;
				s/<div .+?>(.+)<\/div>/$1/;
				s/<br>/\n/g;
				s/<br \/>/\n/g;
				$_ = decode_entities($_);
				$lyrics .= $_;
				last if (!$lyr);
			}
		}
	} elsif ($u =~ /musique.ados.fr/) {
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
		my $footer = undef;
		foreach (split /\n/,$_) {
			s/\r//;
			#			if (s/^.+?<div data-lyrics-container[^>]+class="Lyrics.+?">//i) {
			# Et recorrection du tag de départ genius (7/2025) : c dangereux, pas sûr que ça soit fiable dans la durée, on verra bien...
			# Le filtrage du h2 et pour virer un Idea Lyrics qui se place en tête des paroles parfois
			if (s/^.+class="?LyricsHeader__Title.+?>//) {
				s/<h2.+?<\/h2>//i;
				$lyr = 1;
			}
			if ($lyr) {
				# Si on a des infos sur la chanson, c'est sur plusieurs lignes
				# Si y en a pas, y a quand même un champ RichText mais qui se termine aussitôt et vaut mieux couper ici sinon
				# on récupère un tas de merde en fin de paroles qui changent même l'encodage !
				$footer = $1 if (s/div class="RichText.+?>(.+?<\/div>)//i);
				$footer = $1 if (!$footer && s/div class="RichText.+?>(.+)//i);
				$lyr = 0 if (s/<div class="(Lyrics__Footer|ShareButtons|ExpandableContent__Button).+//);
				s/<br\/?>/\n/g;
				s/<div class="Recommended.+?\/div>//; # les recommandations en + milieu !!!
				# Filtrage des pubs en plein milieu de la chanson !!!
				$lyrics .= decode_entities($_);
				last if (!$lyr && !$footer);
			} elsif ($footer) {
				if ($footer =~ s/<\/div.+//) {
					$footer =~ s/<p>//g;
					$footer =~ s/<\/(p|h3)>/\n\n/g;
					$footer = decode_entities($footer);
					$lyrics .= "\n\n$footer";
					last;
				} elsif (s/<\/div.+//) {
					$footer .= $_;
					$footer =~ s/<p>//g;
					$footer =~ s/<\/(p|h3)>/\n\n/g;
					$footer = decode_entities($footer);
					$lyrics .= "\n\n$footer";
					last;
				}
				$footer .= $_;
			}
		}
	} elsif ($u =~ /paroles-musique.com/) {
		foreach (split /\n/,$_) {
			s/\r//;
			if (s/<div id="lyrics">//) {
				$lyr = 1;
				next;
			}
			next if (/<div class="lf_info/);
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
		my $ins = 0;
		foreach (split /\n/,$_) {
			if (/<div class="main-panel-content/) {
				$start = 1;
				next;
			}
			if ($start) {
				if ($ins) {
					if (/<\/div>/) {
						$ins = 0;
					}
					next;
				}
				if (/Report lyrics/) {
					$start = 0;
					last;
				}
				if (/<ins/) {
					$ins = 1;
					next;
				}
				s/\r//g;
				s/^[ \t]+//;
				s/<\/?(br|p)( ?\/)?>/\n/gs;
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
	} elsif ($u =~ /musiclyrics.com/) {
		my $start = undef;
		foreach (split /\n/,$_) {
			next if (/^ *$/);
			s/^ +//;
			if (/<div class="artist-page-lyrics/) {
				$start = 1;
			} elsif ($start) {
				last if (/<p>Photo/ || /Lyrics/);
				s/<br( \/)?>/\n/g;
				s/<\/p>/\n/;
				s/<p>//;
				s/&#8217;/'/g;
				$lyrics .= decode_entities($_);
			}
		}
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
		say "lyrics rejected - empty ($u)";
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
	s/\(.+?(\)|$)//; # tombé sur un titre en id3v2 sans parenthèse fermante parce que tronqué !!!
	s/–/-/g; # un tiret en utf8 !
	s/(œ|\xc5\x93)/oe/g;
	s/([àâ]|\xc3\xa0)/a/g;
	s/(é|è|ê|ë|\xc3\xa9|\xc3\xaa|\xc3\xa8|\xc3\xab)/e/g; # c3 aa est censé être pareil que ê, et le source est utf8... !!!!
	s/(ï|\xc3\xaf)/i/g;
	s/(ô|\xc3\xb4)/o/g;
	s/(ù|û|\xc3\xb9|\xc3\xbb)/u/g; # le u
	s/(ü|\xc3\xbc)/u/g;
	s/(ç|\xc3\xa7)/c/g;
	s/[!,?;\-]/ /g;
	s/ +/ /g;
	s/^ +//;
	s/ +$//;
	# Et pendant qu'on y est, on va virer les ponctuations...
	s/[\.,\?\;]//g;
	$_;
}

sub get_manual {
	# Traitement manuel pour les url sans solution pour l'instant, où ça devient clairement + simple de copier à la main le texte d'un navigateur plutôt que de s'entêter à trouver
	# des contournements.
	# Donc ici on ouvre un éditeur sur les paroles et un navigateur sur l'url des paroles, et y a plus qu'à. Sites à problèmes :
	# musixmatch : obfuscation tarée des styles pour rendre l'extraction auto des paroles quasi impossible
	# paroles-musique.com: un bouton à cliquer au milieu qui dépend d'une grosse lib js externe
	# genius a une espèce de captcha automatique je brancherai ici en cas de 403.
	# Note : l'appel pour lancer gvim retourne aussitôt, et celui pour ouvrir l'url retourne aussi si y a déjà un navigateur d'ouvert, dans ce cas là on ne pourra pas récupérer
	# les paroles. Autrement si y a pas de navigateur ouvert, le fermer après avoir sauvé les paroles dans l'éditeur, elles seront récupérées comme ça.
	# Si y avait déjà un navigateur, bin il faudra relire la chanson pour pouvoir relire les paroles !
	my ($mech,$u) = @_;

	return undef if (! -f "/usr/bin/gvim");
	system("gvim \"$mech.lyrics\"");
	system("xdg-open \"$u\"");
	if (open(F,"<$mech.lyrics")) {
		@_ = <F>;
		close(F);
		my $lyrics = join("",@_);
		return $lyrics;
	}
}

sub get_lyrics {
	my ($file,$artist,$title) = @_;
	my $lyrics = "";
	if ($file !~ /\.(7z|rar|zip)$/ && open(F,"<","$file.lyrics")) {
		while (<F>) {
			$lyrics .= $_;
		}
		close(F);
	}
	if ($lyrics) {
		print "got lyrics from .lyrics\n";
		return $lyrics;
	}
	# Pendant un temps j'ai essayé de stocker les paroles dans des tags,
	# mais ça pose des problèmes, genre en cas de paroles foireuses il faut
	# aller éditer le tag pour corriger, il y a aussi le problème de
	# l'encodage, c'est nettement + simple par un fichier .lyrics.
	# Je continue quand même à accèder aux tags pour avoir au moins l'info
	# titre et artiste...
	my $mp3 = $file =~ /mp3$/i;
	if ($file =~ /^http/) {
		$mp3 = 0;
	}
	if ($mp3) {
		$mp3 = MP3::Tag->new($file);
		say "pas de mp3 pour $file" if (!$mp3);
	}
	if ($mp3) {

		# get some information about the file in the easiest way
		my $id3v1;
		$mp3->get_tags;
		if (exists $mp3->{ID3v1}) {
			$id3v1 = $mp3->{ID3v1};
		  my ($track,$album,$comment,$year,$genre);
		  $title = $id3v1->title;
          # read some information from the tag
		  $artist = $id3v1->artist;
		  say STDERR "title final id3v1: $title";
		  say "lyrics: using id3v1";
  	    } else {
			my ($track,$album,$comment,$year,$genre);
			($title, $track, $artist, $album, $comment, $year, $genre) = $mp3->autoinfo();
		}
		say "lyrics: artist: $artist, title: $title";
		eval {
			say "calling update_tags";
			$mp3->update_tags if ($title && !$id3v1);
		};
		if ($@) {
			say "eval while updating tags: $@";
		}
		if (exists $mp3->{ID3v2}) {
			say "id3v2 found";
			my $id3v2 = $mp3->{ID3v2};
			my $lyrics = $id3v2->get_frame("USLT"); # Unsynchronized lyric/text transcription
			if (!$lyrics) {
				# Je ne sais pas si on trouve beaucoup ce genre d'encodage, 1 seul fichier ici comme ça jusqu'ici :
				# au lieu d'avoir l'USLT dans une frame normale, il regroupe ça en + de plein d'autres infos dans une frame TXXX
				# donc il faut commencer par faire un get_frames dessus qui retourne une liste avec toutes les infos là-dedans
				# puis aller à la pêche au USLT dedans... ! Un vrai merdier ! Enfin on y arrive quand même, mais là ça devient tordu.
				# Je garde le code pour l'instant, mais pour le fichier que j'ai en exemple de ça, les paroles de genius.com sont mieux !
				my ($name,@info) = $id3v2->get_frames('TXXX');
				for my $info (@info) {
					if (ref $info) {
						if ($info->{Description} eq "USLT") {
							$lyrics = $info;
							last;
						}
					}
				}
			}

			if (ref($lyrics) eq "HASH") {
				say "lyrics: got lyrics from id3v2 tag USLT";
				my $lyrics = $lyrics->{Text};
				$lyrics =~ s/\r//g;
				$lyrics =~ s/\x{2019}/'/g;
				return $lyrics;
			}
		}
	}

	if ((!$title || !$artist) && $file =~ /.+\/(.+) ?\- ?(.+)\./) {
		# tâche de deviner l'artiste et le titre d'après le nom de fichier
		# si possible...
		$artist = $1;
		$title = $2;
		$artist =~ s/^the very best of //i;
		$artist =~ s/best of //i;
		our $last;
		if ($last ne $file) {
			$last = $file;
			if ($mp3) {
				# En fait MP3::Tag sait déduire l'artiste et le titre du nom de
				# fichier donc cette partie là n'est normalement jamais
				# executée, on va garder quand même au cas où mais bon... !
				say "title_set ?!!";
				$mp3->title_set($title);
				$mp3->artist_set($artist);
				$mp3->update_tags();
			}
		}
	}
	my $r;
	my $orig = $title;
	$title =~ s/ \(.+?\)//; # truc entre ()
	$title = pure_ascii($title);
	$title =~ s/ \[.+?\]//; # vire chaine entre [] après le titre éventuelle
	$title =~ s/ en duo.+//; # à tout hasard... !
	if ($title =~ /jeanine medicament blues/i) {
		$artist = "Jean-jacques Goldman";
	}
	say "title $title";
debut:
	say "lyrics: envoie requête : lyrics $artist $title";
	my $mech = search::search("lyrics $artist $title");
	if ($@) {
		print "lyrics: foirage sur le submit $!: $@\n";
		return undef;
	}

	my $u;
	foreach ($mech->links) {
		$u = $_->url;
		# Censure genius.com pour nuit : paroles sans accents, le pire
		# c'est qu'un autre site a exactement les mêmes ! Difficile à
		# détecter, le + simple c'est de l'écarter explicitement pour
		# l'instant
		if ($u =~ /genius.com/ && ($artist =~ /goldman/i ||
			$artist =~ / dion/i)) {
			next;
		}
		next if ($u =~ /songlyrics/ && $title =~ /je marche seul/i);
		# je marche seul sur songlyrics : les paroles sont bonnes mais à la fin il reprend le 1er refrain avant de reprendre le 2nd, ce n'est pas indiqué !

		# lyricsfreak.com retiré le 2/7/2005 : accents remplacés par ? sur la page html, erreurs d'orthographe, qualité pourrie !!!
		if ($u =~ /(musiclyrics.com|musique.ados.fr|genius.com|parolesmania.com|flashlyrics.com|lyrics.wikia.com|lyricsmania.com|greatsong.net)/ ||
			$u =~ /(songlyrics.com|azlyrics)/) {
			my $old = $_;
			my $text = pure_ascii($_->text);
			my $tit = $title;
			if ($text !~ /$tit/) {
				$tit =~ s/mr /mister /;
			}
			if ($text =~ /$tit/ || $u =~ /lyricsfreak.com/ || $text =~ /^En cache/i) {
				# exception sur lyricsfreak : ces cons mélangent titre,
				# artiste et la mention lyrics dans le titre de la page
				# ce qui la rend très difficile à identifier !
				if ($text =~ /^En cache/i) {
					say "Traitement du cache...";
					$u =~ s/\%(..)/chr(hex($1))/ge;
				}
				say "paroles à partir de $u";
				$lyrics = handle_lyrics($mech,$u,$file);
				last if ($lyrics);
			} else {
				print "lyrics: rejet sur le titre, texte : $text, title $title, artist $artist.\n";
			}
			$_ = $old;
		} else {
			say STDERR "lyrics: link not recognized : $u";
		}
		next if ($_->text =~ /youtube/i || $u =~ /youtube/);
	}
	if (!$lyrics) {
		foreach ($mech->links) {
			$u = $_->url;
			if ($u =~ /(paroles.net|lyricsondemand.com|lyricsmode.com|musixwatch.com|paroles-musique.com)/) {
				$lyrics = get_manual($file,$u);
				last if ($lyrics);
			}
		}
	}
	if (!$lyrics && $artist eq "Fredericks Goldman Jones") {
		$artist = "Jean-jacques Goldman";
		goto debut;
	}
	if (!$lyrics && $mp3) {
		# Note que ces paroles contenues dans des tags n'ont pas l'air d'avoir quoi que ce soit d'officiel, trouvé des fautes d'orthographe flagrantes dans un mp3 de Goldman (veiller tard)
		# qui sont corrigées par les paroles de genius...
		$lyrics = $mp3->select_id3v2_frame_by_descr("COMM(fre,fra,eng,#0)[USLT]");
		if ($lyrics) {
			$lyrics = decode_entities($lyrics);
			say "got old format id3v2 lyrics in COMM tag $lyrics (".length($lyrics).")";
			$lyrics .= "\nParoles extraites d'un tag COMM USLT";
		}
	}
	if (!$lyrics) {
		print "get_lyrics: url inconnue : $u pas de paroles ?\n";
		return undef;
	}

	# Pour corriger l'apostrophe à la con de krosoft !
	$lyrics =~ s/\x{2019}/'/g;
	$lyrics =~ s/\x{0153}/oe/g; # bizarre c'est sensé être supporté par perl5...

	if ($file !~ /^http/ && $file !~ /\.(7z|rar|zip)$/) {
		# Sans déconner, vu la complexité des tags mp3 je me demande si je
		# devrais pas plutôt stocker dans un fichier .lyrics pour tout le
		# monde ? Enfin bon...
		# nb : ça y est c'est fait, ça marchait en mp3 mais en cas d'erreur
		# quand les paroles sont mauvaises c'est super merdique à corriger
		# et quand le mp3 vient d'un torrent ça change le fichier, donc
		# finalement les .lyrics pour tout le monde, c'est bien !
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
	say "lyrics: returning $lyrics";
	return $lyrics;
}

1;

