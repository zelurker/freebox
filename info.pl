#!/usr/bin/perl

# Commandes supportées
# prog "nom de la chaine"
# nextprog
# prevprog
# next/prev : fait défiler le bandeau (transmission au serveur C).
# up/down : montre les info pour la chaine suivante/précédente
# zap1 : transmet à list.pl pour zapper

use lib ".";
use strict;
use v5.10;
use POSIX qw(:sys_wait_h);
use Time::Local "timelocal_nocheck";
use Coro::LWP;
use Coro;
use LWP::Simple;
use EV;
# use Time::HiRes qw(gettimeofday tv_interval);
use records;
use lyrics;
use AnyEvent;
use AnyEvent::HTTP;
use http;

use out;
require "radios.pl";

use progs::tloisir;
# use progs::hbo;
use progs::finter;
use progs::podcasts;
use progs::files;
use progs::series;
use progs::arte;
use images;
use myutf;
use Cpanel::JSON::XS qw(decode_json);

our %info; # hash pour stocker les stream_info
our $cleared = 1;
our $to_disp;
our $latin = ($ENV{LANG} !~ /UTF/i);
our $net = out::have_net();
our ($images,$agent,@cur_images);
our $time;
our $old_titre = "";
our $has_vignettes = undef;
if ($net) {
	$images = 1;
	$agent = images->new();
}
our $have_fb = 0; # have_freebox
$have_fb = out::have_freebox() if ($net);
our $have_dvb = 1; # (-f "$ENV{HOME}/.mplayer/channels.conf" && -d "/dev/dvb");
our $reader;
my $recordings = records->new();
our (@podcast,$num_pod);


our ($lastprog,$last_chan,$last_long);
our ($channel,$long);
our @days = ("Dimanche", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi",
	"Samedi");
our ($source,$base_flux,$serv,$name);

$SIG{PIPE} = sub { print "info: sigpipe ignoré\n" };
our $fadeout;
our $refresh;

sub get_cur_name {
	# Récupère le nom de la chaine courrante
	($name,$source,$serv) = out::get_current();
	myutf::mydecode(\$source);
	myutf::mydecode(\$name);
	$source =~ s/flux\/stations\/.+/flux\/stations/;
	return (lc($name),$source,$serv);
}

sub refresh {
	if ($lastprog) {
		disp_prog($lastprog,$last_long);
	} else {
		read_stream_info(time(),"$last_chan");
	}
}

sub myget {
	# un get avec cache
	my $url = shift;
	my $name = out::get_cache($url);
	if (!$name) {
		print "info: get_name from $url returns nothing\n";
		return undef;
	}
	my $raw = undef;
	if (-f $name && !-z $name) {
		utime(undef,undef,$name);
	} else {
		async {
			if ($raw = http::myget($url,$name)) {
				refresh();
			} else {
				print "couldn't get image $url.\n";
			}
		};
	}
		return $name;
}

sub setup_fadeout {
	my $long = shift;
	if (!$long) {
		$fadeout = AnyEvent->timer(after=>5, cb =>
			sub {
				if (! -f "list_coords") {
					undef $refresh;
					out::alpha("info_coords",-40,-255,-5);
					out::send_bmovl("image");
				}
			}
		);
	} else {
		undef $fadeout;
	}
}

sub conv {
	# fonction utilitaire pour formater correctement chaine / source /
	# base_flux pour comparaison
	my $cmd = shift;
	chaines::conv_channel($cmd)."&$source" . ($base_flux ? "/$base_flux" : "");
}

