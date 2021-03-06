#!/usr/bin/perl

# Au d�part c'�tait sens� �tre un script simple...
# juste de quoi r�cup�rer en temps r�el la sortie de mplayer pour r�agir
# aussit�t.
# Mais apr�s j'ai voulu ajouter les recherches de google images
# Et l� s'est pos� un probl�me � priori simple : comment interrompre une
# lecture � intervalles r�guliers pour aller faire autre chose ? Normalement
# �a se fait en 1 seule ligne : alarm. Sauf que l� c'est une fifo, et si le
# signal d'alarm arrive pendant la lecture de la fifo, �a provoque une
# fermeture de la fifo et un SIGPIPE � l'autre bout ! Du coup il a fallu se
# rabattre sur select/sysread, et �a alourdit consid�rablement l'�criture...

use strict;
use v5.10;
use Coro::LWP;
use Coro;
use Coro::Handle;
use Coro::Select;
use AnyEvent;
use AnyEvent::Util;
use AnyEvent::Socket;
use Fcntl;
use POSIX qw(:sys_wait_h);
use out;
require "playlist.pl";
use IPC::SysV qw(IPC_PRIVATE IPC_RMID S_IRUSR S_IWUSR);
use Data::Dumper;
use images;
use Encode;
use Ogg::Vorbis::Header;
use URI::URL;
use lyrics;

our $latin = ($ENV{LANG} !~ /UTF/i);
our $has_vignettes = undef;
our ($child,$parent);
our %setting;

sub utf($) {
	my $str = shift;
	if ($latin && $str =~ /[\xc3\xc5]/) {
		# Tentative de d�tection de l'utf8, pas du tout s�r de marcher !
		Encode::from_to($str, "utf-8", "iso-8859-15");
	} else {
		print "utf: encodage utf $str is_utf:",utf8::is_utf8($str),"\n";
		print "result : ", utf8::decode($str)," chaine:$str\n";
	}
	$str;
}

my @tracks;
open(F,"<desktop");
my $desk_w = <F>;
my $desk_h = <F>;
close(F);
chomp($desk_w,$desk_h);
our @args = @ARGV;
our $start_time;
@ARGV = ();
my $useragt = 'Telerama/1.0 CFNetwork/445.6 Darwin/10.0.0d3';
my $browser = LWP::UserAgent->new(keep_alive => 0,
	agent =>$useragt);
$browser->timeout(3);
$browser->default_header(
	[ 'Accept-Language' => "fr-fr"
		#                          'Accept-Encoding' => "gzip,deflate",
		# 'Accept-Charset' => "ISO-8859-15,utf-8"
	]
);
our $pid_player1;
if (-f "player1.pid") {
	# il faut r�cup�rer ce pid au d�but parce qu'un nouveau peut etre lanc�
	# alors que filter tourne encore
	$pid_player1 = `cat player1.pid`;
	chomp $pid_player1;
}

our ($pid_mplayer,$length,$start_pos);

$Data::Dumper::Indent = 0;
$Data::Dumper::Deepcopy = 1;
our %ipc;
our $agent;
my @list;
our $eof = 0;
my @duree;
my $net = out::have_net();
my $images = 0;
our ($connected,$started);
if ($net) {
	$images = 1;
	$agent = images->new();
}

our @cur_images;
our ($pos,$last_pos);
my $last_track;
my $last_t = 0;
our $stream = 0;
our %bookmarks;
dbmopen %bookmarks,"bookmarks.db",0666;
our $init = 0;
our $prog;
our ($codec,$bitrate,$lyrics);
our $titre = "";
my $a1 = $args[1];
$a1 =~ s/.part$//;
if (open(F,"<$a1.info")) {
	# Si il y a un fichier info pour ce qu'on lit (podcast par exemple)
	# alors r�cup�re le titre dedans !
	$titre = <F>;
	chomp $titre;
	close(F);
	$titre =~ s/pic:(http.+?) //;
}
our $artist;
our $album;
our $old_titre = "";
our $time;
our $time_prog;
our $pid_lyrics;
our $wait_lyrics = 0;
my $buff = "";
our %bg_pic;

