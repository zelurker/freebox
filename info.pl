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
use Coro::LWP;
use Coro;
use LWP::Simple;
use EV;
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

our $latin = ($ENV{LANG} !~ /UTF/i);
our $net = out::have_net();
our $have_fb = 0; # have_freebox
$have_fb = out::have_freebox() if ($net);
our $have_dvb = 1; # (-f "$ENV{HOME}/.mplayer/channels.conf" && -d "/dev/dvb");
our $reader;
my $recordings = records->new();

our ($lastprog,$last_chan,$last_long);
our ($channel,$long);
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
	} else {
		async {
			if ($raw = get $url) {
				if (open(F,">$name")) {
					syswrite(F,$raw,length($raw));
					close(F);
				}
				if ($lastprog) {
					disp_prog($lastprog,$last_long);
				} else {
					read_stream_info(time(),"$last_chan");
				}
			} else {
				print "couldn't get image $url\n";
			}
		};
	}
		return $name;
}

sub disp_lyrics {
	my $out = shift;
	if (open(F,"<stream_lyrics")) {
		my $info = "\nParoles : ";
		while (<F>) {
			$info .= $_;
		}
		close(F);
		print $out $info;
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
			disp_lyrics($out);
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
	# Bizarre d'être obligé de faire ça, mais apparemment vaut mieux !
	binmode($out, ":utf8") if ($ENV{LANG} =~ /UTF/);

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

sub commands {
	my ($fh,$cmd) = @_;
	# C'est un peu bizarre comme idée, long initialisé pour toutes les
	# commandes ? A priori ça n'est utile que pour prog, mais bon on va
	# garder comme ça pour l'instant...
	my @tab = split(/ /,$cmd);
	($tab[0],$long) = split(/\:/,$tab[0]);
	$cmd = join(" ",@tab);

	print "info: reçu commande $cmd.\n";
	if ($cmd eq "clear") {
		out::clear("info_coords");
	} elsif ($cmd eq "time") {
		out::send_command("osd_show_property_text ".get_time(time())." 3000\n");
	} elsif ($cmd eq "nextprog" || $cmd eq "right") {
		disp_prog($prog[$reader]->next($last_chan),$last_long);
	} elsif ($cmd eq "prevprog" || $cmd eq "left") {
		disp_prog($prog[$reader]->prev($last_chan),$last_long);
	} elsif ($cmd =~ /^(next|prev)$/) {
	    # Ces commandes sont juste passées à bmovl sans rien changer
	    # mais en passant par ici ça permet de réinitialiser le timeout
	    # de fondu, plutôt pratique...
		out::send_bmovl($cmd);
	} elsif ($cmd =~ /^(up|down)$/) {
		$cmd = out::send_list(($cmd eq "up" ? "next" : "prev")." $last_chan");
		$channel = $cmd;
		print "got channel :$channel.\n";
		$long = $last_long;
	} elsif ($cmd eq "zap1") {
		out::send_list("zap2 $last_chan");
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
	} else {
		print "info: commande inconnue $cmd\n";
	}
	if (defined($channel)) {
		disp_channel();
	}
}

sub disp_channel {
# Ici on a obtenu la chaine, on cherche un afficheur
	chomp $channel;
	chomp $long if ($long);

	my $sub = undef;
# 1 les trucs spécialisés (séries, radios, etc).
	for (my $n=$#prog; $n>=0; $n--) {
		$sub = $prog[$n]->get($channel,$source,$base_flux,$serv);
		if ($sub) {
			$reader = $n;
			last;
		}
	}
	$lastprog = undef;
# 2 l'afficheur de base pour les fichiers (stream_info)
	if (!$sub) {
		my $name = get_cur_name();
		if ($name eq chaines::conv_channel($channel)) {
			if (-f "stream_info") {
				read_stream_info(time(),$cmd);
				return;
			}
		}
	}

# 3 affichage par défaut, peut quand même y avoir des paroles des fois !
	if (!$sub) {
		# Pas trouvé la chaine
		my $time = time();
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

		print $out "$cmd : ".sprintf("%02d:%02d:%02d",$hour,$min,$sec),"\n";
		if (-f "stream_lyrics") {
			disp_lyrics($out);
		} else {
			print $out "Aucune info\n";
		}
		out::close_fifo($out);
		$start_timer = $time+5 if ($start_timer < $time);
		$last_chan = $channel;
		return;
	}

	# Si on arrive là, on a le texte à afficher dans sub, y a plus qu'à y
	# aller !
	my $read_after = undef;
	disp_prog($sub,$long);
}