sub read_stream_info {
	my ($time,$cmd,$rinfo) = @_;
	$cleared = 0;
	# Là il peut y avoir un problème si une autre source a le même nom
	# de chaine, genre une radio et une chaine de télé qui ont le même
	# nom... Pour l'instant pas d'idée sur comment éviter ça...
	if (!$rinfo) {
		# say "read_stream_info: name ",lc($name),"&$source eq conv(cmd) ",conv($cmd)," cmd $cmd";
		if (lc($name)."&$source" eq conv($cmd)) {
			$rinfo = $info{"$name&$source"};
		} else {
			# say "read_stream_info: bye";
			return;
		}
	}
	my $rtracks = $rinfo->{tracks};
	my $info = $rinfo->{codec} || "";
	my $progress = $rinfo->{progress} || "";
	my $cur = $$rtracks[0];
	my $last = $$rtracks[1];
	$cur = "" if (!$cur); # Evite le warning de manip d'undef
	my $pic = "";
	if ($cur =~ s/pic:(http.+?) //) {
		$pic = $1;
	}
	my $pics = "";
	if ($source eq "flux" && $base_flux =~ /^stations/) {
		$pics = get_radio_pic($cmd);
	}
	if ($pic) {
		$pic = myget $pic || "";
		$last =~ s/pic:(http.+?) // if ($last);
	}
	if (1) { # $info) {
		my $out = out::setup_output("bmovl-src/bmovl","",$long);
		if ($out) {
			print $out "$pics\n$pic\n";
			my ($sec,$min,$hour) = localtime($time);

			myutf::mydecode(\$cmd);
			$cmd = substr($cmd,0,50)."..." if (length($cmd) > 50);
			print $out "$cmd ($info) : ".sprintf("%02d:%02d:%02d",$hour,$min,$sec);
			if ($cur) {
				print $out "\n$cur $progress\n";
			} else {
				print $out " $progress\n\n";
			}
			print $out "Dernier morceau : $last\n" if ($last && $source !~ /^Fichiers/);
			print $out "Paroles : $rinfo->{lyrics}" if ($rinfo->{lyrics});
			print $out $rinfo->{metadata}->{title} if ($rinfo->{metadata}->{title} && !$rinfo->{metadata}->{artist});
			out::close_fifo($out);
			setup_fadeout($long);
		}
		$last_chan = $channel;
	}
}

mkdir "cache" if (! -d "cache");
mkdir "chaines" if (! -d "chaines");

#
# Constants
#

open(F,">info_pl.pid");
print F "$$\n";
close(F);

my ($sec,$min,$hour,$mday,$mon,$year) = localtime();
my $date = sprintf("%02d/%02d/%d",$mday,$mon+1,$year+1900);

sub get_time {
	# Et là renvoie une heure à partir d'un champ time()
	my $time = shift;
	return "-" if (!$time);
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime($time);
	# sprintf("%d/%02d/%02d %02d:%02d:%02d $tz",$year+1900,$mon,$mday,$hour,$min,$sec);
	sprintf("%02d:%02d:%02d",$hour,$min,$sec);
}

my @prog;
if ($have_dvb || $have_fb) {
	push @prog, progs::tloisir->new($net);
}
push @prog, progs::finter->new($net);
push @prog, progs::podcasts->new($net);
push @prog, progs::files->new($net);
push @prog, progs::series->new($net);
push @prog, progs::arte->new($net);
# push @prog, progs::hbo->new($net);

# read_prg:
my $path = "sock_info";
# Ouais génial, sig{term} est intercepté par anyevent donc faut passer par
# ça, et passer un guard au serveur est compliqué (pas trouvé)
our $fin = AnyEvent->signal( signal => "TERM", cb => sub { print "info: on vire les fichiers\n"; unlink $path; unlink "info_pl.pid"; exit(0); });
our $server = out::setup_server($path,\&commands);
my $nb_days = 1;
my $cmd;
my $last_hour = 0;

my $read_before = undef;
($channel,$long) = ();
# my $timer_start;
# la partie à intégrer un de ces 4 dans les timers d'AnyEvent ça sera les
# enregistrements, adapter ce truc :
#		$delay = $recordings->get_delay($time,$delay);
EV::run;

sub disp_duree($) {
	my $duree = shift;
	if ($duree < 60) {
		int($duree)."s";
	} elsif ($duree < 3600) {
		sprintf("%d min",$duree/60);
	} else {
		my $h = sprintf("%d",$duree/3600);
		if ($h > 24) {
			my $d = int($h / 24);
			sprintf("$d jours, %dh%02d",$h % 24,($duree-$h*3600)/60);
		} else {
			sprintf("%dh%02d",$h,($duree-$h*3600)/60);
		}
	}
}