$SIG{PIPE} = sub { print "filter_mplayer: sigpipe ignor�\n" };

sub get_lyrics {
	# Apparemment il faut des param�tres locaux sinon
	# en our c'est mis � jour dans le async quand il a le temps, souvent
	# trop tard !
	my ($artist,$titre) = @_;
	if ($pid_lyrics) {
		$wait_lyrics = 1;
		return;
	}
	$lyrics = 1;
	async {
		# LOOP n�cessaire pour sortir par last ??!
		LOOP: {
		do {
			my ($aut,$tit) = ($artist,$titre);
			# Gestion des flux : ils passent directement l'artiste et le titre
			# dans StreamTitle... !
			if (!$aut && $tit =~ /(.+) \- (.+)/) {
				$aut = $1; $tit = $2;
			}
			$tit =~ s/ \(.+\)//; # Supprime toute mention entre () dans le titre
			print "*** filter: calling get_lyrics $args[1] artist $aut titre $tit\n";
			my $lyrics = lyrics::get_lyrics($args[1],$aut,$tit);
			if ($lyrics) {
				Encode::from_to($lyrics, "utf-8", "iso-8859-15") if ($latin);
				out::send_cmd_info("lyrics\n$lyrics");
			} else {
				out::send_cmd_info("lyrics"); # Au cas o� le titre vient de changer et qu'on a pas l'info
			}
			if ($wait_lyrics) {
				cede;
				$wait_lyrics = 0;
			} else {
				last;
			}
		} while (1);
	}
	}
}

sub handle_result {
	my $result = shift;
	my $image;
	if (!$result) {
		print "handle_result sans result ???\n";
		return;
	}
	while (1) {
		$image = shift @$result;
		last if (!$image);
		if ($image->{w} >= 320 || !$image) {
			last;
		} else {
			print "image trop petite (",$image->{w},"), on passe... reste $#$result\n";
		}
	}
	if ($image) {
		my $name = "cache/".$image->{tbnid};
		$name =~ s/://;
		$image = $image->{imgurl};

		my ($pic);
		my $url = $image;
		my $ext = $url;
		$ext =~ s/.+\.//;
		$ext = substr($ext,0,3); # On ne garde que les 3 1ers caract�res !
		$name .= ".$ext";
		if (-f $name) {
			utime(undef,undef,$name);
			print "handle_result: using cache $name\n";
			out::send_bmovl("image $name");
		} else {
			async {
				my $referer = $url;
				$referer =~ s/(.+)\/.+?$/$1\//;
				print "get image $url, referer $referer\n";
				my $res = $browser->get($url,"Referer" => $referer,":content_file" => $name);
				$pic = $name;
				if (!$res->is_success) {
					print "filter: erreur get ",$res->status_line,"\n";
					handle_images();
					Coro::terminate 1;
				}
				my $ftype = `file $pic`;
				chomp $ftype;
				if ($ftype =~ /gzip/) {
					print "gzip content detected\n";
					rename($pic,"$pic.gz");
					system("gunzip $pic.gz");
					$ftype = `file $pic`;
					chomp $ftype;
				}
				if ($ftype =~ /error/i || $ftype =~ /HTML/) {
					unlink "$pic";
					print "filter: type image $ftype\n";
					handle_images();
					Coro::terminate 1;
				}
				print "handle_result: calling image $pic\n";
				out::send_bmovl("image $pic");
			}
		}
		$time = AnyEvent->timer(after => 25,
			interval => 25,
			cb => sub { handle_images(); });
	} else {
		print "handle_result: fin de liste!\n";
		out::send_bmovl("vignettes") if ($has_vignettes);
		$time = undef;
	}
}

