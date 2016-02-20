#!/usr/bin/perl

# Commandes supportées
# prog "nom de la chaine"
# nextprog
# prevprog
# next/prev : fait défiler le bandeau (transmission au serveur C).
# up/down : montre les info pour la chaine suivante/précédente
# zap1 : transmet à list.pl pour zapper

use strict;
use warnings;
use POSIX qw(:sys_wait_h);
use Time::Local "timelocal_nocheck";
use LWP::Simple;
# use Time::HiRes qw(gettimeofday tv_interval);
use records;

use out;
require "radios.pl";

use progs::telerama;
use progs::nolife;
use progs::finter;
use progs::labas;
use progs::podcasts;
use progs::files;
use progs::series;
use progs::youtube;
use progs::arte;

our $net = out::have_net();
our $have_fb = 0; # have_freebox
$have_fb = out::have_freebox() if ($net);
our $have_dvb = 1; # (-f "$ENV{HOME}/.mplayer/channels.conf" && -d "/dev/dvb");
our $reader;
my $recordings = records->new();

our @cache_pic;
our ($lastprog,$last_chan,$last_long);
our ($channel,$long);
my $time_refresh = 0;
our @days = ("Dimanche", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi",
	"Samedi");
our ($source,$base_flux,$serv);

$SIG{PIPE} = sub { print "info: sigpipe ignoré\n" };
my $start_timer = 0;

sub get_cur_name {
	# Récupère le nom de la chaine courrante
	my ($name) = out::get_current();
	return lc($name);
}

sub get_stream_info {
	my ($cur,$last,$info);
	my $tries = 3;
	while ($tries-- > 0 && !(-s "stream_info")) {
		select undef,undef,undef,0.1;
	}
	if (open(F,"<stream_info")) {
		my $info = <F>;
		if (!$info) {
			print "info nulle, on recommence\n";
			close(F);
			open(F,"<stream_info");
			$info = <F>;
		}
		chomp $info;
		while (<F>) {
			chomp;
			$last = $cur;
			$cur = $_;
		}
		$last =~ s/pic\:.+? // if ($last);
		close(F);
		return ($cur,$last,$info);
	}
	undef;
}

sub myget {
	# un get avec cache
	my $url = shift;
	my $name = out::get_cache($url);
	my $raw = undef;
	if (-f $name && !-z $name) {
		utime(undef,undef,$name);
		return $name;
	} else {
		my $pid = fork();
		if ($pid) {
			push @cache_pic,[$pid,$last_chan,$last_long,$name];
			return $name;
		} else {
			if ($raw = get $url) {
				if (open(F,">$name")) {
					syswrite(F,$raw,length($raw));
					close(F);
				}
			} else {
				print "couldn't get image $url\n";
			}
			exit(0);
		}
	}
}

sub read_stream_info {
	my ($time,$cmd) = @_;
	# Là il peut y avoir un problème si une autre source a le même nom
	# de chaine, genre une radio et une chaine de télé qui ont le même
	# nom... Pour l'instant pas d'idée sur comment éviter ça...
	my ($cur,$last,$info) = get_stream_info();
	$cur = "" if (!$cur); # Evite le warning de manip d'undef
	$cur =~ s/pic:(http.+?) //;
	my $pic = $1;
	my $pics = "";
	if ($source eq "flux" && $base_flux =~ /^stations/) {
		$pics = get_radio_pic($cmd);
	}
	if ($pic) {
		$pic = myget $pic;
		$last =~ s/pic:(http.+?) //;
	} else {
		$pic = "";
	}
	if ($info) {
		my $out = out::setup_output("bmovl-src/bmovl","",0);
		if ($out) {
			print $out "$pics\n$pic\n";
			my ($sec,$min,$hour) = localtime($time);

			print $out "$cmd ($info) : ".sprintf("%02d:%02d:%02d",$hour,$min,$sec),"\n$cur\n";
			print $out "Dernier morceau : $last\n" if ($last);
			out::close_fifo($out);
			if (!$long) {
				$start_timer = $time+5 if ($start_timer < $time);
				print "init start_timer $start_timer / $time\n";
			} else {
				$start_timer = 0;
				print "reset start_timer\n";
			}
		}
		$last_chan = $channel;
	}
}