sub disp_prog {
	$cleared = 0;
	my ($sub,$long,$podcast) = @_;
	if (!$sub) {
		print "info: disp_prog sans sub !\n";
		return;
	}
	encoding($sub);
	$prog[$reader]->valid($sub,\&refresh);
	$lastprog = $sub;
	$last_chan = $$sub[1];
	my $start = $$sub[3];
	my $end = $$sub[4];
	my @date = ($$sub[12] ? split('/', $$sub[12]) : "");
	my $date = timelocal_nocheck(0,0,12,$date[0],$date[1]-1,$date[2]-1900);
	my ($sec,$min,$hour,$mday,$mon,$year,$wday) = localtime($date);
	my $time;
	if ($last_chan eq "podcasts" || $podcast) {
		$time = $start;
	} else {
		$time = time();
	}
	my $reste = undef;
	if ($start && $time >= $start && $time < $end) {
		$reste = $end-$time;
		my $source0 = $source;
		$refresh = AnyEvent->timer(after=>($reste > 60 ? 60 : $reste+1), cb =>
			sub {
				# Il faut recréer $sub -> disp_channel
				disp_channel() if ($source eq $source0);
			}
		);
	} else {
		undef $refresh;
	}
	$start = get_time($start);
	$end = get_time($end);
	my $raw = 0;
	if ($$sub[9]) {
		# Prsence d'une image...
		$raw = myget $$sub[9];
	}
	# Check channel logo
	my $name = "";
	if ($net && !$raw) { # on n'affiche le logo que si on a rien d'autre
		if ($source eq "flux" && $base_flux eq "stations") {
			$name = get_radio_pic($$sub[1]);
		} else {
			$name = chaines::setup_image($$sub[0]);
		}
	}

	my $out = out::setup_output("bmovl-src/bmovl",$raw,$long);

	if (-f "video_size") { # mplayer/mpv en cours...
		my @f = out::get_current();
		if ($f[6] =~ /\.ts$/ && chaines::conv_channel($f[0]) eq lc($$sub[1])) { # on vérifie quand même que c'est bien un .ts
			# Note : habituellement avec le dvb ou une source "stable",
			# f[0] eq $$sub[1] directement, mais pas en utilisant des flux
			# web, dans ce cas là les chaines ont tout un tas de préfixes
			# qui sont préservés au niveau de la liste et qu'on retrouve
			# dans f[0] et qu'on ne peut donc pas comparer à la chaine pour
			# télérama contenue dans sub[1]
			if (open(F,">$f[6].info")) {
				print F "pic:$$sub[9] " if ($$sub[9]);
				print F "$$sub[2]\n$$sub[6]\n$$sub[7]\n";
				close(F);
			}
		}
	}
	print $out "$name\n";
	print $out $raw if ($raw);

	print $out "\n$$sub[1] : $start - $end ".
	($reste ? "reste ".disp_duree($reste) : "($days[$wday] $mday/".($mon+1)."/".($year+1900).")");

	my $tag = conv($channel);
	my $codec = $info{$tag}->{codec};
	print $out " ($codec)" if ($codec);

	$$sub[6] = "" if (!$$sub[6]);
	# Bizarrerie utf : sub[6] doit être séparé par des virgules et pas
	# directement entre les guillemets... Différence de format ?
	my $details = $$sub[6];
	my $id = $$sub[7];
	if ($id && ($source eq "flux" && $base_flux eq "stations")) {
		$$sub[7] = undef;
		mkdir "cache/finter";
		# age du cache : 1/24 parce que le podcast arrive après l'émission... et c variable en + le temps que ça prend
		# donc on met 1h tant pis
		my $sub = http::myget("https://www.radiofrance.fr/franceinter/api/grid/$id","cache/finter/$id",1/24);
		my $j = undef;
		eval {
			# ça peut foirer pour franceinfo par exemple où le prog télérama a tendance à prendre la priorité !
			$j = decode_json($sub);
		};
		foreach (@$j) {
			my $exp = $_->{expression};
			$exp = $_->{concept} if (!$exp);
			my $title = $exp->{visual}->{legend};
			next if (!$title);
			my $sdesc = $exp->{title};
			my $start = $_->{startTime};
			my $end = $_->{endTime};
			my $podcast = $_->{media}->{sources}->[0]{url};
			$sdesc .= "\npod:$podcast" if ($podcast);
			my ($ssec,$smin,$shour) = localtime($start);
			my ($esec,$emin,$ehour) = localtime($end);
			myutf::mydecode(\$title);
			myutf::mydecode(\$sdesc);
			$details .= sprintf("\n%d:%02d : $title - $sdesc",$shour,$smin);
		}
	}
	@podcast = ();
	my $n = 0;
	while ($details =~ s/pod:(http.+)/"podcast ".($n == $num_pod ? "(b)" : "(n,N)")/e) {
		push @podcast,$1;
		$n++;
	}

	print $out "\n$$sub[2]\n\n",$details,"\n$$sub[7]\n";
	print $out "$$sub[11]\n" if ($$sub[11]); # Critique
	if ($$sub[10]) {
		if ($$sub[10] =~ /^\d+$/) {
			print $out "*"x$$sub[10] if ($$sub[10]); # Etoiles
		} else {
			print $out $$sub[10];
		}
	}
	out::close_fifo($out);
	setup_fadeout($long);
	$last_long = $long;
	$$sub[7] = $id;
#	print "last_long = $last_long from disp_prog\n";
}