sub handle_images {
	my $cur = shift;
	$cur = $old_titre if (!$cur);
	$old_titre = $cur;
	print "handle_image: $cur net $net.\n";
	return if (!$net);
	if (!@cur_images || $cur_images[0] ne $cur) {
		print "handle_image: reset search\n";
		# Reset de la recherche pr�c�dente si pas finie !
		if ($cur_images[1]) {
			my $result = $cur_images[1];
		}

		@cur_images = ($cur);
		$cur =~ s/�/u/g; # Pour une raison inconnue allergie !
		my $res = $agent->search($cur);
#		open(F,">vignettes");
#		foreach (@$res) {
#			print F $_,"\n";
#		}
#		close(F);
		# $has_vignettes = 1;
		out::send_bmovl("vignettes") if ($has_vignettes);
		my $result = $agent->{tab};
		push @cur_images,$result;
		handle_result($result);
	} else {
		print "handle_image calling handle_result\n";
		my $result = $cur_images[1];
		handle_result($result);
	}
}

my $pid;
open(F,"<info.pid") || die "can't open info.pid !\n";
$pid = <F>;
chomp $pid;
close(F);
our ($chan,$source,$serv,$flav,$audio,$video,$name) = out::get_current();
$serv =~ s/ (http.+)//;
$prog = $1 if ($source !~ /youtube/);
print "filter: prog = $prog\n";
$source =~ s/\/(.+)//;
our $base_flux = $1;
my ($width,$height) = ();
my $exit = "";

sub bindings($) {
	my $cmd = shift;
	print "*** filter: bindings $cmd (",ord($cmd)," ",ord(index($cmd,1)),") ",length($cmd),"\n";
	if (ord($cmd) >= 0xd0 && ord($cmd) <= 0xd9) {
		# Hack pour r�ussir � transmettre KP0..KP9 � travers sdl
		$cmd = "KP".chr(ord("0")+ord($cmd)-0xd0);
	}

	if ($cmd =~ /^KP(\d)/) {
		out::send_cmd_fifo("sock_list",$1);
	} elsif ($cmd =~ /KP_ENTER/) {
		if (-f "list_coords" || -f "numero_coords") {
			out::send_cmd_fifo("sock_list","zap1");
		} elsif (-f "info_coords") {
			out::send_cmd_info("zap1");
		}
	} elsif ($cmd eq "KP_INS") {
		out::send_cmd_fifo("sock_list","0");
	} elsif ($cmd =~ /^[A-Z]$/ || $cmd =~ /^F\d+$/) {
		# Touche alphab�tique
		out::send_cmd_fifo("sock_list",$cmd);
	} else {
		print "bindings: touche non reconnue $cmd\n";
	}
}

sub check_eof {
	return if ($eof);
	$eof = 1;
	unlink "vignettes" if ($has_vignettes);
	print "check_eof: $source exit:$exit\n";
	unlink("video_size","cache/arte/last_serv");
	if (!$stream && -f "info_coords") {
		if (sysopen(F,"fifo_info",O_WRONLY|O_NONBLOCK)) {
			print F "clear\n";
			close(F);
		}
	}
	if (!$exit || $exit =~ /ID_SIGNAL.(11|6)/) {
		quit_mplayer();
	}
	if ($started) {
		if ($length && $length>0 && ($pos-$start_pos)/$length<0.9 && $length > 300 &&
			# probl�me des bookmarks sur les ts (flux livetv tnt ou freebox :
			# l'index des temps est mort et ne commence pas � 0. On peut mettre - $start_pos
			# pour compenser, mais �a devient faux quand on commence la lecture � un bookmark
			# � ce moment l� start_pos = le bookmark.
			# Pour compliquer encore, y a que mplayer2 qui arrive � g�rer le -ss avec un ts
			# A priori le seul moyen d'�viter que le bookmark ne soit jamais effac� est d'inclure un syst�me
			# qui vire les bookmarks sur des fichiers qui n'existent plus...
			$source =~ /(Fichiers|livetv|Enregist|flux)/ &&
			($exit =~ /ID_EXIT=QUIT/ || !$exit)) {
			print "filter: take bookmark pos $pos for name $serv\n";
			$bookmarks{$serv} = $pos;
		} else {
			print "filter: clear bookmark\n";
			delete $bookmarks{$serv};
		}
	}
	dbmclose %bookmarks;
	if (%setting) {
		if (open(F,">$ENV{HOME}/.freebox/$serv")) {
			foreach (keys %setting) {
				print F "$_ $setting{$_}\n";
			}
			close(F);
		}
	}
	if (-f $args[1] && $args[1] =~ /^podcast/) {
		utime(undef,undef,$args[1]); # touch sur le fichier pour les podcasts!
	}
	exit(0); # au cas o� on est l� par un signal
}