mkdir "cache" if (! -d "cache");
mkdir "chaines" if (! -d "chaines");

sub REAPER {
	my $child;
	# loathe SysV: it makes us not only reinstate
	# the handler, but place it after the wait
	$SIG{CHLD} = \&REAPER;
	while (($child = waitpid(-1,WNOHANG)) > 0) {
		print "info: child $child terminated\n";
# 		if (! -f "info_coords") {
# 			print "plus d'info_coords, bye\n";
# 			return;
# 		}
		for (my $n=0; $n<=$#cache_pic; $n++) {
			while (!$cache_pic[$n][0]) {
				print "pas encore de pid pour cache_pic $n\n";
				sleep(1);
			}
			if ($child == $cache_pic[$n][0] && $last_chan eq $cache_pic[$n][1] &&
			   	(!$last_long || $last_long eq $cache_pic[$n][2]) &&
			   	-f $cache_pic[$n][3]) {
				# L'image est arrivée, réaffiche le bandeau d'info alors
				if ($lastprog) {
					disp_prog($lastprog,$last_long);
				} else {
					read_stream_info(time(),"$last_chan");
				}
				splice @cache_pic,$n,1;
				last if ($n > $#cache_pic);
				redo;
			}
		}
	}
}
$SIG{CHLD} = \&REAPER;
$SIG{TERM} = sub { unlink "info_pl.pid"; unlink "fifo_info"; exit(0); };

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
	push @prog, progs::telerama->new($net);
}
push @prog, progs::nolife->new($net);
push @prog, progs::finter->new($net);
push @prog, progs::labas->new($net);
push @prog, progs::podcasts->new($net);
push @prog, progs::files->new($net);
push @prog, progs::series->new($net);
push @prog, progs::youtube->new($net);
push @prog, progs::arte->new($net);

system("rm -f fifo_info && mkfifo fifo_info");
# read_prg:
my $nb_days = 1;
my $cmd;
debut:
my $last_hour = 0;

read_fifo:
my $read_before = undef;
($channel,$long) = ();
# my $timer_start;
my $time;

sub disp_duree($) {
	my $duree = shift;
	if ($duree < 60) {
		$duree."s";
	} elsif ($duree < 3600) {
		sprintf("%d min",$duree/60);
	} else {
		my $h = sprintf("%d",$duree/3600);
		sprintf("%dh%02d",$h,($duree-$h*3600)/60);
	}
}