sub commands {
	my $fh = shift;
	$cmd = shift;
	# interception d'un double encodage utf8, ça arrive quand un tag est
	# encodé en utf8, mpv lui réapplique un encodage. Je vais pas m'amuser
	# à tout filtrer, ça reste rare, celui là est pour le é, codé en utf8
	# ça fait c3 a9, mis sous forme de codes pour être certain que c'est ce
	# qu'on veut
	$cmd =~ s/\xc3\x83\xc2\xa9/\xc3\xa9/g;
	myutf::mydecode(\$cmd);
	my @tab = split(/ /,$cmd);
	my $old_long = $long;
	($tab[0],$long) = split(/\:/,$tab[0]);
	$cmd = join(" ",@tab);
	$long = "" if (!defined($long)); # Evite les warnings !
	# A priori utile juste pour prog
	$long = $old_long if ($cmd !~ /^prog /);

	print "info: reçu commande $cmd long:$long.\n" if ($cmd !~ /^progress/);
	# for (my $n=0; $n<length($cmd); $n++) {
	# 	print sprintf("%02x ",ord(substr($cmd,$n,1)));
	# }
	# print "\n";
	if ($cmd eq "clear") {
		$fadeout = $refresh = undef;
		out::clear("info_coords");
		$cleared = 1;
		say "bmovl::image";
		out::send_bmovl("image");
	} elsif ($cmd =~ /^switch_mode (.+)/) {
		$source = $1;
		$base_flux = undef;
		$refresh = undef;
	} elsif ($cmd eq "podcast") {
		if (@podcast && $num_pod <= $#podcast) {
			my $podcast = $podcast[$num_pod];
			if ($podcast =~ /transistor/) { # la façon 2026 d'inter de passer des podcasts : de + en + de requêtes indirectes supplémentaires !
				my ($id) = $podcast =~ /.+\/(.+)/;
				my $json2 = http::myget($podcast,"cache/".$id,7);
				if ($json2) {
					eval {
						$json2 = decode_json($json2);
					};
					if ($@) {
						say "json2 decoding failed: $@";
					} else {
						$podcast = $json2->{sources}[0]->{url}; # on se fiche à priori de savoir si c du m4a ou du mp3 ou autre chose
						$podcast[$num_pod] = $podcast;
						$info{"$name&$source"}->{podcast} = 1;
					}
				}
			}
			out::send_cmd_list("open $podcast[$num_pod]");
		}
	} elsif ($cmd eq "nextpod") {
		if ($num_pod < $#podcast) {
			$num_pod++;
		} else {
			$num_pod = 0;
		}

		disp_prog($lastprog,$last_long) if ($lastprog);
	} elsif ($cmd eq "prevpod") {
		if ($num_pod > 0) {
			$num_pod--;
		} else {
			$num_pod = $#podcast;
		}
		disp_prog($lastprog,$last_long) if ($lastprog);
	} elsif ($cmd =~ s/^unload //) {
		# envoyé par le script lua de mpv pour indiquer qu'il quitte
		if ($source =~ /^flux\/podcasts/) {
			# le nom du fichier est renvoyé par la commande unload,
			# pratique pour les cas indirects comme les podcasts !
			utime(undef,undef,$cmd);
		}
		say "images arrêtées sur unload";
		$time = undef;
	} elsif ($cmd eq "tracks") {
		my ($name,$src) = get_cur_name();
		$name .= "&$src";
		my @tracks = ();
		my $rtracks = $info{$name}->{tracks};
		while (<$fh>) {
			chomp;
			if ($_) {
				myutf::mydecode(\$_);
				push @tracks,$_ ;
			}
		}
		close($fh);
		my $same = 0;
		if ($rtracks && $#$rtracks == $#tracks) {
			$same = 1;
			for (my $n=0; $n<=$#tracks; $n++) {
				if ($tracks[$n] ne $$rtracks[$n]) {
					$same = 0;
					last;
				}
			}
		}
		if (!$same && $#tracks > -1) {
			$info{$name}->{tracks} = \@tracks;
			if (!$cleared && $name eq conv($channel)) {
				read_stream_info(time(),$channel,$info{$name});
			}
		}
	} elsif ($cmd =~ /^metadata (.+?) (.+)/) {
		my ($i,$v) = ($1,$2);
		$i = lc($i); # tsss... !
		$v =~ s/\xc2\x92/'/g;
		$v =~ s/\xc3\x83\xc2\xaa/\xc3\xaa/g; # double encodage du ê, parce que mpv refuse les tags en utf8 et les ré-encode systématiquement !
		$v =~ s/\xc3\x83\xc2\xa8/\xc3\xa8/g; # pareil pour le è
		$v =~ s/\xc3\x83\xc2\xb9/\xc3\xb9/g; # et le ù
		$v =~ s/\xc3\x85\xc2\x93/\xc5\x93/g; # oe
		my ($name,$src,$serv) = get_cur_name();
		my $name0 = $name;
		$name .= "&$src";
		$info{$name}->{metadata}->{$i} = $v;
		say "metadata $i = $v";
		if ($i =~ /^icy-title/i && ($v =~ /(.+) - (.+)/ ||
				$v =~ /(.+) \xc3\x8b\xc2\x97 (.+)/)) {
			my ($artist,$title) = ($1,$2);
			if (!($artist =~ /^\d+/ && $title =~ /^\d+$/) && # délire chérie fm
				$artist !~ /^nrjaudio/) { # nostalgie
				say "icy-title: artist:$artist title:$title";
				$title =~ s/\|.+//; # y a des numéros bizarres intercalés par des || sur hotmix
				$info{$name}->{metadata}->{artist} = $artist;
				$info{$name}->{metadata}->{title} = $title;
			}
		} elsif ($i =~ /^icy-title/i) {
			for (my $n=0; $n<=length($v); $n++) {
				say substr($v,$n,1)," ",ord(substr($v,$n,1));
			}
		}

		if ($info{$name}->{metadata}->{artist} && $info{$name}->{metadata}->{end} &&
			$info{$name}->{metadata}->{title}) {
			my @track = ($info{$name}->{metadata}->{artist}." - ".$info{$name}->{metadata}->{title});
			if (!$info{$name}->{tracks}) {
				$info{$name}->{tracks} = \@track;
			} else {
				return if (${$info{$name}->{tracks}}[0] eq $track[0] && $source !~ /^Fichiers/);
				unshift @{$info{$name}->{tracks}},@track;
			}
			if (!$info{$name}->{podcast}) {
				# say "channel was $channel";
				$channel = $name0;
				# say "channel $channel = name0 $name0";
			}
			# le source = $src ici crée la merde quand on lit un podcast à partir de france inter dans flux/stations, on va essayer sans pour voir...
			# $source = $src;
			if ($channel ne $last_chan && $channel ne "flux") {
				$lastprog = undef; # channel eq "flux" -> podcast direct par touche b
				say "lastprog = undef on channel $channel ne last_chan $last_chan";
			}
			if ($info{$name}->{metadata}->{genre} !~ /podcast/i && !$info{$name}->{metadata}->{podcast} && !$info{$name}->{metadata}->{copyright} =~ /Radio/i) {
				# fourni par finter au moins, bah sinon on fera une requête
				# pour rien... !
				my $lyrics = lyrics::get_lyrics($serv,$info{$name}->{metadata}->{artist},$info{$name}->{metadata}->{title});
				myutf::mydecode(\$lyrics);
				$info{$name}->{lyrics} = $lyrics;
			}
			if (!grep($serv eq $_,@podcast)) {
				my ($name,$source,$serv) = out::get_current();
				if ($lastprog) {
					disp_prog($lastprog,$last_long);
				} else {
					# say "appel read_stream_info name $name source $source";
					read_stream_info(time(),$name,$info{$name});
				}
			}
			say "test image...";
			if ($info{$name}->{metadata}->{genre} =~ /podcast/i && !$info{$name}->{metadata}->{podcast} && $info{$name}->{metadata}->{album}) {
				my $title = lyrics::pure_ascii($info{$name}->{metadata}->{title});
				say "cas 1 d'images";
				if (handle_images($info{$name}->{metadata}->{album}." - $title") ||
					handle_images($title) ||
					handle_images($info{$name}->{metadata}->{album})) {
				}
			} elsif ($info{$name}->{metadata}->{artist} && $info{$name}->{metadata}->{title}) {
				say "cas 2 d'images : ",$info{$name}->{metadata}->{artist}." - ".$info{$name}->{metadata}->{title};
				handle_images($info{$name}->{metadata}->{artist}." - ".$info{$name}->{metadata}->{title});
			}
		} elsif ($info{$name}->{metadata}->{end} &&	$info{$name}->{metadata}->{title}) { # cas des chapitres matroshka
			say "cas read_stream_info";
			read_stream_info(time(),$channel,$info{$name});
		}
	} elsif ($cmd =~ /^codec/) {
		my ($codec,$bitrate);
		($cmd,$codec,$bitrate) = split / /,$cmd;
		$info{"$name&$source"}->{codec} = "$codec $bitrate";
		if (!$info{"$name&$source"}->{metadata}->{artist} && !$info{"$name&$source"}->{lyrics} && $serv !~ /^http/ && $serv =~ /(mp3|ogg)$/i &&
		!$info{"$name&$source"}->{lyrics_sent}) { # normalement on reçoit les tags avant le codec...
			say "got name $name&$source src $source serv $serv et pas de tags, on y va... !";
			$info{"$name&$source"}->{lyrics_sent} = 1; # surtout utile quand la cxion est lente et que la réponse met longtemps à arriver
			# mais ça peut être TRES utile dans certains cas avec le vpn !
			my $lyrics = lyrics::get_lyrics($serv);
			if ($lyrics) {
				$serv =~ s/^.+\///;
				$serv =~ /^(.+) ?\- ?(.+)\./;
				$info{"$name&$source"}->{metadata}->{artist} = $1;
				$info{"$name&$source"}->{metadata}->{title} = $2;
				myutf::mydecode(\$lyrics);
				$info{"$name&$source"}->{lyrics} = $lyrics;
			}
		}
		# say "codec: $name&$source eq conv(channel) ",conv($channel);
		if (!$cleared && (!$channel || lc($name)."&$source" eq conv($channel) || $info{"$name&$source"}->{podcast})) {
			#			&& $source !~ /^flux\/podcasts/ && !$info{"$name&$source"}->{progress}) {
			# say "affichage codec";
			if (!grep($serv eq $_,@podcast)) {
				# say "et sans les podcasts";
				# petit hack sur $channel eq "flux" pour avoir un affichage stable
				# quand on déclenche un podcast à partir du bandeau d'info...
				if ($lastprog && $channel eq $last_chan || $channel eq "flux") {
					# say "codec appelle disp_prog";
					disp_prog($lastprog,$last_long,$info{"$name&$source"}->{podcast});
				} else {
					# say "codec appelle read_stream_info channel $channel";
					read_stream_info(time(),$channel,$info{"$name&$source"});
				}
			}
		}
	} elsif ($cmd =~ s/^progress //) {
		# La commande progress avait comme paramètre quoi afficher dans le
		# champ progress à l'époque de mplayer, maintenant elle a en brut
		# la position et la durée, les 2 en secondes
		my ($pos,$dur) = split(/ /,$cmd);
		# au niveau du lua on ne peut pas savoir si un flux doit ou pas
		# envoyer progress, on ne peut le bloquer qu'ici...
		# return if ($src =~ /^flux\/(stations|ecoute_directe|freetuxtv)/);
		if (!$cleared && ($info{"$name&$source"}->{podcast} || (lc($name)."&$source" eq conv($channel) && ($source =~ /^(Fichiers son)/ || $serv =~ /podcast/ )) )) {
			if ($lastprog) {
				$$lastprog[3] = timelocal_nocheck($pos,0,0,$mday,$mon,$year);
				$$lastprog[4] = timelocal_nocheck($dur,0,0,$mday,$mon,$year);
				disp_prog($lastprog,$last_long,$info{"$name&$source"}->{podcast});
			} else {
				$pos = sprintf("%02d:%02d:%02d",$pos/3600,($pos/60)%60,$pos%60);
				$dur = sprintf("%02d:%02d:%02d",$dur/3600,($dur/60)%60,$dur%60);
				$info{"$name&$source"}->{progress} = "$pos - $dur";
				read_stream_info(time(),$channel,$info{"$name&$source"});
			}
		}
	} elsif ($cmd =~ /^lyrics/) {
		my ($name,$src) = get_cur_name();
		$name .= "&$src";
		my $lyrics = "";
		while (<$fh>) {
			$lyrics .= $_;
		}
		$fh->close();
		$info{$name}->{lyrics} = $lyrics;
        # on reçoit des lyrics pour les podcasts des fois quand le mp3
        # contient des tags, radio france le fait. On élimine l'affichage
        # pour ça.
		if (!$cleared && $name eq conv($channel) && $src !~ /^flux\/podcasts/) {
			read_stream_info(time(),$channel,$info{$name});
		}
	} elsif ($cmd eq "time") {
		if (-e "mpvsocket") {
			out::send_command("show-text ".get_time(time())." 3000\n");
		} else {
			out::send_command("osd_show_property_text ".get_time(time())." 3000\n");
		}
	} elsif ($cmd eq "sensors") {
		open(F,"sensors |");
		my @temp;
		while (<F>) {
			chomp;
			push @temp,$1 if (/([\d\.]+..C)/);
		}
		close(F);
		if (-e "mpvsocket") {
			out::send_command("show-text \"wifi $temp[0] cpu $temp[2]\" 8000\n");
		}
	} elsif ($cmd eq "nextprog" || $cmd eq "right") {
		undef $refresh;
		undef @podcast;
		disp_prog($prog[$reader]->next($last_chan),$last_long);
	} elsif ($cmd eq "prevprog" || $cmd eq "left") {
		undef $refresh;
		undef @podcast;
		disp_prog($prog[$reader]->prev($last_chan),$last_long);
	} elsif ($cmd =~ /^(next|prev)$/) {
	    # Ces commandes sont juste passées à bmovl sans rien changer
	    # mais en passant par ici ça permet de réinitialiser le timeout
	    # de fondu, plutôt pratique...
		out::send_bmovl($cmd);
	} elsif ($cmd =~ /^(up|down)$/) {
		$cmd = out::send_list(($cmd eq "up" ? "next" : "prev")." $last_chan");
		$channel = $cmd if (!$info{"$name&$source"}->{podcast});
		print "got channel :$channel from up/down.\n";
		$long = $last_long;
	} elsif ($cmd eq "zap1") {
		out::send_list("zap2 $last_chan");
	} elsif ($cmd =~ s/^prog //) { # on vire le prog, garde que la chaine
		# Note : $long est passé collé à la commande par un :
		# mais il est séparé avant même l'interprêtation, dès la lecture
		# Nouvelle syntaxe prog[:long] chaine&source/base_flux[|serv]
		# ça devient obligatoire d'avoir la source liée à ça avec toutes les
		# sources de programmes maintenant
		# Note sur la regex : le 1er (.+) sert à être sûr qu'on prend la
		# chaine la + longue, au cas où le nom de fichier contient un &
		# le [A-Za-z] est pour éviter les collisons avec le & dans un
		# titre, généralement y a un espace après
		# J'aurais jamais du choisir & comme séparateur !!!
		$cmd =~ s/(.+)&([A-Za-z].+)/$1/;
		$source = $2;
		if ($source =~ s/\/(.+)//) {
			$base_flux = $1;
			$base_flux =~ s/^stations\/.+/stations/;
			$base_flux =~ s/\|(.+)//;
			$serv = $1;
		} else {
			$base_flux = "";
			$source =~ s/\///;
			$serv = "";
		}
		$channel = $cmd;
		# say "fin de prog: channel $channel name $name source $source base_flux $base_flux";
		# say "fin de prog: channel $channel name $name source $source base_flux $base_flux";
		# Note : prog appelle disp_channel pour recalculer le programme
		# pas disp_prog qui réaffiche un programme qu'on a déjà !
		disp_channel();
	} elsif ($cmd eq "record") {
		out::clear("info_coords") if (-f "info_coords");
		out::clear("list_coords") if (-f "list_coords");
		$recordings->add($lastprog);
	} else {
		print "info: commande inconnue $cmd\n";
	}
}

