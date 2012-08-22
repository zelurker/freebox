#!/usr/bin/perl

# Gestion de la liste de chaines
# Accepte les commandes par une fifo : fifo_list
# commandes reconnues :
# down, up, right, left : déplacement dans la liste
# name service flavour : renvoie le nom de la chaine sur la fifo
# next/prev service flavour : renvoie le nom de la chaine suivante/précédente
# zap1 : zappe sur la chaine sélectionnée dans la liste
# zap2 : même chose mais en passant le nom de la chaine
# clear : efface la liste et le cadre d'info éventuel
# list : affiche la liste
# switch_mode : change de mode
# reset_current : resynchronise la liste après une màj du fichier current

use strict;
use Socket;
use POSIX qw(strftime :sys_wait_h SIGALRM);
use LWP::Simple;
use Encode;
use Fcntl;
use File::Glob 'bsd_glob'; # le glob dans perl c'est n'importe quoi !
require "output.pl";
require "mms.pl";
require "chaines.pl";
use HTML::Entities;

sub have_freebox {
	# Les crétins de chez free ont fait une ip sur le net au lieu de faire
	# une ip locale, et cette ip bloque tout traffic y compris le ping de tout
	# ce qui ne fait pas partie de leur réseau. Ils sont gentils hein ?
	# Le + simple pour tester cette saloperie c'est juste de faire un connect
	# sur le port http.
	# On pourrait utiliser Net::Ping, mais c'est à peine + simple, et si jamais
	# un jour ça change on est mal, c mieux comme ça.
	my $net = 1;
	eval {
		POSIX::sigaction(SIGALRM,
			POSIX::SigAction->new(sub { die "alarm" }))
			or die "Error setting SIGALRM handler: $!\n";
		alarm(2);
		my $remote = "mafreebox.freebox.fr";
		my $port = 80;
		my $iaddr   = inet_aton($remote)       || die "no host: $remote";
		my $paddr   = sockaddr_in($port, $iaddr);
		my $proto   = getprotobyname("tcp");
		socket(SOCK, PF_INET, SOCK_STREAM, $proto)  || die "socket: $!";
		connect(SOCK, $paddr)               || die "connect: $!";
		close(SOCK);
		print "Accès freebox ok !\n";
	};
	alarm(0);
	$net = 0 if ($@);
	$net;
}

our ($l);
our $net = have_net();
my $have_fb = 0; # have_freebox
$have_fb = have_freebox() if ($net);
our $have_dvb = (-f "$ENV{HOME}/.mplayer/channels.conf" && -d "/dev/dvb");
our $pid_player2;
open(F,">info_list.pid") || die "info_list.pid\n";
print F "$$\n";
close(F);
my $numero = "";
my $time_numero = undef;
my $last_list = "";

$SIG{PIPE} = sub { print "list: sigpipe ignoré\n" };

my @modes = (
	"freeboxtv",  "dvb", "Enregistrements", "Fichiers vidéo", "Fichiers son", "livetv", "flux","radios freebox",
	"cd","apps");
if (!$have_fb || !$have_dvb) {
	for (my $n=0; $n<=$#modes; $n++) {
		if ((!$have_fb && $modes[$n] =~ /freebox/) ||
			(!$have_dvb && $modes[$n] eq "dvb")) {
			splice(@modes,$n,1);
			redo;
		}
	}
}

my ($mode_opened,$mode_sel);

if (open(F,"<current")) {
	@_ = <F>;
	close(F);
}
my ($chan,$source,$serv,$flav) = @_;
$source =~ s/\/(.+)//;
my $base_flux = $1;
chomp ($chan,$source,$serv,$flav);
$chan = lc($chan);
$source = "freeboxtv" if (!$source);
# print "list: obtenu chan $chan source $source serv $serv flav $flav\n";

my (@list);
our $found = undef;
my $mode_flux;
our %conf;

sub read_conf {
	if (open(F,"<$ENV{HOME}/.freebox/conf")) {
		while (<F>) {
			chomp;
			if (/(.+) = (.+)/) {
				$conf{$1} = $2;
			}
		}
		close(F);
	}
}

sub save_conf {
	if ($base_flux) {
		$conf{"sel_$source\_$base_flux"} = $found;
	} else {
		$conf{"sel_$source"} = $found;
	}
	my $dir = "$ENV{HOME}/.freebox";
	mkdir $dir;
	if (open(F,">$dir/conf")) {
		foreach (keys %conf) {
			print F "$_ = $conf{$_}\n";
		}
		close(F);
	}
}

sub cd_menu {
	@list = ();
	# 1 - séléectionner le cd
	# pour l'instant on prend le 1er listé dans /proc/sys/dev/cdrom/info
	my $cd = "";
	if (open(F,"</proc/sys/dev/cdrom/info")) {
		while (<F>) {
			chomp;
			if (/drive name:[ \t]*(.+)/) {
				$cd = "/dev/$1";
				last;
			}
		}
		close(F);
	}
	if (!$cd) {
		$base_flux = "problème dans /proc/sys/dev/cdrom/info";
		return;
	}

	my $tries = 1;
	my @list_cdda = ();
	my $error;
	do {
		$error = 0;
		open(F,"mplayer -cdrom-device $cd cddb:// -nocache -identify -frames 0|");
		my $track;
		@list = @list_cdda = ();
		my ($artist,@duree);
		while (<F>) {
			chomp;
			if (/(ID.+?)\=(.+)/) {
				my ($name,$val) = ($1,$2);
				print "scanning $name = $val\n";
				if ($name eq "ID_CDDB_INFO_ARTIST") {
					$base_flux = "$val - ";
					$artist = $val;
				} elsif ($name eq "ID_CDDB_INFO_ALBUM") {
					$base_flux .= $val;
				} elsif ($name =~ /ID_CDDB_INFO_TRACK_(\d+)_NAME/) {
					$track = $val;
					print "track = $track\n";
				} elsif ($name =~ /ID_CDDB_INFO_TRACK_(\d+)_MSF/) {
					print "list: $artist - $track / $1\n";
					$duree[$1-1] = $val;
					if ($list[$1-1]) {
						$list[$1-1][0][1].= "$track";
					} else {
						push @list,[[$1,"$track","cddb://$1-99"]];
					}
				} elsif ($name =~ /ID_CDDA_TRACK_(\d+)_MSF/) {
					push @list_cdda,[[$1,"pas d'info cddb ($val)","cdda://$1"]] if ($val ne "00:00:00");
				}
			} elsif (/500 Internal Server Error/) {
				$error = 1;
			}
		}
		close(F);
		for (my $n=0; $n<=$#list; $n++) {
			$list[$n][0][1] .= " ($duree[$n])";
		}
	} while ($error && ++$tries <= 3);
	$found = 0;
	@list = @list_cdda if (!@list);
}

