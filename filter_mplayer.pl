#!/usr/bin/perl

# Au départ c'était sensé être un script simple...
# juste de quoi récupérer en temps réel la sortie de mplayer pour réagir
# aussitôt.
# Mais après j'ai voulu ajouter les recherches de google images
# Et là s'est posé un problème à priori simple : comment interrompre une
# lecture à intervalles réguliers pour aller faire autre chose ? Normalement
# ça se fait en 1 seule ligne : alarm. Sauf que là c'est une fifo, et si le
# signal d'alarm arrive pendant la lecture de la fifo, ça provoque une
# fermeture de la fifo et un SIGPIPE à l'autre bout ! Du coup il a fallu se
# rabattre sur select/sysread, et ça alourdit considérablement l'écriture...

use strict;
use Fcntl;
require "output.pl";
eval {
	require WWW::Google::Images;
	WWW::Google::Images->import();
};
my $images = 0;
my @cur_images;
our $agent;
my $last_t = 0;
our $stream = 0;
our $init = 0;
if (!$@) {
	# google images dispo si pas d'erreur
	$images = 1;
	$agent = WWW::Google::Images->new(
		server => 'images.google.com',
	);
}
our $titre = "";
our $artist;
our $album;
our $old_titre = "";
our $time;
our $last_image;
my $buff = "";

sub handle_result {
	my $result = shift;
	my $image;
	if ($image = $result->next()) {
		open(F,"<desktop");
		my $w = <F>;
		my $h = <F>;
		close(F);
		chomp($w,$h);
		my ($x,$y) = ($w/36,$h/36);
		$w -= $x; $h -= $y;
		if (open(F,"<list_coords")) {
			my $coords = <F>;
			my ($aw,$ah,$ax,$ay) = split(/ /,$coords);
			$x = $ax+$aw;
			$y = $ay;
			$w -= $x;
			close(F);
		}
		if ($w <= 10) {
			print "handle_result : on aurait w=$w, on annule\n";
			return;
		}
		if (open(F,"<info_coords")) {
			my $coords = <F>;
			close(F);
			my ($aw,$ah,$ax,$ay) = split(/ /,$coords);
			$h = $ay-$y;
		}

		my ($pic,$ftype);
		do {
			$pic = $image->save_content(base => 'image');
			print "handle_result: context ",$image->context_url()," name $pic\n";
			if ($last_image && $pic ne $last_image) {
				unlink $last_image;
			}
			$last_image = $pic;
			$ftype = `file $pic`;
			chomp $ftype;
			if ($ftype =~ /error/i) {
				$image = $result->next;
				if (!$image) {
					return if (!$image);
				}
			}
		} while ($ftype =~ /error/i);

		if ($ftype =~ /gzip/) {
			rename($pic,"$pic.gz");
			system("gunzip $pic.gz");
		}
		my $out = open_bmovl();
		print $out "image $pic $x $y $w $h\n";
		close($out);
	}
}

sub handle_images {
	my $cur = shift;
	$cur = $old_titre if (!$cur);
	$old_titre = $cur;
	print "handle_image: $cur.\n";
	if (!@cur_images || $cur_images[0] ne $cur) {
		# Reset de la recherche précédente si pas finie !
		if ($cur_images[1]) {
			my $result = $cur_images[1];
			while ($result->next()) {}
			unlink $last_image if ($last_image);
		}

		@cur_images = ($cur);

		my $result = $agent->search($cur, limit => 10);
		handle_result($result);
		push @cur_images,$result;
	} else {
		my $result = $cur_images[1];
		handle_result($result);
	}
	$time = time()+25;
}

my $pid;
open(F,"<info.pid") || die "can't open info.pid !\n";
$pid = <F>;
chomp $pid;
close(F);
if (open(F,"<current")) {
	@_ = <F>;
	close(F);
}
our ($chan,$source,$serv,$flav) = @_;
chomp ($chan,$source,$serv,$flav);
unlink "stream_info";
my ($width,$height) = ();
my $exit = "";
my ($codec,$bitrate);

sub check_eof {
	print "check_eof: $source\n";
	unlink("video_size","stream_info",$last_image);
	if (!$stream && -f "info_coords") {
		open(F,">fifo_info");
		print F "clear\n";
		close(F);
	}
	if ($source eq "Fichiers son" && $exit !~ /ID_EXIT=QUIT/) {
		print "filter: envoi nextchan\n";
		if (open(F,">fifo_list")) {
			print F "nextchan\n";
			close(F);
		}
	}
}

sub send_cmd_prog {
	my $tries = 1;
	my $error;
	do {
		if (sysopen(F,"fifo_info",O_WRONLY|O_NONBLOCK)) {
			$error = 0;
			print F "prog $chan\n";
			close(F);
		} else {
			print "filter: envoi commande prog from filter impossible tries=$tries !\n";
			$error = 1;
			sleep(1);
		}

	} while ($error && $tries++ < 3);
}

