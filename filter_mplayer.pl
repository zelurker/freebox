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
use POSIX qw(:sys_wait_h);
require "output.pl";
require "playlist.pl";
use IPC::SysV qw(IPC_PRIVATE IPC_RMID S_IRUSR S_IWUSR);
use Data::Dumper;

$Data::Dumper::Indent = 0;
$Data::Dumper::Deepcopy = 1;
our %ipc;
our $agent;
my @list;
my $net = have_net();
my $images = 0;
eval {
	require WWW::Google::Images;
	WWW::Google::Images->import();
};
if (!$@ && $net) {
	# google images dispo si pas d'erreur
	$images = 1;
	$agent = WWW::Google::Images->new(
		server => 'images.google.com',
	);
}
our @cur_images;
our $pos;
my $last_t = 0;
our $stream = 0;
our %bookmarks;
dbmopen %bookmarks,"bookmarks.db",0666;
our $init = 0;
our $prog;
our ($codec,$bitrate);
our $titre = "";
our $artist;
our $album;
our $old_titre = "";
our $time;
our $time_prog;
our $last_image;
my $buff = "";
our %bg_pic;

sub REAPER {
	my $child;
	# loathe SysV: it makes us not only reinstate
	# the handler, but place it after the wait
	$SIG{CHLD} = \&REAPER;
# Les images arrivent en tache de fond...
	while (($child = waitpid(-1,WNOHANG)) > 0) {
		if ($bg_pic{$child}) {
			if (!-f $bg_pic{$child}) {
				my $result = $cur_images[1];
				handle_result($result);
			} else {
				$last_image = $bg_pic{$child};
			}
			delete $bg_pic{$child};
		} elsif ($ipc{$child}) {
			my $id = $ipc{$child};
			my $dump;
			shmread($id,$dump,0,180000) || die "shmread: $!";
			my $result;
			$dump =~ s/\000+//;
			eval($dump);
			handle_result($result);
			push @cur_images,$result;
			shmctl($id, IPC_RMID, 0)        || die "shmctl: $!";
			delete $ipc{$child};
		} else {
			print "filter: didn't find bg_pic for child $child\n";
		}
	}
}
$SIG{CHLD} = \&REAPER;

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

		my ($pic);
		my $url = $image->content_url();
		my $ext = $url;
		$ext =~ s/.+\.//;
		my $name = "image.$ext";
		my $pid = fork();
		if ($pid == 0) {
			$pic = $image->save_content(file => $name);
			print "handle_result: context ",$image->context_url()," name $pic\n";
			if (! -f "$pic") {
				print "filter: pas d'image $pic\n";
				exit 0;
			}
			if ($last_image && $pic ne $last_image) {
				unlink $last_image;
			}
			my $ftype = `file $pic`;
			chomp $ftype;
			if ($ftype =~ /error/i) {
				unlink "$pic";
				print "filter: type image $ftype\n";
				exit 0;
			}
			if ($ftype =~ /gzip/) {
				rename($pic,"$pic.gz");
				system("gunzip $pic.gz");
			}
			send_bmovl("image $pic $x $y $w $h");
			exit 0;
		} else {
			$bg_pic{$pid} = $name;
		}
	}
}

