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
use progs::arte;

our %info; # hash pour stocker les stream_info
our $cleared = 1;
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
our $fadeout;
our $refresh;

sub get_cur_name {
	# Récupère le nom de la chaine courrante
	my ($name,$source) = out::get_current();
	$source =~ s/flux\/stations\/.+/flux\/stations/;
	return (lc($name),$source);
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
	# Là il peut y avoir un problème si une autre source a le même nom
	# de chaine, genre une radio et une chaine de télé qui ont le même
	# nom... Pour l'instant pas d'idée sur comment éviter ça...
	if (!$rinfo) {
		my ($name,$src) = get_cur_name();
		$name .= "&$src";
		if ($name eq conv($cmd)) {
			$rinfo = $info{$name};
		} else {
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

			print $out "$cmd ($info) : ".sprintf("%02d:%02d:%02d",$hour,$min,$sec);
			if ($cur) {
				print $out "\n$cur $progress\n";
			} else {
				print $out " $progress\n\n";
			}
			print $out "Dernier morceau : $last\n" if ($last);
			print $out "Paroles : $rinfo->{lyrics}" if ($rinfo->{lyrics});
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
	push @prog, progs::telerama->new($net);
}
push @prog, progs::nolife->new($net);
push @prog, progs::finter->new($net);
push @prog, progs::labas->new($net);
push @prog, progs::podcasts->new($net);
push @prog, progs::files->new($net);
push @prog, progs::series->new($net);
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
	$cleared = 0;
	my ($sub,$long) = @_;
	if (!$sub) {
		print "info: disp_prog sans sub !\n";
		return;
	}
	print "disp_long : long:$long\n";
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
		$refresh = AnyEvent->timer(after=>($reste > 60 ? 60 : $reste+1), cb =>
			sub {
				# Il faut recréer $sub -> disp_channel
				disp_channel();
			}
		);
	} elsif ($end && $end < $time) {
		# paradoxe reste négatif
		$refresh = AnyEvent->timer(after=>15, cb =>
			sub {
				disp_channel();
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
	# binmode($out, ":utf8") if ($ENV{LANG} =~ /UTF/);

	print $out "$name\n";
	print $out $raw if ($raw);

	print $out "\n$$sub[1] : $start - $end ".
	($reste ? "reste ".disp_duree($reste) : "($days[$wday])");

	my $tag = conv($channel);
	my $codec = $info{$tag}->{codec};
	print $out " ($codec)" if ($codec);

	$$sub[6] = "" if (!$$sub[6]);
	print $out "\n$$sub[2]\n\n$$sub[6]\n$$sub[7]\n";
	print $out "$$sub[11]\n" if ($$sub[11]); # Critique
	print $out "*"x$$sub[10] if ($$sub[10]); # Etoiles
	out::close_fifo($out);
	setup_fadeout($long);
	$last_long = $long;
#	print "last_long = $last_long from disp_prog\n";
}

sub commands {
	my $fh = shift;
	$cmd = shift;
	my @tab = split(/ /,$cmd);
	my $old_long = $long;
	($tab[0],$long) = split(/\:/,$tab[0]);
	$cmd = join(" ",@tab);
	$long = "" if (!$long); # Evite les warnings !
	# A priori utile juste pour prog
	$long = $old_long if ($cmd !~ /^prog /);

	print "info: reçu commande $cmd long:$long.\n";
	if ($cmd eq "clear") {
		$fadeout = $refresh = undef;
		out::clear("info_coords");
		$cleared = 1;
	} elsif ($cmd eq "tracks") {
		my ($name,$src) = get_cur_name();
		print "tracks: name $name, src $src.\n";
		$name .= "&$src";
		my @tracks = ();
		my $rtracks = $info{$name}->{tracks};
		while (<$fh>) {
			chomp;
			if ($_) {
				push @tracks,$_ ;
				print "tracks: reçu $_.\n";
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
	} elsif ($cmd =~ /^codec/) {
		my ($codec,$bitrate);
		($cmd,$codec,$bitrate) = split / /,$cmd;
		my ($name,$src) = get_cur_name();
		$name .= "&$src";
		$info{$name}->{codec} = "$codec $bitrate";
		if (!$cleared && $name eq conv($channel) && $src !~ /^flux\/podcasts/) {
			if ($lastprog && $channel eq $last_chan) {
				disp_prog($lastprog,$last_long);
			} else {
				read_stream_info(time(),$channel,$info{$name});
			}
		}
	} elsif ($cmd =~ s/^progress //) {
		my ($name,$src) = get_cur_name();
		$name .= "&$src";
		$info{$name}->{progress} = $cmd;
		if (!$cleared && $name eq conv($channel) && $src !~ /^flux\/podcasts/) {
			# Ne pas afficher de progress sur les podcasts, conflit avec
			# l'info progs/podcasts
			read_stream_info(time(),$channel,$info{$name});
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
		if (!$cleared && $name eq conv($channel)) {
			read_stream_info(time(),$channel,$info{$name});
		}
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
	} elsif ($cmd =~ s/^prog //) { # on vire le prog, garde que la chaine
		# Note : $long est passé collé à la commande par un :
		# mais il est séparé avant même l'interprêtation, dès la lecture
		# Nouvelle syntaxe prog[:long] chaine,source/base_flux
		# ça devient obligatoire d'avoir la source liée à ça avec toutes les
		# sources de programmes maintenant
		$cmd =~ s/&(.+)//;
		$source = $1;
		if ($source =~ s/\/(.+)//) {
			$base_flux = $1;
			$base_flux =~ s/^stations\/.+/stations/;
			$base_flux =~ s/,(.+)//;
			$serv = $1;
		} else {
			$base_flux = "";
			$source =~ s/\///;
			$serv = "";
		}
		$channel = $cmd;
		# long n'est pas effacé par une commande prog
		$long = $old_long if ($old_long);
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

sub disp_channel {
# Ici on a obtenu la chaine, on cherche un afficheur
	chomp $channel;
	chomp $long if ($long);
	$cleared = 0;
	print "disp_channel: entrée avec channel=$channel long:$long\n";

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
		my ($name,$src) = get_cur_name();
		if ($name."&$src" eq conv($channel)) {
			read_stream_info(time(),$cmd,$info{"$name&$src"});
			return;
		}
	}

# 3 affichage par défaut, peut quand même y avoir des paroles des fois !
	if (!$sub) {
		# Pas trouvé la chaine
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
	disp_prog($sub,$long) if ($sub);
}

