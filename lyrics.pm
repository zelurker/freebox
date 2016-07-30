#!/usr/bin/perl

package lyrics;

use strict;
use WWW::Mechanize;
use HTML::Entities;
use Ogg::Vorbis::Header;
use MP3::Tag;
use utf8;

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
		($artist) = $ogg->comment("ARTIST") || $ogg->comment("artist");
		($title) = $ogg->comment("TITLE") || $ogg->comment("title");
		my (@lyrics) = $ogg->comment("LYRICS") || $ogg->comment("lyrics");
		$lyrics = join("\n",@lyrics);
		print "ogg artist $artist title $title\n";
		# Si c'est du vieux ogg, on aura peut-être créé un fichier lyrics
		if (!$lyrics && open(F,"<$file.lyrics")) {
			while (<F>) {
				$lyrics .= $_;
			}
			close(F);
		}
		if ($lyrics) {
			$lyrics =~ s/<br>/\n/g;
			return $lyrics;
		}
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

	my $mech = WWW::Mechanize->new();
	$mech->agent_alias("Linux Mozilla");
	$mech->timeout(10);
	$mech->default_header('Accept-Encoding' => scalar HTTP::Message::decodable());
	$mech->get("https://www.google.fr/");
	my $r = $mech->submit_form(
		form_number => 1,
		fields      => {
			q => "lyrics $artist - $title",
		}
	);
	my $u;
	foreach ($mech->links) {
		$u = $_->url;
		if ($u =~ /url.q=(http.+?)&/) {
			$u = $1;
			print $_->text,"\n$u\n";
			last if ($u =~ /(paroles.net|lyricsfreak.com)/);
			next if ($_->text =~ /youtube/i || $u =~ /youtube/);
		}
	}
	if ($u !~ /(paroles.net|lyricsfreak.com)/) {
		print "get_lyrics: url inconnue : $u pas de paroles ?\n";
		return undef;
	}
	$mech->get($u);
	# $mech->save_content("page.html");
	$_ = $mech->content;
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
	} elsif ($u =~ /paroles.net/) {
		my $lyr = 0;
		my $div = 0;
		my $start_div;
		foreach (split /\n/,$_) {
			s/\r//;
			$div++ if (/<div/);
			$div-- if (/<\/div/);
			if (s/<div class="song-text">//) {
				$lyr = 1;
				$start_div = $div-1;
			}
			if ($lyr) {
				if (/<\/?div/ && $div == $start_div) {
					$lyr = 0;
					next;
				}
				s/<br>/\n/g;
				# Filtrage des pubs en plein milieu de la chanson !!!
				$lyrics .= decode_entities($_) if (!/<\/?(div|script)/ && $div-1 == $start_div);
			}
		}
		$lyrics =~ s/\n$//s;
	}

	if ($ogg) {
		$lyrics =~ s/\n/<br>/sg;
		$ogg->add_comments("LYRICS",$lyrics);
		my $ret = $ogg->write_vorbis();
		if ($ret == 1) {
			print "ogg file updated !\n";
		} else {
			# Old ogg files can't have their comments updated (ogg 1.2.0 and
			# before).
			if (open(F,">$file.lyrics")) {
				print F "$lyrics";
				close(F);
				print "lyrics file created\n";
			}
		}
		$lyrics =~ s/<br>/\n/sg;
	} elsif ($mp3) {
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
	}
	return $lyrics;
}

1;