sub encoding {
	my $sub = shift;
	foreach (1,2,6,7,11) {
		my $ref = \$$sub[$_];
		if (!$$ref) {
			$$ref = "";
			next;
		}
		myutf::mydecode($ref);
	}
}

sub disp_channel {
# Ici on a obtenu la chaine, on cherche un afficheur
	chomp $channel;
	chomp $long if ($long);
	my ($name,$src) = get_cur_name();
	$name .= "&$src";
	$cleared = 0;
	$fadeout = $refresh = undef;
	print "disp_channel: entrée avec channel=$channel long:$long\n";

	$to_disp = $channel;
	my $sub = undef;
# 1 les trucs spécialisés (séries, radios, etc).
	for (my $n=$#prog; $n>=0; $n--) {
		$sub = $prog[$n]->get($channel,$source,$base_flux,$serv);
		if ($sub) {
			$reader = $n;
			last;
		} elsif ($prog[$n]->{err}) { # il renvoie rien, mais y a une erreur !
			my $out = out::setup_output("bmovl-src/bmovl","",$long);
			($sec,$min,$hour) = localtime(time());
			print $out "\n\n";
			print $out "$cmd : ".sprintf("%02d:%02d:%02d",$hour,$min,$sec),"\n";
			print $out "Erreur : ",$prog[$n]->{err},"\n";
			out::close_fifo($out);
			setup_fadeout($long);
			return;
		}
	}
	$lastprog = undef;
# 2 l'afficheur de base pour les fichiers (stream_info)
	if (!$sub) {
		# say "disp_channel: name $name eq conv(channel) ",conv($channel);
		if ($name eq conv($channel)) {
			# say "read_stream_info from disp_channel";
			read_stream_info(time(),$channel,$info{"$name"});
			return;
		}
	}

# 3 affichage par défaut, peut quand même y avoir des paroles des fois !
	if (!$sub) {
		# Pas trouvé la chaine
		# say "disp_channel: par défaut";
		my $time = time();
		my $out = out::setup_output("bmovl-src/bmovl","",$long);
		$cmd =~ s/pic:(.+?) //;
		my $pic = $1;
#	my $src = out::send_list("info ".lc($cmd));
#	$src =~ s/,.+//;
		if ($source eq "flux/stations") {
			$pic = get_radio_pic($cmd);
		}
		print $out "$pic\n\n";
		($sec,$min,$hour) = localtime($time);
		myutf::mydecode(\$cmd);
		say "*** affichage après decode: $cmd";

		print $out "$cmd : ".sprintf("%02d:%02d:%02d",$hour,$min,$sec),"\n";
#		if (-f "stream_lyrics") {
#			disp_lyrics($out);
#		} else {
			print $out "Aucune info\n";
#		}
		out::close_fifo($out);
		setup_fadeout($long);
		$last_chan = $channel;
		return;
	}

	# Si on arrive là, on a le texte à afficher dans sub, y a plus qu'à y
	# aller !
	disp_prog($sub,$long,$info{$name}->{podcast}) if ($sub && $to_disp eq $channel);
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
		$ext = substr($ext,0,3); # On ne garde que les 3 1ers caractères !
		$name .= ".$ext";
		if (-f $name) {
			utime(undef,undef,$name);
			out::send_bmovl_utf("image $name");
		} else {
			my $referer = $url;
			$referer =~ s/(.+)\/.+?$/$1\//;
			print "get image $url, referer $referer\n";
			http_get $url,headers => { "referer" => $referer },sub {
				my ($body,$hdr) = @_;
				if ($hdr->{Status} =~ /^2/) { # ok
					open(F,">$name");
					print F $body;
					close(F);
					$pic = $name;
					my $ftype = `file \"$pic\"`;
					chomp $ftype;
					if ($ftype =~ /gzip/) {
						print "gzip content detected\n";
						rename($pic,"$pic.gz");
						system("gunzip $pic.gz");
						$ftype = `file \"$pic\"`;
						chomp $ftype;
					}
					if ($ftype =~ /error/i || $ftype =~ /HTML/) {
						unlink "$pic";
						print "filter: type image $ftype\n";
						handle_images();
						return;
					}
					out::send_bmovl_utf("image $pic");
				} else {
					handle_images();
				}
			};
		}
		say "images 25s";
		$time = AnyEvent->timer(after => 25,
			interval => 25,
			cb => sub { say "cb handle_images"; handle_images(); });
	} else {
		out::send_bmovl("vignettes") if ($has_vignettes);
		say "images: plus d'images, arrêt du timeout";
		$time = undef;
	}
}