sub quit_mplayer {
	print "filter: fait quitter mplayer...\n";
	out::send_command("quit\n");
	eval {
		alarm(3);
		while (<>) {}
		alarm(0);
	};
	if ($@) {
		# On va tacher de r�cup�rer le bon pid !
		if ($pid_mplayer) {
			kill "TERM", $pid_mplayer;
			# $exit .= "ID_EXIT=QUIT ";
		}
	}
	sleep(1);
	# Evidemment �a impose d'avoir /proc mais �a simplifie !
	if (-f "/proc/$pid_mplayer/cmdline") {
		print "filter: mplayer pid=$pid_mplayer, on kille -9 !\n";
		kill "KILL", $pid_mplayer;
	} else {
		print "filter: mplayer parti proprement !\n";
	}
}

sub send_cmd_prog {
	# force long � 0 : ce long est un pb r�curent, pas s�r que �a soit la
	# bonne fa�on de faire, mais si on ne le force pas ici alors si on
	# appuie sur i pendant qu'on regarde une chaine de t�l� le bandeau
	# d'info reste en long et ne disparait plus tout seul quand on change
	# de chaine !
	my $cmd = "prog:0 $chan&$source";
	if ($chan =~ / video\// && $chan !~ /\....?$/) { # chan youtube
		# quand on arrive l� g�n�ralement on nous passe le titre ce qui ne
		# donne rien pour retrouver l'info, il vaut mieux passer par le
		# fichier � la place !
		$cmd = "prog:0 $args[1]&$source";
	}
	$cmd .= "/$base_flux" if ($base_flux);
	say STDERR "filter: sending command $cmd";
	out::send_cmd_info("$cmd") if ($cmd);
	# out::send_cmd_fifo("direct_sock_info",$cmd);
}

sub update_codec_info {
	my $f;
	if ($codec && $bitrate && $init) {
		out::send_cmd_info("codec $codec $bitrate");
	}
}

our $child_checker;

sub check_player2 {
	$child_checker = AnyEvent->child(pid => $pid_mplayer, cb => sub {
			my ($pid,$status) = @_;
			print "filter: fin de mplayer, pid $pid, status $status\n";
			$pid_mplayer = 0;
			$child_checker = undef;
		});
}

sub run_mplayer {
	# Lancement de mplayer � partir de filter
	($child,$parent) = portable_socketpair();
	# socketpair($child, PARENT, AF_UNIX, SOCK_STREAM, PF_UNSPEC)
	# ||  die "socketpair: $!";
	$start_time = time();

	$child->autoflush(1);
	$parent->autoflush(1);
	$pid_mplayer = fork();
	if ($pid_mplayer == 0) {
		$child->close();
		$args[1] =~ s/ http.+//; # vire le prog si il est encore attach� l� !
		if ($bookmarks{$serv}) {
			if ($bookmarks{$serv} > 0) {
				print "run_mplayer: bookmark $bookmarks{$serv}\n";
				push @args,("-ss",$bookmarks{$serv});
			} else {
				print "run_mplayer: deleting bookmark $bookmarks{$serv}\n";
				delete $bookmarks{$serv};
			}
		}
		open(STDIN, "<&",$parent) || die "can't dup stdin to parent";
		# close(STDIN);
		open(STDOUT, ">&",$parent) || die "can't dup stdout to parent";
		open(STDERR, ">&",$parent) || die "can't dup stderr";
		print "run_mplayer: args = @args\n";
		exec(@args);
	}
	check_player2();
}

our $fin = AnyEvent->signal( signal => "TERM", cb => \&check_eof );
my $rin = "";

if ($source =~ /^(dvb|freebox)/) {
	delete $bookmarks{$serv};
	print "clear bookmark source $source\n";
}
start:
# Lancement du prog en param�tre
if (@args) {
	run_mplayer();
} else {
	$child = *STDIN;
}
$parent->close();
# $child = unblock $child;
# print "non block : $child\n";
vec($rin,$child->fileno(),1) = 1;