sub apps_menu {
	our %apps;
	@list = ();
	if (!%apps) {
		my $lang = lc($ENV{LANG});
		my ($lang2) = ($lang =~ /^(..)_/);
		print "test lang $lang,$lang2\n";
		while (</usr/share/applications/*>) {
			next if (!open(F,"<$_"));
			my $file = $_;
			my %fields;
			while (<F>) {
				chomp;
				if (/(.+)\=(.+)/) {
					$fields{lc($1)} = $2;
				}
			}
			close(F);
			next if ($fields{"terminal"} eq "true");
			next if ($fields{"onlyshowin"}); # app specific
			next if (!$fields{"categories"}); # si, si, ça arrive !!!
			$fields{categories} =~ s/;$//; # supprime éventuel ; à la fin
            foreach ($lang2,$lang) {
				if ($fields{"name[$_]"}) {
					$fields{name} = $fields{"name[$_]"}; 
					Encode::from_to($fields{name}, "utf-8", "iso-8859-15");
				}
			}
			push @{$apps{$fields{categories}}},[$fields{name},$fields{icon},$fields{exec}];
			if (length($fields{categories}) < 2) {
				print "categ $fields{categories}: $fields{name},$fields{icon},$fields{exec} fichier $file\n";
			}
		}
	}
	my %categ;
	foreach (keys %apps) {
		if ($base_flux && /^$base_flux/) {
			my $key = $_;
			s/^$base_flux\;?//;
			s/;.+$//;
			if ($_ && !$categ{$_}) {
				$categ{$_} = 1;
				push @list,[[1,$_,""]];
			} elsif (!$_) {
				foreach (@{$apps{$key}}) {
					push @list,[[2,$$_[0],$$_[2]]];
				}
			}
		} elsif (!$base_flux) {
			my $key = $_;
			s/\;.+//;
			if (!$categ{$_}) {
				$categ{$_} = 1;
				push @list,[[1,$_,""]];
			}
		}
	}
	@list = sort { $$a[0][1] cmp $$b[0][1] } @list;
	for (my $n=0; $n<=$#list; $n++) {
		$list[$n][0][0] = $n+1;
		print "list $n $list[$n][0][0] $list[$n][0][1]\n";
	}
}

sub read_freebox {
	my $list;
	open(F,"<freebox.m3u") || die "can't read freebox playlist\n";
	@list = <F>;
	close(F);
	$list = join("\n",@list);
	@list = ();
	$list =~ s/ \(standard\)//g;
	$list;
}

sub read_list {
#	print "list: read_list source $source base_flux $base_flux mode_flux $mode_flux\n";
	if (!$base_flux) {
		$found = $conf{"sel_$source"};
	}
	if ($source eq "menu") {
		@list = ();
		$base_flux = "";
		my $nb = 1;
		foreach (@modes) {
			if (switch($_)) {
				push @list,[[$nb++,$_]];
			}
		}
	} elsif ($source eq "apps") {
		apps_menu();
	} elsif ($source eq "cd") {
		cd_menu();	
	} elsif ($source =~ /freebox/) {
		my $list;
		my ($name,$serv,$flav,$audio,$video) = get_name($list[$found]);
		if ($source =~ /Radios/i) {
			if (open(F,"<Freebox-Radios.m3u")) {
				$list = "";
				while (<F>) {
					$list .= $_;
				}
				close(F);
				print "freebox radios lue... ";
				print "pas " if ($list !~ /EXTINF/);
				print "validé\n";
			} else {
				print "impossible d'ouvrir le fichier de radios\n";
				@list = ();
				return;
			}
		} elsif (!-f "freebox.m3u" || -M "freebox.m3u" >= 1) {
			$list = get "http://mafreebox.freebox.fr/freeboxtv/playlist.m3u";
			$list =~ s/ \(standard\)//g;
			if (!$list) {
				print "can't get freebox playlist\n";
				$list = read_freebox();
			} else {
				open(F,">freebox.m3u") || die "can't create freebox.m3u\n";
				print F $list;
				close(F);
			}
		} else {
			$list = read_freebox();
		}
		if ($list !~ /EXTINF/) {
			unlink "freebox.m3u";
			print "format freebox.m3u pété, on essaye encore...\n";
			$list = read_freebox();
		}
		my @rejets;
		if (open(F,"<rejets/$source")) {
			while (<F>) {
				chomp;
				my ($serv,$flav,$audio,$video,$name) = split(/:/);
				push @rejets,[$serv,$flav,$audio,$video,$name];
			}
			close(F);
		}

		Encode::from_to($list, "utf-8", "iso-8859-15") if ($list !~ /débit/);

		my ($num,$name,$service,$flavour,$audio,$video);
		my $last_num = undef;
		@list = ();
		my $tv;
		$tv = 1 if ($source eq "freeboxtv" || $source eq "freebox");
		foreach (split(/\n/,$list)) {
			if (/^#EXTINF:(\d+),(\d+) \- (.+?) *$/) {
				($num,$name) = ($2,$3);
				$service = $flavour = $audio = $video = undef;
			} elsif (/^#EXTVLCOPT:no-video/) {
				$video = "no-video";
			} elsif (/audio-track-id=(\d+)/) {
				$audio = $1;
			} elsif (/service=(\d+)/) {
				$service = $1;
				if (/flavour=(.+)/) {
					$flavour = $1;
				}
				die "pas de numéro pour $_\n" if (!$num);
				next if (!defined($flavour) && $tv);
				my $reject = 0;
				my $red = 0;

				foreach (@rejets) {
					if ($$_[0] eq $service && $$_[1] eq $flavour &&
						$$_[2] eq $audio && $$_[3] eq $video) {
						if ($$_[4] ne $name) {
							$red = 1;
							if ($$_[0] == 430) {
								print "red sur $$_[4]/$name $flavour\n";
							}
						} else {
							$reject = 1;
						}
						last;
					}
				}
				next if ($reject);
				next if (($tv && $video eq "no-video") ||
					(!$tv && $video ne "no-video"));

				$num -= 10000 if (!$tv);
				my $pic = get_chan_pic($name);
				if ($pic) {
					print "$pic from $name\n";
				} else {
					print "no pic found for name $name\n";
				}

				my @cur = ($num,$name,$service,$flavour,$audio,$video,$red,
				$pic);
				if ($last_num != $num) {
					$last_num = $num;
					push @list,[\@cur];
				} else {
					my $rtab = $list[$#list];
					push @$rtab,\@cur;
				}
			}
		}
		if (!$tv) {
			@list = sort { $$a[0][1] cmp $$b[0][1] } @list;
		}
	} elsif ($source eq "dvb") {
		my $f;
		open($f,"<$ENV{HOME}/.mplayer/channels.conf") || die "can't open channels.conf\n";
		@list = ();
		my $num = 1;
		while (<$f>) {
			chomp;
			my @fields = split(/\:/);
			my $service = $fields[0];
			my $name = $service;
			$name =~ s/\(.+\)//; # name sans le transpondeur
			my $pic = get_chan_pic($name);
			push @list,[[$num++,$name,$service,undef,undef,undef,undef,$pic]];
		}
		close($f);
	} elsif ($source =~ /^(livetv|Enregistrements)$/) {
		@list = ();
		my $num = 1;
		my $pat;
		if ($source eq "livetv") {
			$pat = "livetv/*.ts";
		} else {
			$pat = "records/*.ts";
		}
		while (glob($pat)) {
			my $service = $_;
			my $name = $service;
			$name =~ s/.ts$//;
			$name =~ s/^.+\///;
			my ($an,$mois,$jour,$heure,$minute,$sec,$chaine) = $name =~ /^(....)(..)(..) (..)(..)(..) (.+)/;
			$name = "$jour/$mois $heure:$minute $chaine ";
			my $taille = -s "$service";
			$taille = sprintf("%d",$taille/1024/1024);
			$name .= $taille."Mo";
			push @list,[[$num++,$name,$service]];
		}
		@list = reverse @list;
	} elsif ($source =~ /^Fichiers/) {
		@list = ();
		my ($path,$tri);
		if ($source eq "Fichiers vidéo") {
			$path = "video_path";
			$tri = "tri_video";
		} else {
			$path = "music_path";
			$tri = "tri_music";
		}
		print "read_list pour $source\n";
		my $num = 1;
		my $pat;
		if (!$conf{$path}) {
			$conf{$path} = `pwd`;
			chomp $conf{$path};
		}
		if ($conf{$path} eq "/") {
			$pat = "/*";
		} else {
			$pat = "$conf{$path}/*";
			$pat =~ s/ /\\ /g;
			$pat =~ s/\[/\\\[/g;
			$pat =~ s/\]/\\\]/g;
		}
		$conf{"$tri"} = "nom" if (!$conf{"$tri"});
		my @paths = bsd_glob($pat);
		while ($_ = shift @paths) {
			my $service = $_;
			next if (!-e $service); # lien symbolique mort
			my $name = $service;
			$name =~ s/.+\///; # Supprime le path du nom
			if (-d $service) {
				$name .= "/";
			}
			push @list,[[$num++,$name,$service,-M $service]];
		}
		unlink "info_coords";
		if ($conf{$tri} eq "date") {
			@list = sort { $$a[0][3] <=> $$b[0][3] } @list;
		}
		if ($conf{$path} ne "/") {
			unshift @list,[[$num++,"../",".."]];
		}
		unshift @list,[[$num++,"Tri par $conf{$tri}","tri par"]];
#		@list = reverse @list;
	} elsif ($source eq "flux") {
		if (open(F,"<current")) {
			@_ = <F>;
			close(F);
			if ($_[2] =~ /^cd/) {
				# c'est un flux provoqué par le cd -> ne rien faire
				$source = "cd";
				return;
			}
		}
		my $num = 1;
		if (!$base_flux) {
			@list = ();
			while (<flux/*>) {
				my $service = $_;
				my $name = $service;
				$name =~ s/^.+\///;
				push @list,[[$num++,$name,$service]];
			}
		} else {
			my $b = $base_flux;
			if ($b =~ /\//) {
				$b =~ s/(.+?)\/.+/$1/;
			}
			if (-x "flux/$b") {
				my ($name,$serv,$flav,$audio,$video) = get_name($list[$found]);
				if (!$mode_flux) {
					$serv = "";
					$base_flux =~ s/^(.+?)\/.+/$1/;
				}
				if ($serv eq "Recherche") {
					delete $ENV{WINDOWID};
					$serv = `zenity --entry --text="A chercher (regex)"`;
					chomp $serv;
					$serv = "result:$serv";
					$base_flux =~ s/(.+?)\/.+/$1\/$serv/;
				}
				if (!$serv && $base_flux =~ /\/result\:(.+)/) {
					# Quand on relance freebox, get_name ne peut pas avoir la
					# bonne valeur, on doit la déduire de base_flux si on veut
					# que ça marche !
					$serv = $1;
				}

				print "list: execution plugin flux $b param $serv base_flux $base_flux\n";
				open(F,"flux/$b \"$serv\"|");
				$mode_flux = <F>;
				chomp $mode_flux;
			} else {
			   	if (!open(F,"<flux/$base_flux")) {
					return;
				}
			}
			@list = ();
			while (<F>) {
				my $name = $_;
				my $service = <F>;
				chomp ($name,$service);
				$name =~ s/^pic:(.+?) //;
				my $pic = $1;
				if ($pic =~ /.+\/(.+?)\/default.jpg/) {
					# Youtube
					my $file = "cache/$1_yt.jpg";
					if (!-f $file) {
						if (open(G,">$file")) {
							print G get $pic;
							close(G);
						}
					}
					$name = "pic:$file ".decode_entities($name);
				}

				push @list,[[$num++,$name,$service]];
			}
			print "list: ".($#list+1)." flux\n";
			$found = 0 if ($found > $#list);
			close(F);
		}
	} else {
		print "read_list: source inconnue $source\n";
	}
	if ($base_flux) {
		$found = $conf{"sel_$source\_$base_flux"};
	}
}

sub get_name {
	my $rtab = shift;
	my $name = $$rtab[0][1];
	my $sel = $$rtab[0];
	if ($mode_opened && $rtab == $list[$found]) {
		$sel = $$rtab[$mode_sel];
	} else {
		foreach (@$rtab) {
			if (length($$_[1]) < length($name)) {
				$sel = $_;
			}
		}
	}
	return ($$sel[1],$$sel[2],$$sel[3],$$sel[4],$$sel[5]);
}

sub find_channel {
	my ($serv,$flav,$audio) = @_;
	$flav = "" if ($flav eq "0");
	if ($source =~ /freebox/) {
		for (my $n=0; $n<=$#list; $n++) {
			for (my $x=0; $x<=$#{$list[$n]}; $x++) {
				if ($list[$n][$x][2] == $serv &&
					$list[$n][$x][3] eq $flav &&
					($audio ? $list[$n][$x][4] == $audio : 1)) {
					return ($n,$x);
				}
			}
		}
	} else { # dvb
		for (my $n=0; $n<=$#list; $n++) {
			if ($list[$n][0][2] eq $serv) {
				return ($n,0);
			}
		}
	}
	return undef;
}

sub find_name {
	my $name = shift;
	for (my $n=0; $n<=$#list; $n++) {
		for (my $x=0; $x<=$#{$list[$n]}; $x++) {
			if (lc($list[$n][$x][1]) eq $name) {
				return ($n,$x);
			}
		}
	}
	# Si on est là, on a pas trouvé, on va essayer avec conv_channel Si c'est
	# le cas, généralement on reçoit le nom par info.pl et le nom a déjà été
	# converti, il vaut mieux éviter de le convertir 2 fois pour des chaines
	# comme game one music hd hd $name = conv_channel($name);
	for (my $n=0; $n<=$#list; $n++) {
		for (my $x=0; $x<=$#{$list[$n]}; $x++) {
			if (conv_channel($list[$n][$x][1]) eq $name) {
				return ($n,$x);
			}
		}
	}
	print "find_name: rien trouvé pour $name\n";
	return undef;
}

sub switch_mode {
	my $found = shift;
	$found++;
	$found = 0 if ($found > $#modes);
	$source = $modes[$found];
	print "switch_mode: source = $source\n";
	read_list();
}

sub reset_current {
	# replace tout sur current
	my $f;
	if (open($f,"<current")) {
		my $name  = <$f>;
		my $src = <$f>;
		close($f);
		chomp($name, $src);
		$src =~ s/\/(.+)//;
		if ($1 && $base_flux ne $1) {
			$base_flux = $1;
			print "reset_current: read_list sur base_flux $base_flux\n";
			read_list();
		}
		if ($src ne $source) {
			print "reset_current: reseting to $src\n";
			$source = $src;
			read_list();
		} else {
			# On va quand meme chercher la chaine en cours...
			for (my $n=0; $n<=$#list; $n++) {
				for (my $x=0; $x<=$#{$list[$n]}; $x++) {
					my ($num,$name2) = @{$list[$n][$x]};
					if ($name eq $name2) {
						$found = $n;
						last;
					}
				}
			}
		}
	}
}

sub kill_player1 {
	if (-f "player1.pid") {
		my $pid = `cat player1.pid`;
		chomp $pid;
		print "pid2 à tuer $pid.\n";
		kill "TERM",$pid;
		unlink "player1.pid";
	}
}

sub run_mplayer2 {
	my ($name,$src,$serv,$flav,$audio,$video) = @_;
	$l = undef; # Ne ferme pas ça dans le fils !!!
	unlink "fifo_cmd","fifo";
	system("mkfifo fifo_cmd fifo");
	my $player = "mplayer2";
	my $cache = 100;
	my $filter = "";
	my $cd = "";
	my $pwd;
	chomp ($pwd = `pwd`);
	my $quiet = "";
	if ($src =~ /(flux|cd)/) {
		$quiet = "-quiet";
		if ($name =~ /mms/ || $src =~ /youtube/) {
			$cache = 1000;
		}
		if ($src =~ /cd/) {
			if (open(F,"</proc/sys/dev/cdrom/info")) {
				while (<F>) {
					chomp;
					if (/drive name:[ \t]+(.+)/) {
						$cd = $1;
						last;
					}
				}
				close(F);
				print "cd drive : $cd\n";
				$cd = "-cdrom-device /dev/$cd " if ($cd);
			}
		}
		if ($name =~ /cddb/) {
			$player = "mplayer";
		}	   
		$serv =~ s/ http.+//; # Stations de radio, vire l'url du prog
	} else {
		$audio = "-aid $audio " if ($audio);
		if ($src =~ /Fichiers vidéo/) {
			if ($name =~ /(mpg|ts)$/) {
				$filter = ",kerndeint";
			}
			$cache = 5000;
		} elsif (($src =~ /freeboxtv/ && ($name =~ /HD/ || $name =~ /bas débit/)) ||
			($src eq "dvb")) {
			$filter = ",kerndeint";
			$player = "mplayer" if ($src ne "dvb");
		}
	}
	my @list = ("perl","filter_mplayer.pl",$player,$audio,$cd,$serv,"-cache",$cache,
		"-framedrop","-autosync",10,
		"-stop-xscreensaver","-identify",$quiet,"-input",
		"nodefault-bindings:conf=$pwd/input.conf:file=fifo_cmd","-vf",
		"bmovl=1:0:fifo,screenshot$filter");
	for (my $n=0; $n<=$#list; $n++) {
		if (!$list[$n]) {
			splice(@list,$n,1);
			redo;
		}
	}
	print join(",",@list),"\n";
	exec(@list);
}

sub load_file2($$$$$) {
	# Même chose que load_file mais en + radical, ce coup là on kille le player
	# pour redémarrer à froid sur le nouveau fichier. Obligatoire quand on vient
	# d'une source non vidéo vers une source vidéo par exemple.
	my ($name,$serv,$flav,$audio,$video) = @_;
	my $prog;
	$prog = $1 if ($serv =~ s/ (http.+)//);
	send_command("pause\n");
	kill_player1();
	if ($serv !~ /^cddb/ && $serv !~ /(mp3|ogg|flac|mpc|wav|aac|flac|ts)$/i) {
	    # Gestion des pls supprimée, mplayer semble les gérer
	    # très bien lui même.
		my $old = $serv;
	    $serv = get_mms($serv) if ($serv =~ /^http/);
		print "get_mms $old -> $serv\n";
		if ($serv) {
			print "flux: loadfile $serv from $serv\n";
			open(G,">live");
			close(G);
		}
	}
	if ($serv) {
		if ($source !~ /(Fichiers son|cd)/) {
			print "effacement fichiers coords:$source:\n";
			clear( "list_coords","info_coords","video_size");
			system("kill -USR2 `cat info.pid`");
		}
		open(G,">current");
		my $src = $source; # ($source eq "cd" ? "flux" : $source);
		$src .= "/$base_flux" if ($base_flux);
		$serv .= " $prog" if ($prog);
		# $serv est en double en 7ème ligne, c'est voulu
		# oui je sais, c'est un bordel
		# A nettoyer un de ces jours dans run_mp1/freebox
		print G "$name\n$src\n$serv\n$flav\n$audio\n$video\n$serv\n";
		close(G);
		print "sending quit\n";
		unlink("id","stream_info");
		# Remarque ici on ne veut pas que le message id_exit=quit sorte de
		# filter, donc on le kille juste avant d'envoyer la commande de quit
		my $f;
		if ($pid_player2) {
			print "player2 pid ok, kill...\n";
			kill "TERM" => $pid_player2;
		}
		# On a déjà pas de player2, on admet qu'il faut tout relancer
		# dans ce cas là
		print "run_mplayer2...\n";
		if ($src =~ /(dvb|freeboxtv)/) {
			print "lancement run_mp1...\n";
			system("./run_mp1 \"$serv\" $flav $audio $video \"$source\" \"$name\"");
		}
		$pid_player2 = fork();
		if ($pid_player2 == 0) {
			run_mplayer2($name,$src,$serv,$flav,$audio,$video);
		}
	}
}

sub get_cur_mode {
	# Détermine si on est sur la chaine qui passe, un bazar
	if (open(F,"<current")) {
		<F>; # nom
		my $src = <F>;
		chomp $src;
		if ($src ne "freeboxtv") {
			close(F);
			return 0; # Toujours le 1er mode sur une chaine différente
		}
		my $serv = <F>;
		my $flav = <F>;
		chomp ($serv,$flav);
		close(F);
		for (my $n=0; $n<=$#{$list[$found]}; $n++) {
			my ($num,$name,$service,$flavour,$audio,$video,$red) = @{$list[$found][$n]};
			if ($service == $serv && $flavour eq $flav) {
				return $n;
			}
		}
	}
	return 0;
}

sub disp_modes {
	# Affiche la boite de modes sur la droite
	# $mode_sel doit déjà être initialisé (éventuellement par get_cur_mode)
	my $out = setup_output("mode_list");
	$mode_opened = 1;
	my $n=0;
	print $out "modes\n";
	foreach (@{$list[$found]}) {
		my ($num,$name,$serv,$flav) = @{$_};
		if ($mode_sel == $n++) {
			print $out "*";
		} else {
			print $out " ";
		}
		print $out sprintf("%3d:%s",$num,$name),"\n";
	}
	close($out);
}

sub close_mode {
	clear("mode_coords");
	$mode_opened = 0;
}

sub close_numero {
	$time_numero = undef;
	if (defined($numero)) {
		clear("numero_coords");
		$numero = undef;
	}
}

read_conf();
read_list();
system("rm -f fifo_list && mkfifo fifo_list; mkfifo reply_list");
sub REAPER {
	my $child;
	# loathe SysV: it makes us not only reinstate
	# the handler, but place it after the wait
	$SIG{CHLD} = \&REAPER;
	while (($child = waitpid(-1,WNOHANG)) > 0) {
		print "list: child $child terminated\n";
		if ($child == $pid_player2) {
			print "player2 quit\n";
			$pid_player2 = 0;
			unlink("fifo","fifo_cmd");
		}
# 		if (! -f "info_coords") {
# 			print "plus d'info_coords, bye\n";
# 			return;
# 		}
	}
}

sub quit {
	close($l);
   	unlink "fifo_list","reply_list";
   	exit(0);
}

$SIG{CHLD} = \&REAPER;
$SIG{TERM} = \&quit;
my $nb_elem = 16;
if (!open($l,"<fifo_list")) {
	print "failed opening fifo_list, 2nd try...\n";
	open($l,"<fifo_list") || die "can't open fifo_list\n";
}
my $lout;
while (1) {
	my $cmd;
	if (defined($l)) {
		$cmd = <$l>;
		chomp $cmd;
	}
	if (!defined($cmd)) {
		close($l) if (defined($l));
		open($l,"<fifo_list");
		if (!defined($l)) {
			print "list: open fifo_list failed !!!\n";
		}
		next;
	}
	again:
	print "list: commande reçue après again : $cmd\n";
	if (-f "list_coords" && $cmd eq "clear") {
		clear("list_coords");
		clear("info_coords");
		close_mode() if ($mode_opened);
		send_bmovl("image");
		next;
	} elsif ($cmd eq "refresh") {
		my $found0 = $found;
		read_list() if ($source eq "Enregistrements");
		$found = $found0;
	} elsif ($cmd eq "down") {
		if ($mode_opened) {
			$mode_sel++;
			$mode_sel = 0 if ($mode_sel > $#{$list[$found]});
			disp_modes();
			next;
		}
		$found++;
		close_numero();
	} elsif ($cmd eq "up") {
		if ($mode_opened) {
			$mode_sel--;
			$mode_sel = $#{$list[$found]} if ($mode_sel < 0);
			disp_modes();
			next;
		}
		$found--;
		close_numero();
	} elsif ($cmd eq "right") {
		if ($source eq "flux" && $found > $#list-$nb_elem) {
			$cmd = "zap1";
			goto again;
		} else {
			my $rtab = $list[$found];
			if ($#$rtab > 0 && !$mode_opened) {
				$mode_sel = get_cur_mode();
				disp_modes();
				next;
			}
			close_mode if ($mode_opened);
			$found += $nb_elem;
		}
		close_numero();
	} elsif ($cmd eq "left") {
		if ($mode_opened) {
			close_mode();
			send_bmovl("image");
			next;
		}
		if ($found < $nb_elem || $nb_elem == 0) {
			if ($source =~ "flux" && $base_flux) { 
				if ($base_flux =~ /\//) {
					$base_flux =~ s/(.+)\/.+/$1/;
					if ($base_flux =~ /\//) {
						$mode_flux = "list";
					} else {
						$mode_flux = "";
					}
				} else {
					$base_flux = "";
				}
				read_list();
			} elsif ($source eq "apps" && $base_flux) {
				if ($base_flux =~ /;/) {
					print "base_flux avant $base_flux\n";
					$base_flux =~ s/(.+);.+/$1/;
					print "base_flux après $base_flux\n";
				} else {
					$base_flux = "";
				}
				read_list();
			}
		} else {
			$found -= $nb_elem;
		}
		close_numero();
	} elsif ($cmd eq "home") {
		if ($mode_opened) {
			$mode_sel = 0;
			disp_modes();
			next;
		}
		$found = 0;
		close_numero();
	} elsif ($cmd eq "end") {
		if ($mode_opened) {
			$mode_sel = $#{$list[$found]};
			disp_modes();
			next;
		}
		$found = $#list;
		close_numero();
	} elsif ($cmd eq "insert") {
		print "commande insert found $found\n";
		if (open(F,">rejets/$source.0")) {
			if (open(G,"<rejets/$source")) {
				while (<G>) {
					chomp;
					my ($serv,$flav,$aud,$vid,$n) = split(/:/);
					my $trouve = 0;
					foreach (@{$list[$found]}) {
						my ($num,$name,$service,$flavour,$audio,$video,$red) = @{$_};
						if ($red) {
							$$_[6] = 0;
						}
						if ($service eq $serv && $flavour eq $flav &&
							$aud eq $audio && $video eq $vid) {
							print "insert found $name for $service/$serv $flavour/$flav $aud/$audio $vid/$video\n";
							$trouve = 1;
						}
					}
					print F "$_\n" if (!$trouve);
				}
				close(G);
			}

			close(F);
			unlink "rejets/$source" && rename("rejets/$source.0","rejets/$source");
		}
	} elsif ($cmd eq "reject") {
		if ($source =~ /^(Enregistrements|livetv)/) {
			my $file = $list[$found][0][2];
			print "fichier à effacer $file\n";
			unlink $file;
		} elsif (open(F,">rejets/$source.0")) {
			if (open(G,"<rejets/$source")) {
				while (<G>) {
					chomp;
					my ($serv,$flav,$aud,$vid,$n) = split(/:/);
					my $trouve = 0;
					foreach (@{$list[$found]}) {
						my ($num,$name,$service,$flavour,$audio,$video,$red) = @{$_};
						if ($service eq $serv && $flavour eq $flav &&
							$aud eq $audio && $video eq $vid) {
							$trouve = 1;
							last;
						}
					}
					print F "$_\n" if (!$trouve);
				}
				close(G);
			}
					
			if (!$mode_opened) {
				foreach (@{$list[$found]}) {
					my ($num,$name,$service,$flavour,$audio,$video) = @{$_};
					print F "$service:$flavour:$audio:$video:$name\n";
				}
			} else {
				my ($name,$serv,$flav,$audio,$video) = get_name($list[$found]);
				print F "$serv:$flav:$audio:$video:$name\n";
			}

			close(F);
			unlink "rejets/$source" && rename("rejets/$source.0","rejets/$source");
		} else {
			print "list: Can't open rejects\n";
		}
		read_list();
		close_mode() if ($mode_opened);
	} elsif ($cmd =~ /^zap(1|2)/) {
		# zap1 : zappe sur la sélection en cours
		# zap2 : zappe sur le nom de chaine passé en paramètre
		if ($cmd =~ s/^zap2 //) {
			($found) = find_name($cmd);
		}
		close_numero();
		save_conf();
		my ($name,$serv,$flav,$audio,$video) = get_name($list[$found]);
		$mode_opened = 0 if ($mode_opened);
		if ($source eq "menu") {
			$source = $name;
			read_list();
			if ($source eq "cd") {
				# le cd est en "autostart" !
				goto again;
			}
		} elsif ($source =~ /^(livetv|Enregistrements)$/) {
			load_file2($name,$serv,$flav,$audio,$video);
			next;
		} elsif ($source =~ /^Fichiers/) {
			my $path = ($source eq "Fichiers vidéo" ? "video_path" : "music_path");
			if ($serv eq "tri par") {
				$conf{tri_video} = ($conf{tri_video} eq "nom" ? "date" : "nom");
				read_list();
			} elsif ($name =~ /\/$/) { # Répertoire
				my $old;
				if ($serv eq "..") {
					$conf{$path} =~ s/^(.*)\/(.+)/$1/;
					$old = "$2/";
					$conf{$path} = "/" if (!$conf{$path});
				} else {
					$conf{$path} = $serv;
				}
				my $n;
				read_list();
				for ($n=0; $n<=$#list; $n++) {
					my ($name) = get_name($list[$n]);
					if ($name eq $old) {
						$found = $n;
						last;
					}
				}
			} else {
				load_file2($name,$serv,$flav,$audio,$video);
				next;
			}
		} elsif ($source eq "apps") {
			my ($name,$serv) = get_name($list[$found]);
			if (!$serv) {
				if ($base_flux) {
					$base_flux .= ";$name";
				} else {
					$base_flux = $name;
				}
				read_list();
			} else {
				$serv =~ s/ .+//; # Ne garde que la commande
				if (open(F,"<desktop")) {
					my ($width,$height);
					($width,$height) = <F>;
					chomp $width;
					chomp $height;
					close(F);
					my $margew = sprintf("%d",$width/36);
					my $margeh = sprintf("%d",$height/36);
					$width -= 2*$margew;
					$height -= 2*$margeh;
					my $l = `$serv -h|grep geometry`;
					my ($g) = $l =~ /(\-\-?geometry)/;

					$serv .= " $g $width"."x".$height."+$margew+$margeh" if ($g);
				} else {
					print "pas de fichier desktop\n";
				}
				print "list: exec $serv\n";
				send_command("pause\n");
				kill_player1();
				system("$serv");
				reset_current();
				send_command("pause\n");
				unlink("current"); # pour être sûr que la commande zap passera
				$cmd = "zap1";
				my ($name,$serv,$flav,$audio,$video) = get_name($list[$found]);
				print "would zap to $name,$serv,$flav,$audio,$video\n";
				goto again;
			}
		} elsif ($source =~ /^(flux|cd)/) {
			print "list: source pour lancement $source\n";
			if (!$base_flux) {
				$base_flux = $name;
				$mode_flux = "";
				print "base_flux = $name\n";
				read_list();
			} elsif ($mode_flux eq "list" || $serv !~ /\/\//) {
				$base_flux .= "/$name";
				read_list();
			} else {
				print "lecture flux: load_file2 $serv\n";
				load_file2($name,$serv,$flav,$audio,$video);
				next;
			}
		} else {
			# cas freeboxtv/dvb/radios freebox
			# On a pas trop le choix pour le else à rallonge ici
			# on a besoin que le flux relise sa liste et sans goto c'est la
			# seule façon d'y arriver. Ca va, ça reste lisible quand même...
			open(F,"<current");
			my ($n,$src,$s,$f,$a,$v) =  <F>;
			close(F);
			chomp($s,$f,$a,$v,$src);
			$src =~ s/\/.+//;
			if ($s ne $serv || $flav ne $f || $audio ne $a || $v ne $video || $src ne $source) {
				unlink( "list_coords","info_coords","stream_info",
					"numero_coords");
				$flav = 0 if (!$flav);
				$video = 0 if (!$video);
				$audio = 0 if (!$audio);
				print "list: source $source lancement ./run_mp1 \"$serv\" $flav $audio $video \"$source\" \"$name\"\n";
				# Si player2 ne démarre pas correctement freebox peut se
				# retrouver à boucler dessus et la pipe de commande n'est
				# jamais ouverte dans ce cas là. Il vaut mieux passer par
				# send_command...
				send_command("pause\n") if ($pid_player2);
				system("./run_mp1 \"$serv\" $flav $audio $video \"$source\" \"$name\"");
				send_command("quit\n") if ($pid_player2);
				unlink "fifo_cmd";
				kill "TERM" => $pid_player2 if ($pid_player2);
				system("kill -USR2 `cat info.pid`");
				unlink "id";
				if (open(F,"<current")) { # On récupère le nom de fichier
					(undef,undef,undef,undef,undef,undef,$serv) = <F>;
					chomp $serv;
					close(F);
				}
				print "lancement $name,$src,$serv,$flav,$audio,$video\n";
				$pid_player2 = fork();
				if ($pid_player2 == 0) {
					run_mplayer2($name,$src,$serv,$flav,$audio,$video);
				}
			}
			next;
		}
	} elsif ($cmd =~ /^name /) {
		my @arg = split(/ /,$cmd);
		if ($#arg < 2 && $source =~ /freebox/) {
			print F "syntax: name service flavour [audio] $#arg\n";
		} else {
			if ($source eq "dvb") {
				$cmd =~ s/^name //;
				$arg[1] = $cmd;
			}
			my ($n,$x) = find_channel($arg[1],$arg[2],$arg[3]);
			if (!defined($n)) {
				print F "not found $arg[1] $arg[2]\n";
			} else {
				my ($name) = get_name($list[$n]); # récupère le nom le + court
				print F "$name\n";
			}
		}
		close(F);
		next;
	} elsif ($cmd =~ /^(next|prev) /) {
		my $next;
		$next = $cmd =~ s/^next //;
		$cmd =~ s/^prev //;
		open($lout,">reply_list") || die "can't write reply_list\n";
		if (!$cmd) {
			print $lout "syntax: next|prev <nom de la chaine>\n";
		} else {
			reset_current() if (!-f "list_coords");
			my ($n,$x) = find_name($cmd);
			if (!defined($n)) {
				print $lout "not found $cmd\n";
			} else {
				my $name;
				if ($next) {
					my $next = $n+1;
					$next = 0 if ($next > $#list);
					($name) =get_name($list[$next]); 
					print "next: got $name from $next\n";
				} else {
					my $prev = $n-1;
					$prev = $#list if ($prev < 0);
					($name) =get_name($list[$prev]); 
				}
				print $lout "$name\n";
			}
		}
		close($lout);
		next;
	} elsif ($cmd =~ s/^info //) {
		open($lout,">reply_list") || die "can't write reply_list\n";
		if (!$cmd) {
			print $lout "syntax: info <nom de la chaine>\n";
		} else {
			# si la commande est envoyée par le bandeau d'info tout seul
			# revenir à la source utilisée par la chaine courante
			reset_current() if (! -f "list_coords");
			my ($n,$x) = find_name($cmd);
			if (!defined($n)) {
				print $lout "not found $cmd\n";
			} else {
				print "cmd info: $source,",join(",",@{$list[$n][$x]}),"\n";
				print $lout "$source,",join(",",@{$list[$n][$x]}),"\n";
			}
		}
		close($lout);
		next;
	} elsif ($cmd =~ /^switch_mode/) {
		my @arg = split(/ /,$cmd);
		my $found = 0;
		if ($#arg == 1) {
			for (my $n=0; $n<=$#modes; $n++) {
				if ($modes[$n] eq $arg[1]) {
					$found = $n;
					last;
				}
			}
			$found--;
		} else {
			for (my $n=0; $n<=$#modes; $n++) {
				if ($source eq $modes[$n]) {
					$found = $n;
					last;
				}
			}
		}
		switch_mode($found);
	} elsif ($cmd eq "menu") {
		$source = "menu";
		read_list();
	} elsif ($cmd =~ /^(\d)$/ || $cmd =~ /backspace/i) {
		if (defined($1)) {
			$numero .= $1;
		} else {
			$numero =~ s/\d$//;
			if (!$numero) {
				close_numero();
				next;
			} else {
				clear("numero_coords");
			}
		}

		open(F,">numero_coords");
		close(F);
		if (!-f "list_coords") {
			# Si la liste est affichée faut envoyer cette commande à la fin
			send_bmovl("numero $numero");
		}
		for (my $n=0; $n<=$#list; $n++) {
			my ($num,$name) = @{$list[$n][0]};
			if ($num >= $numero) {
				$found = $n;
				last;
			}
		}
		$time_numero = time()+3;
		if (!-f "list_coords") {
			# Si la liste est affichée de toutes façons ça va provoquer une
			# commande à info, pas la peine de le réveiller
			send_cmd_info("refresh");
			next;
		}
	} elsif ($cmd =~ /^[A-Z]$/) { # alphabétique
		$found = 1 if ($found == 0);
		my $old = $found;
		$cmd = ord($cmd);
		for (; $found <= $#list; $found++) {
			my ($name,$serv,$flav,$audio,$video) = get_name($list[$found]);
			last if (ord(uc($name)) >= $cmd);
		}
		if ($found > $#list || $found == $old) {
			for ($found = 1; $found < $old; $found++) {
				my ($name,$serv,$flav,$audio,$video) = get_name($list[$found]);
				last if (ord(uc($name)) >= $cmd);
			}
		}
			
		if ($found > $#list) {
			# not found
			$found = $old;
			my ($name) = get_name($list[$found]);
			print "list: touche pas trouvée, format : $name\n";
			next;
		} else {
			print "list: touche trouvée, found $found old $old\n";
		}
	} elsif ($cmd =~ /^F(\d+)$/) { # Touche de fonction
		my $nb = $1-2;
		if ($nb > $#modes || $nb == 14) {
			$source = "menu";
			read_list();
		} else {
			switch_mode($nb);
		}
	} elsif ($cmd eq "nextchan") {
		reset_current() if (! -f "list_coords");
		$found++;
		$found = $#list if ($found > $#list);
		$cmd = "zap1";
		goto again;
	} elsif ($cmd eq "prevchan") {
		reset_current() if (! -f "list_coords");
		$found--;
		if ($found >= 0) {
			$cmd = "zap1";
			goto again;
		} else {
			$found = 0;
		}
	} elsif ($cmd eq "reset_current") {
		reset_current();
		next if (!-f "list_coords");
	} elsif ($cmd eq "quit") {
		print "list: commande quit\n";
		system("kill `cat info.pid`");
		system("kill `cat info_pl.pid`") if ((-s "recordings") == 0);
		quit();
	} elsif ($cmd ne "list") {
		print "list: commande inconnue :$cmd!\n";
		next;
	}
	if ($cmd eq "refresh") {
		if ($time_numero && time() >= $time_numero) {
			if ($cmd !~ /^zap/ && $numero) {
				$cmd = "zap1";
				goto again;
			}
			close_numero();
		}
		next if (! -f "list_coords");
	}
	$nb_elem = 16;
	$nb_elem = $#list+1 if ($nb_elem > $#list);

	if ($#list >= 0) {
		$found -= $#list+1 while ($found > $#list);
		$found += $#list+1 while ($found < 0);
	}

	my $beg = $found - 9;
	$beg = 0 if ($beg < 0);
	my $out;

	my $cur = "";
	if (($source eq "flux" || $source eq "cd") && $base_flux) {
		$cur .= "$source > $base_flux\n";
	} elsif ($source =~ /Fichiers/) {
		my $path = ($source eq "Fichiers vidéo" ? "video_path" : "music_path");
		$cur .= "$source : $conf{$path}\n";
	} else {
		$cur .= "$source\n";
	}
	my $n = $beg-1;
	for (my $nb=1; $nb<=$nb_elem; $nb++) {
		last if (++$n > $#list);
		my $rtab = $list[$n];
		my ($num,$name,$service,$flavour,$audio,$video,$red,$pic) = @{$$rtab[0]};
		if ($n == $found) {
			$cur .= "*";
		} elsif ($red) {
			$cur .= "R";
		} elsif ($name =~ /\/$/ && $source =~ /Fichiers/) {
			$cur .= "D"; # Directory (répertoire)
		} else {
			$cur .= " ";
		}
		foreach (@$rtab) {
			my ($temp,$name2) = @$_;
			$name = $name2 if (length($name2) < length($name));
		}
		if (!$num) {
			die "list split failed\n";
		}
		$cur .= sprintf("%3d:%s",$num,($pic ? "pic:$pic " : "").$name);
		if ($#$rtab > 0) {
			$cur .= ">";
		}
		$cur .= "\n";
	}
	if ($cmd ne "refresh" || $cur ne $last_list) {
		if ($source =~ /Fichiers/) {
			$out = setup_output("fsel");
		} elsif ($source eq "flux") {
			$out = setup_output("longlist");
		} else {
			$out = setup_output(($cmd eq "refresh" ? "list-noinfo" : "bmovl-src/list"));
		}
		print $out $cur;
		close($out);
		$last_list = $cur;
	}
	if ($cmd =~ /^(\d|backspace)$/i) {
		send_bmovl("numero $numero");
	}
}
close($l);
print "list à la fin input vide\n";