sub disp_prog {
	my ($sub,$long) = @_;
	if (!$sub) {
		print "info: disp_prog sans sub !\n";
		return;
	}
	$lastprog = $sub;
	$last_chan = $$sub[1];
	my $start = $$sub[3];
	my $end = $$sub[4];
	my @date = ($$sub[12] ? split('/', $$sub[12]) : "");
	my $date = timelocal_nocheck(0,0,12,$date[0],$date[1]-1,$date[2]-1900);
	my ($sec,$min,$hour,$mday,$mon,$year,$wday) = localtime($date);
	my $time = time();
	my $reste = undef;
	if ($start && $time > $start && $time < $end) {
		$reste = $end-$time;
	}
	$start = get_time($start);
	$end = get_time($end);
	my $raw = 0;
	if ($$sub[9]) {
		# Prsence d'une image...
		my $name = $$sub[9];
		$name =~ s/^.+\///;

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
	binmode($out, ":utf8"); # if ($source =~ /Fichiers/);

	print $out "$name\n";
	print $out $raw if ($raw);

	print $out "\n$$sub[1] : $start - $end ".
	($reste ? "reste ".disp_duree($reste) : "($days[$wday])");
	if (-f "stream_info") {
		my ($cur,$last,$info) = get_stream_info();
		$cur = "" if (!$cur); # Evite le warning de manip d'undef
		$cur =~ s/pic:(http.+?) //;
		$cur =~ s/^.+\(\) //; # vire les infos vides d'auteurs/pistes
		print "*** info: got $cur,$last,$info.\n";

		print $out " ($info)";
	}
	print $out "\n$$sub[2]\n\n$$sub[6]\n$$sub[7]\n";
	print $out "$$sub[11]\n" if ($$sub[11]); # Critique
	print $out "*"x$$sub[10] if ($$sub[10]); # Etoiles
	out::close_fifo($out);
	if (!$long) {
		$start_timer = $time+5 if ($start_timer < $time);
	} else {
		$start_timer = 0;
	}
	$last_long = $long;
#	print "last_long = $last_long from disp_prog\n";
}

if (!$channel) {
	$cmd = "";
	do {
		# Celui là sert à vérifier les déclenchements externes (noair.pl)
		$time = time;
		my $delay = $time + 30;
		if (-f "list_coords" || -f "numero_coords") {
			$delay = $time+3;
		}
		# Pour afficher le bandeau du prochain programme en auto, on désactive
		# c'est + gênant qu'autre chose surtout à cause des imprécisions de
		# certaines chaines... !
#		if ($last_chan && defined($lastprog)) {
#			my $ndelay = $$lastprog[4];
#			$ndelay = 0 if ($ndelay <= $time);
#			# print "delay nextprog : ",get_time($ndelay),"\n";
#			if (!$delay || ($ndelay && $ndelay < $delay)) {
#				$delay = $ndelay ;
#			}
#			if (defined($delay) && $delay < $time) {
#				# on obtient un delay négatif ici quand nolife n'a pas
#				# encore les programmes actuels
#				$delay = undef;
#			}
#		}

		if ($start_timer && $start_timer > $time &&
			(!$delay || $start_timer < $delay)) {
			$delay = $start_timer;
			# print "delay start_timer : ",get_time($delay),"\n";
		}
		$delay = $recordings->get_delay($time,$delay);

		$delay -= $time if ($delay);
		$delay = 1 if ($delay <= 0);
		if ((-f "list_coords" || -f "numero_coords") && $delay && $delay > 1) {
			$delay = 1;
		}
		# print "info: delay $delay\n";

		my $nfound;
		eval {
			local $SIG{ALRM} = sub { die "alarm\n"; };
			alarm($delay) if ($delay);
			open(F,"<fifo_info") || die "ouverture fifo_info !\n";
			alarm(0);
			$nfound = 1;
			($cmd) = <F>;
		};
		$nfound = 0 if ($@);

		$time = time;
#		if ($last_chan && defined($lastprog) && $$lastprog[4] &&
#			$time >= $$lastprog[4] && $time - $$lastprog[4]<=5) {
##			if (-f "info_coords" && $time - $$lastprog[4] < 5) {
#			my $prg = $prog[$reader]->next($last_chan);
#			disp_prog($prg,$last_long);
##			}
#		}
		$recordings->handle($time);
		if (-f "list_coords" || -f "numero_coords" && $time-$time_refresh >= 1) {
			$time_refresh = $time;
			out::send_cmd_list("refresh");
		}

		if ($nfound > 0) {
			if ($cmd) {
				chomp ($cmd);
				my @tab = split(/ /,$cmd);
				($tab[0],$long) = split(/\:/,$tab[0]);
				$cmd = join(" ",@tab);
			}
		}
		close(F);
		if ($start_timer && $time - $start_timer >= 0 && -f "info_coords" &&
			! -f "list_coords") {
			print "alpha sur start_timer\n";
			out::alpha("info_coords",-40,-255,-5);
			unlink "info_coords";
			$start_timer = 0;
			out::send_bmovl("image");
		}
	} while (!$cmd);
	#$timer_start = [gettimeofday];
# 	print "info: reçu cmd $cmd\n";
	if ($cmd eq "clear") {
		out::clear("info_coords");
		goto read_fifo;
	} elsif ($cmd eq "time") {
		out::send_command("osd_show_property_text ".get_time(time())." 3000\n");
		goto read_fifo;
	} elsif ($cmd eq "nextprog" || $cmd eq "right") {
		disp_prog($prog[$reader]->next($last_chan),$last_long);
		goto read_fifo;
	} elsif ($cmd eq "prevprog" || $cmd eq "left") {
		disp_prog($prog[$reader]->prev($last_chan),$last_long);
		goto read_fifo;
	} elsif ($cmd =~ /^(next|prev)$/) {
	    # Ces commandes sont juste passées à bmovl sans rien changer
	    # mais en passant par ici ça permet de réinitialiser le timeout
	    # de fondu, plutôt pratique...
		out::send_bmovl($cmd);
	    goto read_fifo;
	} elsif ($cmd =~ /^(up|down)$/) {
		$cmd = out::send_list(($cmd eq "up" ? "next" : "prev")." $last_chan");
		$channel = $cmd;
		print "got channel :$channel.\n";
		$long = $last_long;
	} elsif ($cmd eq "zap1") {
		if (open(F,">fifo_list")) {
			print F "zap2 $last_chan\n";
			close(F);
		} else {
			print "can't talk to fifo_list\n";
		}
		goto read_fifo;
	} elsif ($cmd =~ s/^prog //) {
		# Note : $long est passé collé à la commande par un :
		# mais il est séparé avant même l'interprêtation, dès la lecture
		# Nouvelle syntaxe prog[:long] chaine,source/base_flux
		# ça devient obligatoire d'avoir la source liée à ça avec toutes les
		# sources de programmes maintenant
		$cmd =~ s/§(.+)//;
		$source = $1;
		$source =~ s/\/(.+)//;
		$base_flux = $1;
		$base_flux =~ s/,(.+)//;
		$serv = $1;
		$channel = $cmd;
	} elsif ($cmd eq "record") {
		out::clear("info_coords") if (-f "info_coords");
		out::clear("list_coords") if (-f "list_coords");
		$recordings->add($lastprog);
		goto read_fifo;
	} else {
		print "info: commande inconnue $cmd\n";
		goto read_fifo;
	}
}
chomp $channel;
chomp $long if ($long);
# print "lecture from fifo channel $channel long ".($long ? $long : "")." fields $#fields\n";

my $sub = undef;
for (my $n=$#prog; $n>=0; $n--) {
	$sub = $prog[$n]->get($channel,$source,$base_flux,$serv);
	if ($sub) {
		$reader = $n;
		last;
	}
}
$lastprog = undef;
if (!$sub) {
	my $name = get_cur_name();
	if ($name eq chaines::conv_channel($channel)) {
		if (-f "stream_info") {
			read_stream_info($time,$cmd);
			goto read_fifo;
		}
	}
}
if (!$sub) {
	# Pas trouvé la chaine
	my $out = out::setup_output("bmovl-src/bmovl","",0);
	$cmd =~ s/pic:(.+?) //;
	my $pic = $1;
#	my $src = out::send_list("info ".lc($cmd));
#	$src =~ s/,.+//;
	if ($source eq "flux/stations") {
		$pic = get_radio_pic($cmd);
	}
	print $out "$pic\n\n";
	($sec,$min,$hour) = localtime($time);

	print $out "$cmd : ".sprintf("%02d:%02d:%02d",$hour,$min,$sec),"\nAucune info\n";
	out::close_fifo($out);
	$start_timer = $time+5 if ($start_timer < $time);
	$last_chan = $channel;
	goto read_fifo;
}

my $read_after = undef;
disp_prog($sub,$long);
goto read_fifo;