our $old_str = "";

sub update_prog {
	# Mise � jour du programme � partir de l'url contenue dans
	# $prog...
	# Apparemment il faut obligatoirement un async ici pour Coro sinon on
	# se prend une erreur fatale de blocage incompr�hensible !
	async {
		my $str = handle_prog($prog,"$codec $bitrate");
		if ($str) {
			if ($str ne $old_str) {
				my ($artist,$titre) = split(/\-/,$str);
				get_lyrics($artist,$titre);

				print "new call to handle_image (old = $old_str)\n";
				handle_images($str);
				$old_str = $str;
			}
		} else {
			print "filter: pas obtenu de str $str\n";
			undef $time_prog;
		}
	}
}

if ($prog && $net) {
	$time_prog = AnyEvent->timer(after => 1, interval => 30, cb => sub { update_prog(); } );
}

while (1) {
	my $rout = $rin;
	my $nfound = select($rout,undef,undef,0.2); # Coro::Select
	if ($nfound) {
		# Pour une raison totalement inconnue, m�me si on appelle
		# $child = nonblock $child ici, sysread reste bloquant !
		# y a absolument rien � faire pour l'emp�cher apparemment du coup
		# j'ai laiss� tomber Coro::Handle pour child et j'utilise juste son
		# select...
		my $ret = $child->sysread($buff,8192); # ,length($buff));
		$buff =~ s/\x00+//;
		# apparently the buffer can be full of empty lines ? Just 4000 0xa
		# in it !
		$buff =~ s/\x0a{2,}//;
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
		if (/^Server returned/) {
			print "$_\n";
		} elsif (/ANS_(.+)=(.+)/) {
			my ($var,$val) = ($1,$2);
			if ($source =~ /(dvb|freeboxtv)/) {
				$setting{$var} = $val;
			}
		} elsif (/ID_VIDEO_WIDTH=(.+)/) {
			$width = $1;
		} elsif (/ID_VIDEO_HEIGHT=(.+)/) {
			$height = $1;
		} elsif (/ID_LENGTH=(.+)/) {
			$length = $1;
		} elsif (/ID_START_TIME=(.+)/) {
			$start_pos = $1;
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
			check_eof() if (/ID_SIGNAL=(6|11)/);
		} elsif (/End of file/i) {
			$exit .= $_;
		} elsif (/ICY Info/) {
			my $info = "";
			$stream = 1;
			my $icy_ok = undef;
			while (s/([a-z_]+)\=\'(.*?)\'\;//i) {
				my ($name,$val) = ($1,$2);
				if ($name eq "StreamTitle" && $val) {
					$val =~ s/\.\.\. Telech.+//; # vire les pubs de hotmix
					$val =~ s/ \|.+//; # vire les sufixes hotmix
					$val =~ s/\(WR\) //; # vire ce truc de rfm enfoir�s...
					$val =~ s/\+/ /g if ($serv =~ /ouifm\.ice/); # !!! y a vraiment n'importe quoi des fois !
					if ($val !~ /^ *\- *$/ && $val !~ /^<.+>$/ && $val !~ /^\d+ \- \d+$/ && $val !~ /RFI \d+/) { # sp�cialit� mfm : " - " ou "<html>" !
						# $val = utf($val);
						$info .= "$val ";
						$lyrics = 0 if ($titre ne $val);
						$titre = $val;
						print "re�u par icy info: $val.\n";
						$icy_ok = 1;
						if ($prog && $time_prog) {
							undef $prog,$time_prog;
							print "on d�sactive les updates par prog dans ce cas l�...\n";
						}
						get_lyrics($artist,$titre) if (!$lyrics);
						if (!$net) {
							$info .= " pas de r�seau)";
						} elsif (!$images) {
							$info .= " (pas de WWW::Google::Images)";
						}
					}
				} elsif ($val && $name !~ /^(StreamUrl|adw_ad|durationMilliseconds|insertionType|metadata)/) {
					$info .= " + $name=\'$val\' ";
				}
			}
			$info =~ s/ *$//;
			if ($info && $icy_ok) {
				push @tracks,$info;
				out::send_cmd_info("tracks\n".join("\n",reverse @tracks));
				if ($images && $titre =~ /\-/ && $titre ne $old_titre) {
					handle_images($titre) ;
				} else {
					$titre = $old_titre;
				}
			}
		} elsif (/Title: (.+)/i && !$titre) {
			print "filter: update Title: $1\n";
			$titre = $1;
			if ($artist && $titre) {
				out::send_cmd_info("tracks\n$artist - $titre\n");
				handle_images("$artist - $titre");
			}
		} elsif (/Artist: (.+)/i || /ID_CDDB_INFO_ARTIST=(.+)/) {
			$artist = $1;
			if ($artist && $titre) {
				out::send_cmd_info("tracks\n$artist - $titre\n");
				handle_images("$artist - $titre");
			}
		} elsif (/ID_CDDB_INFO_TRACK_(\d+)_NAME=(.+)/) {
			$list[$1] = ($list[$1] ? $list[$1] : "").utf($2);
		} elsif (/ID_CDDB_INFO_TRACK_(\d+)_MSF=(.+)/) {
			$duree[$1] = $2;
		} elsif (/Album: (.+)/i || /ID_CDDB_INFO_ALBUM=(.+)/) {
			$album = utf($1);
		} elsif (/ID_CDDA_TRACK=(\d+)/) {
			next if ($last_track && $last_track == $1);
			$last_track = $1;
			$titre = $list[$1];
			print "filter: cddb: on prend titre = $titre artist $artist\n";
			my $f;
			unlink("current");
			if (open($f,">current")) {
				print $f "$titre ($duree[$1])\ncd/$artist - $album\ncddb://$1-99\n\n\ncddb://$1-99\n";
				close($f);
				print "filter: current updated on cdda info\n";
				$chan = "$titre ($duree[$1])";
				send_cmd_prog();
				out::send_cmd_fifo("sock_list","reset_current");
			}
			handle_images("$artist - $titre") if ($titre); # ($album)")
		} elsif (!$stream && /^A:[ \t]*(.+?) \((.+?)\..+?\) of (.+?) \((.+?)\)/) {
			my ($t1,$t2,$t3,$t4) = ($1,$2,$3,$4);
			$pos = $t1; # bookmark (podcast...)
			if ($t1 - $last_t >= 1) {
				$last_t = $t1;
				if (!$artist && !$titre && $source =~ /Fichiers/ && $args[1] =~ /ogg$/i) {
					# La lecture des tags vorbis est gravement bugu�e dans
					# mplayer, un truc � patcher un de ces 4 �ventuellement
					# mais on peut peut-�tre utiliser le module perl +
					# simple...
					my $ogg = Ogg::Vorbis::Header->new($args[1]);
					($artist) = $ogg->comment("ARTIST");
					($artist) = $ogg->comment("artist") if (!$artist);
					($titre) = $ogg->comment("TITLE");
					($titre) = $ogg->comment("title") if (!$titre);
					out::send_cmd_info("tracks\n$artist - $titre\n");
					handle_images("$artist - $titre") if ($titre && $artist); # ($album)")
				}
				if (!$artist && !$titre && $chan =~ /(.+) - (.+)\..../) {
					# D�duction de l'artiste et du titre sur le nom de fichier
					($artist,$titre) = ($1,$2);
					if ($artist =~ /\d+ \- (.+)/) { # piste - artiste
						$artist = $1;
					}
				}
				if (!$lyrics && (($artist && $titre) || $args[1] !~ /^http/)) {
					get_lyrics($artist,$titre);
				}
				# out::send_cmd_info("progress $t2 ".($t3>0 ? int($t1*100/$t3) : "-")."%");
				out::send_cmd_info("progress ".int($t1*100/$t3)."%") if ($t3>0 && -f "info_coords");
			}
		} elsif (/Starting playback/) {
			if (($source eq "dvb" || $source eq "freeboxtv") && $length) {
				print "filter: starting playback, length = $length\n";
				out::send_command("seek ".($length+$start_pos-5)." 2\n");
				if (open(F,"<$ENV{HOME}/.freebox/$serv")) {
					while (<F>) {
						chomp;
						my ($var,$val) = split / /,$_;
						$setting{$var} = $val;
						$val =~ s/yes/1/;
						$val =~ s/^no$/0/;
						out::send_command("set_property $var $val");
					}
					close(F);
				}
			}
			say "filter: start, source $source length $length";

			if ($width && $height) {
				open(F,">video_size") || die "can't write to video_size\n";
				print "filter: init video $width x $height\n";
				print F "$width\n$height\n";
				close(F);
				print "filter: envoi USR1 � $pid\n";
				out::clear("list_coords","video_coords","info_coords","numero_coords","mode_coords");
				if ($args[0] !~ /mpv/) {
					kill "USR1",$pid;
					$connected = 1;
				}
			}
			$started = 1;
			send_cmd_prog();
		} elsif (/End of file/ || /^EOF code/) {
			print "filter: end of video\n";
			if ($connected) {
				print "filter: USR2 point1\n";
				kill "USR2",$pid;
				$connected = 0;
				$started = 0;
				if ($source =~ /Fichiers vid�o/) {
					delete $bookmarks{$serv};
					sleep(1);
					out::send_cmd_fifo("sock_list","list");
				}
			}
			# A priori pas la peine d'envoyer un check_eof ici, �a va �viter
			# de fermer pr�cipitement en cas de -idle
			# check_eof();
		} elsif (!$stream && /^A:(.+?) V:.*A-V: (.+?) c/) {
			$last_pos = $pos;
			$pos = $1;
			my $delay = abs($2);
			if ($delay > 1) {
				print STDERR "filter: delay = $delay\n";
			}
			# print STDERR "pos $pos\n";
			if (!defined($start_pos)) {
				$start_pos = $pos ;
				print "start_pos = $start_pos\n";
			}
		} elsif (/No bind found for key \'(.+)\'/) {
			bindings($1);
		}
	}
}
print "filter: exit message : $exit\n";
if ($source =~ /(dvb|freebox)/ && $exit =~ /EOF/) {
	print "eof detected for $source pos $pos\n";
	if (!-d "/proc/$pid_player1") {
		print "plus de player1, on va tenter de relancer...\n";
		unlink "player1.pid";
		print "./run_mp1 \"$serv\" $flav $audio $video \"$source\" \"$name\"\n";
		system("./run_mp1 \"$serv\" $flav $audio $video \"$source\" \"$name\"");
		my $f;
		if (open($f,"<player1.pid")) {
			$pid_player1 = <$f>;
			chomp $pid_player1;
			close($f);
			print "player1 relanc�, pid $pid_player1.\n";
		} else {
			print "pas de player1.pid... !\n";
		}
	}

	if ($pid_player1 && -f "player1.pid" && -d "/proc/$pid_player1") {
		# my $newpos = $last_pos-$start_pos - 15;
		my $newpos = $last_pos - 7;
		if (time() - $start_time < 3) {
			print "Moins de 3s depuis le lancement, on attend...\n";
			my $size = (-s $args[1]);
			print "taille init $size\n";
			$size += 1024*1024;
			my $wait = 0;
			while (-s $args[1] < $size && -d "/proc/$pid_player1" && $wait < 10) {
				sleep(1);
				$wait++;
			}
			if ($wait == 10 || !(-d "/proc/$pid_player1")) {
				print "wait $wait\n";
				if (!-d "/proc/$pid_player1") {
					print "plus de player1\n"
				} else {
					print "on kille player1\n";
					kill "TERM",$pid_player1;
				}
				print "et on arr�te les frais\n";
				exit(0);
			}
		}
		print "player1 toujours l�, on boucle: $newpos !\n";
		$exit = "";
		if ($newpos > 0) {
			$bookmarks{$serv} = $newpos;
		} else {
			delete $bookmarks{$serv};
		}
		goto start;
	} else {
		print "plus de player1, on quitte\n";
	}
}

kill "USR2",$pid if ($connected);
check_eof();
