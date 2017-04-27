package link_get;

use WWW::Mechanize;
use POSIX qw(:sys_wait_h );
use strict;

our $debug = 0;

sub REAPER {
	my $child;
	$SIG{CHLD} = \&REAPER;
	while (($child = waitpid(-1,WNOHANG)) > 0) {
	}
}

sub link_get {
	my ($file,$url,$size) = @_;
	# traite un link get : vérification de la taille, lancement éventuel de
	# wget, renvoi du nom de fichier sur stdout (pour les plugins de flux)
	# note : la taille est optionnelle en paramètre, valable surtout pour
	# les podcasts et encore, certains ont une taille erronnée dans leus
	# infos. Quand la taille n'est pas passée, elle est récupérée par un
	# head sur l'url (et si elle est passée, le head est appelé quand même
	# pour vérifier si ça colle !)

	# Vérification de la taille !!!
	# Même un serveur comme radio france a l'air d'envoyer parfois des tailles
	# totalement farfelues, on se demande comment leur truc est codé encore...

	my $mech = WWW::Mechanize->new();
	$mech->agent_alias("Linux Mozilla");
	$mech->timeout(10);
	$mech->default_header('Accept-Encoding' => scalar HTTP::Message::decodable());

	my $r = $mech->head($url);
	if ($size != $r->header("Content-length") && $r->header("Content-length")) {
		# print "podcast: taille du fichier pod invalide, on garde la taille head: ",$r->header("Content-length"),"\n";
		$size = $r->header("Content-length");
	}

	if (!-f "$file" || -s $file != $size) {
		print STDERR "lien get: taille != $size pour fichier $file\n";
		$SIG{CHLD} = \&REAPER;
		my $pid = fork();
		if (!$pid) {
			# Note : normalement un lien get n'est fait QUE sur une liste
			# de type direct ce qui rend la fermeture des STD inutile, mais
			# si jamais on oublie, ça va bloquer ici, à priori autant les
			# fermer ça évite des conneries...
			close(STDIN);
			close(STDOUT);
			close(STDERR);
			exec("wget","-O",$file,"-q","-c","-N",$url);
		}
		my $n = 1;
		my $dest = 10*1024*1024;
		while ($n++ < 10 && -s $file < $dest) {
			my ($found_video,$found_audio);
			# C'est pas si long à coder, on essaye juste d'ouvrir le
			# fichier toutes les secondes jusqu'à ce qu'on détecte le codec
			# video et audio, + efficace que d'attendre une taille fixe vu
			# que ça peut changer en fonction de plein de trucs.
			if (open(F,"mplayer -frames 0 -identify $file 2>/dev/null|") ||
				open(F,"mplayer2 -frames 0 -identify $file 2>/dev/null|")) {
				while (<F>) {
					$found_audio = 1 if (/ID_AUDIO_FORMAT/);
					$found_video = 1 if (/ID_VIDEO_FORMAT/);
				}
				close(F);
				# print "found_audio $found_audio video $found_video\n";
				last if ($file =~ /mp3$/i && $found_audio);
				last if ($file !~ /mp3$/i && $found_audio && $found_video);
			}

			# lien get sur le réseau, y a vraiment intérêt à lui laisser de
			# l'avance, 1s ne semble pas assez dans tous les cas, va pour
			# 1.5 alors...
			select undef,undef,undef,1.5;
		}
	}
	print "$file\n"; # Renvoie le nom du fichier à list.pl
	exit(0);
}

1;