sub handle_images {
	my $cur = shift;
	$cur = $old_titre if (!$cur);
	$old_titre = $cur;
	print "handle_image: $cur.\n";
	return if (!$net);
	if (!@cur_images || $cur_images[0] ne $cur) {
		# Reset de la recherche précédente si pas finie !
		if ($cur_images[1]) {
			my $result = $cur_images[1];
			while ($result->next()) {}
			if ($last_image eq "1") {
				print "on évite d'effacer le fichier 1 (2)\n";
			} else {
				unlink $last_image if ($last_image);
			}
		}

		@cur_images = ($cur);
		my $size = 200000;
		my $id = shmget(IPC_PRIVATE, $size, S_IRUSR | S_IWUSR) || die "shmget $!\n";
		my $pid = fork();
		if ($pid) {
			$ipc{$pid} = $id;
		} else {
			my $result = $agent->search($cur, limit => 10);
			my $dump = Data::Dumper->Dump([$result],[qw(result)]);
			shmwrite($id,$dump,0,180000) || die "shmwrite\n";
			exit(0);
		}

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
$serv =~ s/ (http.+)//;
$prog = $1;
print "filter: prog = $prog\n";
$source =~ s/\/.+//;
unlink "stream_info";
my ($width,$height) = ();
my $exit = "";

sub bindings($) {
	my $cmd = shift;
	print "*** filter: bindings $cmd (",ord($cmd)," ",ord(index($cmd,1)),") ",length($cmd),"\n";
	if (ord($cmd) >= 0xd0 && ord($cmd) <= 0xd9) {
		# Hack pour réussir à transmettre KP0..KP9 à travers sdl
		$cmd = "KP".chr(ord("0")+ord($cmd)-0xd0);
	}

	if ($cmd =~ /^KP(\d)/) {
		send_cmd_list($1);
	} elsif ($cmd =~ /KP_ENTER/) {
		if (-f "list_coords" || -f "numero_coords") {
			send_cmd_list("zap1");
		} elsif (-f "info_coords") {
			send_cmd_info("zap1");
		}
	} elsif ($cmd eq "KP_INS") {
		send_cmd_list("0");
	} elsif ($cmd =~ /^[A-Z]$/) {
		# Touche alphabétique
		send_cmd_list($cmd);
	} else {
		print "bindings: touche non reconnue $cmd\n";
	}
}

sub check_eof {
	print "check_eof: $source\n";
	unlink("video_size","stream_info");
	if ($last_image eq "1") {
	    print "on évite d'effacer le fichier 1\n";
	} else {
	    unlink $last_image if ($last_image);
	}
	if (!$stream && -f "info_coords") {
		if (sysopen(F,"fifo_info",O_WRONLY|O_NONBLOCK)) {
			print F "clear\n";
			close(F);
		}
	}
	if (!$exit) {
		print "filter: fait quitter mplayer...\n";
		send_command("quit\n");
		eval {
			alarm(3);
			while (<>) {}
			alarm(0);
		};
		if ($@) {
			system("killall mplayer; killall mplayer2");
			print "filter: kill !!!\n";
			$exit .= "ID_EXIT=QUIT ";
			sleep(1);
			system("killall -9 mplayer; killall -9 mplayer2");
		} else {
			print "filter: mplayer parti proprement !\n";
		}
	}
	if ($exit) {
		open(F,">id") || die "can't write to id\n";
		print F "$exit\n";
		close(F);
		print "filter: fichier id créé\n";
	}
	if ($source =~ /^(cd|Fichiers son)/ && $exit !~ /ID_EXIT=QUIT/ && $exit ne "") {
		print "filter: envoi nextchan exit $exit\n";
		send_cmd_list("nextchan");
	}
	if ($source eq "Fichiers vidéo" && ($exit =~ /ID_EXIT=QUIT/ || !$exit)) {
		print "filter: take bookmark pos $pos for name $serv\n";
		$bookmarks{$serv} = $pos;
	} else {
		print "filter: source $source exit $exit name $serv\n";
		delete $bookmarks{$serv};
	}
	dbmclose %bookmarks;
	exit(0); # au cas où on est là par un signal
}

sub send_cmd_prog {
	# Le test -f info_coords est pour essayer de ne pas effacer le bandeau
	# sur timer quand on l'a affiché en fixe.
	# Evidemment ça va pas marhcer dans 100% des cas, si le morceau commence
	# et que send_cmd_prog est appelé avant que le bandeau n'ait eu le temps
	# de s'effacer, il va devenir fixe.
	# Bah au moins ça donne un moyen d'avoir un bandeau fixe ou pas de bandeau
	# du tout sans liste.
	send_cmd_info("prog".(-f "info_coords" ? ":long" : "")." $chan");
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
			send_cmd_prog();
		} else {
			print "impossible de créer stream_info !\n";
		}
	}
}

$SIG{TERM} = \&check_eof;
my $rin = "";
vec($rin,fileno(STDIN),1) = 1;
if ($prog && $net) {
	$time_prog = time()+1;
}