sub update_codec_info {
	if ($codec && $bitrate && $init) {
		my $info = "";
		if (open(F,"<stream_info")) {
			while (<F>) {
				$info .= $_;
			}
		}
		close(F);
		if (open(F,">stream_info")) {
			print F "$codec $bitrate\n";
			print F $info if ($info);
			close(F);
		} else {
			print "impossible de créer stream_info !\n";
		}
		send_cmd_prog();
	}
}

my $rin = "";
vec($rin,fileno(STDIN),1) = 1;
while (1) {

	chomp;
	my $t = undef;
	$t = $time - time() if ($time);
	if ($t < 0) {
		handle_images();
		next;
	}
	my $rout = $rin;
	my $nfound = select($rout,undef,undef,$t);
	if ($time && $time <= time()) {
		handle_images();
	}
	if ($nfound > 0) {
		my $ret = sysread(STDIN,$buff,8192,length($buff));
		$buff =~ s/\x00+//;
		if (length($buff) > 40000) {
			open(F,">buff");
			print F $buff;
			close(F);
			exit(1);
		}

		if (defined($ret) && $ret == 0) {
			last;
		}
	} else {
		next;
	}
	while ($buff =~ s/(.+?)[\n\r]//) {
		$_ = $1;
		if (/ID_VIDEO_WIDTH=(.+)/) {
			$width = $1;
		} elsif (/ID_VIDEO_HEIGHT=(.+)/) {
			$height = $1;
		} elsif (/ID_AUDIO_CODEC=(.+)/) {
			$codec = $1;
			$codec =~ s/mpg123/mp3/;
			update_codec_info();
		} elsif (/ID_AUDIO_BITRATE=(.+)/ || /^Bitrate\: (.+)/) {
			if ($1) {
				$bitrate = $1;
				$bitrate =~ s/000$/k/;
				update_codec_info();
			}
		} elsif (/(Audio only|Video: no video)/) {
			if (!$init) {
				$init = 1;
				update_codec_info() if ($bitrate && $codec);
			}
		} elsif (/(\d+) x (\d+)/ && $width < 300) {
			$width = $1; $height = $2; # fallback here if it fails
		} elsif (/(\d+)x(\d+) =/ && $width < 300) {
			$width = $1; $height = $2; # fallback here if it fails
		} elsif (/ID_(EXIT|SIGNAL)/) {
			$exit .= $_;
		} elsif (/End of file/i) {
			$exit .= $_;
		} elsif (/ICY Info/) {
			my $info = "";
			$stream = 1;
			while (s/([a-z_]+)\=\'(.*?)\'\;//i) {
				my ($name,$val) = ($1,$2);
				if ($name eq "StreamTitle") {
					$info .= "$val ";
					$titre = $val;
					$info .= " (pas de WWW::Google::Images)" if (!$images);
				} elsif ($val && $name ne "StreamUrl") {
					$info .= " + $name=\'$val\' ";
				}
			}
			$info =~ s/ *$//;
			if ($info && open(F,">>stream_info")) {
				print F "$info\n";
				close(F);
			}
			system("./info 1 &");

			if ($images && $titre =~ /\-/ && $titre ne $old_titre) {
				handle_images($titre) ;
			} else {
				$titre = $old_titre;
			}
		} elsif (/Title: (.+)/i) {
			$titre = $1;
		} elsif (/Artist: (.+)/i) {
			$artist = $1;
		} elsif (/Album: (.+)/i) {
			$album = $1;
		} elsif (!$stream && /^A:[ \t]+(.+?) \((.+?)\) of (.+?) \((.+?)\)/) {
			my ($t1,$t2,$t3,$t4) = ($1,$2,$3,$4);
			if ($t1 - $last_t >= 1) {
				if (!$artist && !$titre && $chan =~ /(.+) - (.+)\..../) {
					# Déduction de l'artiste et du titre sur le nom de fichier
					($artist,$titre) = ($1,$2);
				}
				handle_images("$artist - $titre ($album)")
				if ($last_t == 0 && ($artist || $titre));
				$last_t = $t1;
				if (open(F,">stream_info")) {
					print F "$codec $bitrate\n";
					print F "$artist - $titre ($album) $t2 ".int($t1*100/$t3),"%\n";
					close(F);
					send_cmd_prog();
				}
			}
		} elsif (/Starting playback/) {
			if ($width && $height) {
				open(F,">video_size") || die "can't write to video_size\n";
				print F "$width\n$height\n";
				close(F);
				kill "USR1",$pid;
			}
			send_cmd_prog();
		} elsif (/End of file/ || /^EOF code/) {
			print "filter: end of video\n";
			kill "USR2",$pid;
			check_eof();
		}
	}
}
kill "USR2",$pid;
if ($exit) {
	open(F,">id") || die "can't write to id\n";
	print F "$exit\n";
	close(F);
	print "filter: fichier id créé\n";
}
print "filter: exit message : $exit\n";
check_eof();