sub handle_images {
	my $cur = shift;
	$cur = $old_titre if (!$cur);
	$old_titre = $cur;
	say "appel handle_images";
	say "handle_images: pas de réso" if (!$net);
	return if (!$net);
	if (!@cur_images || $cur_images[0] ne $cur) {
		say "handle_images reset";
		# Reset de la recherche précédente si pas finie !
		if ($cur_images[1]) {
			my $result = $cur_images[1];
		}

		@cur_images = ($cur);
		$cur =~ s/û/u/g; # Pour une raison inconnue allergie !
		my $res = $agent->search($cur);
#		open(F,">vignettes");
#		foreach (@$res) {
#			print F $_,"\n";
#		}
#		close(F);
		# $has_vignettes = 1;
		# out::send_bmovl("vignettes") if ($has_vignettes);
		my $result = $agent->{tab};
		for (my $n=0; $n<=$#$result; $n++) {
			if ($$result[$n]->{imgurl} =~ /alamy/) {
				delete $$result[$n];
				redo;
			}
			for (my $x=0; $x<$n; $x++) {
				# Le tbnid semble être une identification de l'image en filtrant les espaces, sert à éliminer les doublons pour les sites qui ont plusieurs fois la même image
				# dans plusieurs résolutions !
				if ($$result[$x]->{tbnid} eq $$result[$n]->{tbnid}) {
					delete $$result[$n];
					last;
				}
			}
		}
		say "handle_images: $#$result images";
		return 0 if ($#$result == -1);
		push @cur_images,$result;
		handle_result($result);
	} else {
		my $result = $cur_images[1];
		handle_result($result);
	}
	return 1;
}