my $old_str = "";
while (1) {

	chomp;
	my $t = undef;
	my $t0 = time();
	$t = $time - $t0 if ($time);
	if ($t && $t < 0) {
		handle_images();
		next;
	}
	if ($time_prog && (($t && $time_prog - $t0 < $t) || !$t)) {
		$t = $time_prog - $t0;
	}

	my $rout = $rin;
	my $nfound = select($rout,undef,undef,$t);
	$t0 = time();
	if ($time && $time <= $t0) {
		handle_images();
	}
	if ($time_prog && $time_prog <= $t0) {
		unlink "stream_info.0";
		rename "stream_info","stream_info.0";
		my $str = handle_prog($prog,"$codec $bitrate");
		if ($str) {
			$time_prog = time()+30;
			my $diff = 0;
			if (open(F,"stream_info")) {
				if (open(G,"<stream_info.0")) {
					while (<F>) {
						if ($_ ne <G>) {
							$diff = 1;
							last;
						}
					}
					close(G);
				} else {
					$diff = 1;
				}
				close(F);
			} 
			if ($diff) {
				print "send_cmd_prog got str $str\n";
				send_cmd_prog();
			} else {
				print "filter: pas de cmd prog, pas de diff\n";
			}
			if ($str ne $old_str) {
				print "new call to handle_image (old = $old_str)\n";
				handle_images($str);
				$old_str = $str;
			}
		} else {
			print "filter: pas obtenu de str $str\n";
		}
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
			print "filter: sortie sur ret $ret\n";
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
			check_eof() if (/ID_SIGNAL=6/);
		} elsif (/End of file/i) {
			$exit .= $_;
		} elsif (/ICY Info/) {
			my $info = "";
			$stream = 1;
			while (s/([a-z_]+)\=\'(.*?)\'\;//i) {
				my ($name,$val) = ($1,$2);
				if ($name eq "StreamTitle" && $val) {
					$info .= "$val ";
					$titre = $val;
					$info .= " (pas de WWW::Google::Images)" if (!$images);
				} elsif ($val && $name !~ /^(StreamUrl|adw_ad|durationMilliseconds|insertionType|metadata)/) {
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
		} elsif (/Artist: (.+)/i || /ID_CDDB_INFO_ARTIST=(.+)/) {
			$artist = $1;
		} elsif (/ID_CDDB_INFO_TRACK_(\d+)_NAME=(.+)/) {
			$list[$1] = $2;
		} elsif (/Album: (.+)/i) {
			$album = $1;
		} elsif (/ID_FILENAME=cddb...(.+)/) {
			$titre = $list[$1];
			print "filter: cddb: on prend titre = $titre artist $artist\n";
			handle_images("$artist - $titre") # ($album)")
		} elsif (!$stream && /^A:[ \t]+(.+?) \((.+?)\..+?\) of (.+?) \((.+?)\)/) {
			my ($t1,$t2,$t3,$t4) = ($1,$2,$3,$4);
			if ($t1 - $last_t >= 1) {
				if (!$artist && !$titre && $chan =~ /(.+) - (.+)\..../) {
					# Déduction de l'artiste et du titre sur le nom de fichier
					($artist,$titre) = ($1,$2);
				}
				handle_images("$artist - $titre") # ($album)")
				if ($images && $last_t == 0 && ($artist || $titre));
				$last_t = $t1;
				if (open(F,">stream_info")) {
					print F "$codec $bitrate".($images ? "" : " - pas de WWW::Google::Images")."\n";
					print F "$artist - $titre ($album) $t2 ".int($t1*100/$t3),"%\n";
					close(F);
					send_cmd_prog();
				}
			}
		} elsif (/Starting playback/) {
			if ($width && $height) {
				open(F,">video_size") || die "can't write to video_size\n";
				print "filter: init video $width x $height\n";
				print F "$width\n$height\n";
				close(F);
				print "filter: envoi USR1 à $pid\n";
				unlink("list_coords","video_coords","info_coords","numero_coords","mode_coords");
				kill "USR1",$pid;
			}
			send_cmd_prog();
			if ($bookmarks{$serv}) {
				print "filter: j'ai un bookmark pour cette vidéo\n";
				send_command("seek $bookmarks{$serv} 2\n");
			}
		} elsif (/End of file/ || /^EOF code/) {
			print "filter: end of video\n";
			print "filter: USR2 point1\n";
			kill "USR2",$pid;
			check_eof();
		} elsif (!$stream && /^A:(.+?) V:/) {
			$pos = $1;
		} elsif (/No bind found for key \'(.+)\'/) {
			bindings($1);
		}
	}
}
print "filter: USR2 point2\n";
kill "USR2",$pid;
print "filter: exit message : $exit\n";
check_eof();
