#!/usr/bin/perl

# Gestion des listes
# Accepte les commandes par une fifo : fifo_list

use strict;
use Socket;
use POSIX qw(strftime :sys_wait_h SIGALRM);
use Encode;
use Fcntl;
use File::Glob 'bsd_glob'; # le glob dans perl c'est n'importe quoi !
use out;
use chaines;
require "mms.pl";
require "radios.pl";
use HTML::Entities;

our $latin = ($ENV{LANG} !~ /UTF/i);
our ($inotify,$watch);
use Linux::Inotify2;
$inotify = new Linux::Inotify2;
$inotify->blocking(0);
our $dvd;
our $encoding;

our $net = out::have_net();
our $have_fb = 0; # have_freebox
$have_fb = out::have_freebox() if ($net);
our $have_dvb = (-f "$ENV{HOME}/.mplayer/channels.conf" && -d "/dev/dvb");
our ($l);
our $pid_player2;
open(F,">info_list.pid") || die "info_list.pid\n";
print F "$$\n";
close(F);
my $numero = "";
my $time_numero = undef;
my $last_list = "";
our $update_pic = 0;

$SIG{PIPE} = sub { print "list: sigpipe ignoré\n" };

my @modes = (
	"freeboxtv",  "dvb", "Enregistrements", "Fichiers vidéo", "Fichiers son", "livetv", "flux","radios freebox",
	"cd","dvd","apps");
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

my ($chan,$source,$serv,$flav) = out::get_current();
# Si base_flux contient une recherche + quelque chose d'autre, tronque à la
# recherche. On ne peut pas restaurer l'url d'une vidéo précise, il vaut mieux
# retourner sur la recherche
$source =~ s/result:(.+?)\/.+/result:$1/;
$source =~ s/\/(.+)//;
my $base_flux = $1;
chomp ($chan,$source,$serv,$flav);
$chan = lc($chan);
$source = "freeboxtv" if (!$source);
# print "list: obtenu chan $chan source $source serv $serv flav $flav\n";

our (@list);
our $found = undef;
my $mode_flux;
our %conf;

sub update_pics {
	my $rpic = shift;
	if (!@$rpic) {
		print "update_pics: pas d'images\n";
		return;
	}
	$update_pic = fork();
	if ($update_pic == 0) {
		for (my $n=0; $n<=$#$rpic; $n+=2) {
			if (open(my $f,">$$rpic[$n]")) {
				my ($type,$cont) = chaines::request($$rpic[$n+1]);
				print "debug: url $$rpic[$n+1] -> type $type\n";
				print $f $cont;
				close($f);
				# print "updated pic $$rpic[$n] from ",$$rpic[$n+1],"\n";
				out::send_cmd_list("refresh");
			}
		}
		exit(0);
	}
}

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
	return if ($base_flux =~ /youtube/);
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
		# mplayer2 inclut un test pour quitter tout de suite si y a pas de cd
		# mplayer passe 3 plombes dans ce cas là !
		open(F,"mplayer2 -cdrom-device $cd cddb:// -nocache -identify -frames 0|");
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
					Encode::from_to($fields{name}, "utf-8", "iso-8859-1") if ($latin);
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

sub list_files {
	@list = ();
	my ($path,$tri);
	if ($source eq "Fichiers vidéo") {
		$path = "video_path";
		$tri = "tri_video";
	} elsif ($source eq "dvd") {
		$path = "dvd_path";
		$conf{"dvd_path"} = $dvd;
		$tri = "tri_video";
	} else {
		$path = "music_path";
		$tri = "tri_music";
	}
	if ($watch) {
		$watch->cancel;
	}
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
			if ($conf{$tri} eq "hasard") {
				push @paths,bsd_glob("$service/*");
				next;
			}
			$name .= "/";
		}
		next if ($name =~ /\.nfo$/i && $conf{$tri} eq "hasard");

		# On aimerait bien utiliser is_utf8 ici, sauf qu'en fait si le flag
		# utf8 de perl n'est pas positionné sur la chaine ça renvoie toujours
		# faux, donc aucun intérêt. A priori y a toujours un caractère 0xc3
		# devant les accents classiques français, j'ai pas tout vérifié donc
		# pas sûr que ça marche partout, mais j'ai pas trouvé non plus de
		# détection générique utf8. Pour l'instant ça marche en tous cas !
		if ($latin && $name =~ /[\xc3\xc5]/) {
			# c3 est pour la plupart des accents
			# c5 est pour le oe collé.
			eval {
				Encode::from_to($name, "utf-8", "iso-8859-1");
			}; # trop idiot autrement !
			if ($@) {
				print "list_files: pb conversion utf $name\n";
			}
		} elsif (!$latin && $name =~ /[\xc3\xc5]/) {
			$encoding = "utf8";
		}
		push @list,[[$num++,$name,$service,-M $service]];
	}
	unlink "info_coords";
	if ($conf{$tri} eq "date") {
		@list = sort { $$a[0][3] <=> $$b[0][3] } @list;
	} elsif ($conf{$tri} eq "hasard") {
		my @list2;
		while (@list) {
			push @list2,splice(@list,rand($#list+1),1);
		}
		@list = @list2;
	}
	if ($conf{$path} ne "/") {
		unshift @list,[[$num++,"../",".."]];
	}
	unshift @list,[[$num++,"Tri par nom","tri par nom"],
	[$num++,"Tri par date", "tri par date"],
	[$num++,"Tri aléatoire", "tri par hasard"]];
	if ($inotify) {
		print "adding watch for $conf{$path}\n";
		$watch = $inotify->watch($conf{$path},IN_MODIFY|IN_CREATE|IN_DELETE,
			,sub {
				my $e = shift;
				print "*** inotify update $e->{w}{name}\n";
				my ($old) = get_name($list[$found]);
				read_list();
				for (my $n=0; $n<=$#list; $n++) {
					my ($name) = get_name($list[$n]);
					if ($name eq $old) {
						$found = $n;
						last;
					}
				}
			});
		print "got watch $watch\n";
	} else {
		print "no inotify\n";
	}
#		@list = reverse @list;
}

sub read_list {
#	print "list: read_list source $source base_flux $base_flux mode_flux $mode_flux\n";
	if (!$base_flux) {
		$found = $conf{"sel_$source"};
	}
	if ($source =~ /free/ && !$have_fb) {
		$source = "menu";
	}
	if ($source eq "menu") {
		@list = ();
		$base_flux = "";
		my $nb = 1;
		foreach (@modes) {
			push @list,[[$nb++,$_]];
		}
	} elsif ($source eq "apps") {
		apps_menu();
	} elsif ($source eq "cd") {
		cd_menu();
	} elsif ($source eq "dvd") {
		@list = ([[1,"mplayer"]],
		[[2,"vlc"]],
		[[3,"eject"]]);
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
			$list = chaines::request("http://mafreebox.freebox.fr/freeboxtv/playlist.m3u");
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

		eval {
			Encode::from_to($list, "utf-8", "iso-8859-1") if ($latin && $list !~ /débit/);
		};

		if ($@) {
			print "read_list: pb conversion utf $list\n";
		}

		my ($num,$service,$flavour);
		my $last_num = undef;
		@list = ();
		my $tv;
		$tv = 1 if ($source eq "freeboxtv" || $source eq "freebox");
		my @pic = ();
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
				my $pic = chaines::get_chan_pic($name,\@pic);
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
		update_pics(\@pic);
		if (!$tv) {
			@list = sort { $$a[0][1] cmp $$b[0][1] } @list;
		}
	} elsif ($source eq "dvb") {
		my $f;
		open($f,"<$ENV{HOME}/.mplayer/channels.conf") || die "can't open channels.conf\n";
		@list = ();
		my $num = 1;
		my @pic = ();
		while (<$f>) {
			chomp;
			my @fields = split(/\:/);
			my $service = $fields[0];
			my $name = $service;
			$name =~ s/\(.+\)//; # name sans le transpondeur
			my $pic = chaines::get_chan_pic($name,\@pic);
			push @list,[[$num++,$name,$service,undef,undef,undef,undef,$pic]];
		}
		close($f);
		update_pics(\@pic);
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
		list_files();
	} elsif ($source eq "flux") {
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
				$b =~ s/(.+?)\/(.+)/$1/;
			}
			$encoding = "";
			if (-x "flux/$b") {

				# Ok, ça peut être valable d'expliquer les retours des plugins
				# executables :
				# si ça commence par http ou mms -> lien direct
				# Si c'est Recherche, traité en interne, base_flux est reseté
				# et vaut plugin/result:ce qu'on cherche
				# On peut passer Recherche:libellé pour changer le libellé
				# affiché pour la recherche.
				# Si ça commence par un +, base_flux est aussi reseté et
				# contient ce qui suit le +
				# Si y a un espace dans ce qui est retourné c'est pris pour
				# une liste, sauf pour youtube (youtube passe le flux audio de
				# cette façon).
				# Un peu bordelique tout ça, mais bon, ça marche pas mal...

				my ($name,$serv,$flav,$audio,$video) = get_name($list[$found]);
				print "name $name,$serv,$flav,$audio,$video mode_flux $mode_flux base_flux $base_flux\n";
				if ($base_flux =~ /result:/ && $base_flux !~ /result:.*\// &&
					$serv =~ /http/) {
					$serv = ""; # Sinon on ne peut plus revenir avec la flèche
					# gauche !!!
					print "reset serv\n";
				}
				if ($serv =~ /^Recherche/) {
					my ($libelle) = $serv =~ /^Recherche\:(.+)/;
					$libelle = "A chercher (regex)" if (!$libelle);
					delete $ENV{WINDOWID};
					$serv = `zenity --entry --text="$libelle"`;
					chomp $serv;
					if ($encoding =~ /utf/i && $latin) {
						eval {
							Encode::from_to($serv, "iso-8859-1", "utf-8") ;
						};
						if ($@) {
							print "read_list2: pb conv utf $serv\n";
						}
					} else {
						print "encoding $encoding lang $ENV{LANG}\n";
					}
					$serv = "result:$serv";
					$base_flux =~ s/^(.+?)\/.+$/$1\/$serv/;
				} elsif ($serv =~ /^\+/) { # commence par + -> reset base_flux
					$serv =~ s/^.//; # Supprime le + !
					if ($serv !~ /http/) {
						$base_flux =~ s/^(.+?)\/.+$/$1\/$serv/;
					} else {
						$base_flux =~ s/^(.+?)\/.+$/$1/;
					}
					print "après simplification base_flux $base_flux\n";
				} elsif (!$mode_flux && $base_flux !~ /\//) {
					# pas de mode (list ou direct)
					$serv = "";
					$base_flux =~ s/^(.+?)\/.+/$1/;
				} elsif ($serv !~ /^(http|mms|prog)/ && $base_flux !~ /podcasts/ && $serv !~ /\//) {
					# Endroit merdique : on se retrouve serv = valeur
					# retournée et on veut l'arborescence des valeurs à la
					# place, dispo dans base_flux sauf que base_flux
					# utilise uniquement les libellés, pas les valeurs !!!
					# Je ne suis pas sûr que la méthode ici soit fiable
					# dans tous les cas, j'en doute même mais bon le
					# principe c'est :
					# on récupère base_flux, on vire l'entête (nom du
					# plugin) et on remplace le dernier élément par la
					# vraie valeur retournée.
					# Attention en cas de retour (flèche gauche), serv ne
					# vaut rien, cas particulier
					#
					# Solution à long terme : avoir une liste des valeurs
					# en + de celles des libellés...
					print "serv valait $serv\n";
					my @arg = split(/\//,$base_flux);
					$arg[$#arg] = $serv if (defined($serv));
					$serv = join("/",@arg[1...$#arg]);
					print "reconstitution serv = $serv\n";
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
				if ($mode_flux =~ /encoding/) {
					$encoding = $mode_flux;
					$mode_flux = <F>;
				}
				chomp $mode_flux;
			} else {
				if (!open(F,"<flux/$base_flux")) {
					return;
				}
			}
			@list = ();
			my @pic = ();
			my $last = undef;
			while (<F>) {
				if (/encoding:/) {
					$encoding = $_;
					print "encoding: $encoding\n";
					next;
				}
				my $name = $_;
				my $service = <F>;
				chomp ($name,$service);
				next if ($last && $last eq $name);
				$last = $name;
				my $pic = undef;
				if ($name =~ s/^pic:(.+?) //) {
					$pic = $1;
				}
				eval {
					if ($latin && $encoding =~ /utf/i) {
						Encode::from_to($name, "utf-8", "iso-8859-1")
					} elsif (!$latin && $encoding !~/utf/i) {
						Encode::from_to($name, "iso-8859-1","utf-8")
					}
				};
				if ($@) {
					print "read_list: pb3 conv utf $name\n";
				}
				if ($pic) {
					my $file = out::get_cache($pic);
					if (!-f $file || -z $file) {
						push @pic,($file,$pic);
					}
					$name = "pic:$file ".decode_entities($name);
				} else {
					$name = decode_entities($name);
				}
				$name =~ s/&#39;/'/g;

				if ($base_flux eq "stations") {
					my $pic = get_radio_pic($name,\@pic);
					push @list,[[$num++,$name,$service,undef,undef,undef,undef,$pic]];
				} else {
					push @list,[[$num++,$name,$service]];
				}
			}
			if (@pic) {
				update_pics(\@pic);
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
	#return ($$sel[1],$$sel[2],$$sel[3],$$sel[4],$$sel[5]);
	return @$sel[1..$#$sel];
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
			if (chaines::conv_channel($list[$n][$x][1]) eq $name) {
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
	$base_flux = undef;
	read_list();
}

sub reset_current {
	# replace tout sur current
	my $f;
	my ($name,$src) = out::get_current();
	if ($name) {
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

sub mount_dvd() {
	if (open(my $f,"</proc/sys/dev/cdrom/info")) {
		while (<$f>) {
			chomp;
			if (/drive name:[ \t]*(.+)/) {
				$dvd = "/dev/$1";
			} elsif (/Can read DVD.+1/) {
				last;
			}
		}
		close($f);
	} else {
		print "Can't get dvd drive, assuming /dev/dvd\n";
		$dvd = "/dev/dvd";
	}
	if (open(my $f,"</proc/mounts")) {
		while (<$f>) {
			my ($dev,$mnt) = split(/ /);
			if ($dev eq "$dvd") {
				$dvd = $mnt;
				close($f);
				return;
			}
		}
	}
	close(F);
	system("mount $dvd");
	my $f;
	if (open($f,"</proc/mounts")) {
		while (<$f>) {
			my ($dev,$mnt) = split(/ /);
			if ($dev eq "$dvd") {
				$dvd = $mnt;
				last;
			}
		}
	}
	close($f);
}

sub run_mplayer2 {
	my ($name,$src,$serv,$flav,$audio,$video) = @_;
	$l = undef; # Ne ferme pas ça dans le fils !!!
	if ($serv =~ /^get,\d+:.+/) {
		# lien get : download géré par le plugin
		print "lien get détecté: $serv\n";
		my ($b) = $base_flux =~ /(.+?)\/.+/;
		print "b reconst: $b\n";
		if (-x "flux/$b") {
			open(F,"flux/$b \"$serv\"|");
			$serv = <F>;
			chomp $serv;
			print "Récupéré le lien $serv à partir de flux/$b\n";
			close(F);
		}
	}
	unlink "fifo_cmd","fifo";
	system("mkfifo fifo_cmd fifo");
	my $player = "mplayer2";
	my $cache = 100;
	my $filter = "";
	my $cd = "";
	my $pwd;
	chomp ($pwd = `pwd`);
	my $quiet = "";
	if ($serv =~ /(mms|rtmp|rtsp)/ || $src =~ /youtube/ || ($serv =~ /:\/\// &&
		$serv =~ /(mp4|avi|asf|mov)$/)) {
		$cache = 1000;
	}
	if ($serv =~ /^https/) {
		# Apparemment mplayer2 ne peut pas lire de l'https !!!
		$player = "mplayer";
	}
	if ($src =~ /cd/) {
		$quiet = "-quiet";
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
		}
		# le cache du cd n'est pas nécessaire sur toutes les configs
		# mais ça aide pour mon ata. Quel cache alors ça ! Les valeurs
		# élevées provoquent un délai entre le moment où on voit une piste
		# commencer à l'écran et on entend son début.
		# En + le cache nécessaire semble varier en fonction du cd !
		# (peut-être un effet de la lib paranoia ?)
		# 200 semble le minimum absolu avec un certain cd, 250 pour avoir
		# un peu de marge
		$cache = 250;
		# if ($serv =~ /cddb/) {
			$player = "mplayer";
			# }
		$serv =~ s/ http.+//; # Stations de radio, vire l'url du prog
	} else {
		$audio = "-aid $audio " if ($audio);
		if ($src =~ /youtube/ && $serv =~ s/ (http.+)//) {
			$audio = $1;
		}
		if ($src =~ /Fichiers vidéo/) {
# 			if ($name =~ /(mpg|ts)$/) {
# 				$filter = ",kerndeint";
# 			}
			$cache = 5000;
		} elsif ($src =~ /(freeboxtv|dvb|livetv)/) {
			$filter = ",kerndeint";
			$player = "mplayer2";
		}
	}
	my ($dvd1,$dvd2,$dvd3);
	if ($serv =~ /iso$/i || $src eq "dvd") {
		$serv = $dvd;
		if ($flav eq "mplayer") {
			$dvd1 = "-dvd-device";
			$dvd2 = "-nocache";
			$dvd3 = "dvdnav://";
			$filter = ",kerndeint";
		} else {
			exec("vlc","-f","--deinterlace","-1",$serv);
		}
	}

	if ($player eq "mplayer2" && $serv =~ /(avi|mkv$)/ &&
		# Dilemne : mplayer2 ne supporte pas le x265, mais mplayer est
		# bourré de bugs ! Donc on continue à avoir mplayer2 par défaut
		# sauf sur les fichiers où on ne trouve pas la vidéo avec lui !
	   	open(F,"$player -frames 0 -identify -frames 0 \"$serv\"|")) {
		my $found_video = 0;
		while (<F>) {
			if (/ID_VIDEO_FORMAT/) {
				$found_video = 1;
				last;
			}
		}
		close(F);
		$player = "mplayer" if (!$found_video);
	}
	my @list = ("perl","filter_mplayer.pl",$player,$dvd1,$serv,
		# Il faut passer obligatoirement nocorrect-pts avec -(hard)framedrop
		# Apparemment options interdites avec vdpau, sinon on perd la synchro !
#			"-framedrop", # "-nocorrect-pts",
#	   	"-autosync",10,
		"-fs",
		"-stop-xscreensaver","-identify",$quiet,"-input",
		"nodefault-bindings:conf=$pwd/input.conf:file=fifo_cmd","-vf",
		"bmovl=1:0:fifo$filter,screenshot",$dvd2,$dvd3);
	if ($audio) {
		if ($src =~ /youtube/) {
			push @list,("-audiofile",$audio);
		} else {
			push @list,$audio;
		}
	}
	push @list,("-cdrom-device","/dev/$cd") if ($cd);
	# fichier local (commence par /) -> pas de cache !
	# Eviter le cache sur la hd en local donne une sacrée amélioration !
	if ($src =~ /youtube/ && $audio) {
		# Pour les adaptive fmts de youtube
		# vaut mieux désactiver le cache sinon le délai
		# initial avant que ça commence est vraiment trop long
		push @list,("-nocache");
	} else {
		# Pas sûr qu'une valeur par défaut de 100 du cache soit sensée, ça casse la lecture des cds audio
		# donc je ne passe un cache que si on a une valeur spéciale !
		push @list,("-cache",$cache) if ($serv !~ /^(\/|livetv|records)/ && $cache > 100);
	}
	# hr-mp3-seek : lent, surtout quand on revient en arrière, mais
	push @list,("-hr-mp3-seek") if ($serv =~ /mp3$/);
	push @list,("-demuxer","lavf") if ($player eq "mplayer" && $serv =~ /\.ts$/);
	for (my $n=0; $n<=$#list; $n++) {
		last if ($n > $#list);
		if (!$list[$n]) {
			splice(@list,$n,1);
			redo;
		}
	}
	print join(",",@list),"\n";
	exec(@list);
}

sub load_file2 {
	# Même chose que load_file mais en + radical, ce coup là on kille le player
	# pour redémarrer à froid sur le nouveau fichier. Obligatoire quand on vient
	# d'une source non vidéo vers une source vidéo par exemple.
	# retourne 1 si on a lancé un lecteur, 0 si on a juste modifié la liste
	my ($name,$serv,$flav,$audio,$video) = @_;
	my $prog;
	$prog = $1 if ($serv =~ s/ (http.+)//);
	if ($serv =~ /(jpe?g|png|gif|bmp)$/i) {
		system("feh \"$serv\"");
		return 1;
	}
	if ($serv =~ /m3u$/) {
		my $old_base = $base_flux;
		$base_flux .= "/$name";
		my $tv = ($name =~ /TV/i);
		my $radio = ($name =~ /radio/i);
		if (!$tv && !$radio) {
			$tv = ($base_flux =~ /tv/i);
			$radio = ($base_flux =~ /radio/i);
		}
		print "m3u base_flux $base_flux serv $serv name $name\n";
		my ($type,$cont);
		if ($serv =~ /http/) {
			($type,$cont) = chaines::request($serv);
		} else {
			my $f;
			if (open($f,"<$serv")) {
				while (<$f>) {
					$cont .= $_;
				}
				close($f);
				$serv =~ s/^(.+\/).+?$/$1/; # ne garde que le répertoire
			}
		}
		if (!$cont) {
			my @cur = (1,$type);
			@list = [\@cur];
			return 0;
		}
		eval {
			Encode::from_to($cont, "utf-8", "iso-8859-1") if ($latin && $type =~ /utf/);
		};
		if ($@) {
			print "load_file2: pb conv utf $cont\n";
		}
		my @old = @list;
		if ($cont =~ /^#EXTM3U/) {
			@list = ();
		} else {
			$base_flux = $old_base;
		}
		my $num = 1;
		my $name = "";
		my @pic = ();
		foreach (split /\n/,$cont) {
			next if (/^\#EXTM3U/);
			s/\r//; # pour ête sûr !
			if (/^#EXTINF:\-?\d*\,(.+)/ || /^#EXTINF:(.+)/) {
				$name = $1;
			} elsif (/^#/) {
				next;
			} elsif ($name) {
				$serv = $_;
				my $pic = undef;
				if ($tv) {
					$pic = chaines::get_chan_pic($name,\@pic);
				} elsif ($radio) {
					$pic = get_radio_pic($name,\@pic);
				}
				print "push $num,$name,$serv (tv $tv radio $radio)\n";
				my @cur = ($num++,$name,$serv,undef,undef,undef,undef,$pic);
				push @list,[\@cur];
				$name = undef;
			} elsif (-f "$serv$_") { # liste de fichiers locaux
				$serv .= $_;   # prend juste le 1er et sort !
				for ($found=0; $found<=$#list; $found++) {
					my ($name) = get_name($list[$found]);
					last if ($name eq $_);
				}
				$cont = undef;
				last;
			} else {
				$serv = $_;
			}
		}
		if ($#list == 0) { # 1 seule entrée dans le m3u
			@list = @old;
			$cont = undef;
			$base_flux = $old_base;
			# $serv va juste être passé à la suite...
		}
		return 0 if ($cont && $serv =~ /m3u$/);
	}
	if ($serv !~ /^cddb/ && $serv !~ /(mp3|ogg|flac|mpc|wav|aac|flac|ts)$/i) {
	    # Gestion des pls supprimée, mplayer semble les gérer
	    # très bien lui même.
		my $old = $serv;
	    $serv = get_mms($serv) if ($serv =~ /^http/ && $serv !~ /youtube/);
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
			out::clear( "list_coords","info_coords","video_size");
			system("kill -USR2 `cat info.pid`");
		}
		out::send_command("pause\n");
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
		return 1;
	}
	return 0;
}

sub get_cur_mode {
	# Détermine si on est sur la chaine qui passe, un bazar
	my (undef,$src,$serv,$flav) = out::get_current();
	if ($src) {
		if ($src ne "freeboxtv") {
			return 0; # Toujours le 1er mode sur une chaine différente
		}
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
	my $out = out::setup_output("mode_list");
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
	out::clear("mode_coords");
	$mode_opened = 0;
}

sub close_numero {
	$time_numero = undef;
	if (defined($numero)) {
		out::clear("numero_coords");
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
		} elsif ($child == $update_pic) {
			print "update pic over\n";
			disp_list();
			$update_pic = 0;
		}
# 		if (! -f "info_coords") {
# 			print "plus d'info_coords, bye\n";
# 			return;
# 		}
	}
}

sub quit {
	close($l);
   	unlink "fifo_list","reply_list","info_list.pid";
   	exit(0);
}

$SIG{CHLD} = \&REAPER;
$SIG{TERM} = \&quit;
my $nb_elem = 16;
my $init = 1;
my $cmd = "list";
my $lout;
while (1) {
	if ($init) {
		$init = 0;
	} else {
		$cmd = undef;
	}
	# Il faut coller ça dans un eval sinon on est presque sûr d'avoir un couac
	# pendant la récupération de beaucoup d'images (fin du process -> sig child
	# -> interrompt la lecture fifo -> fermeture !
	eval {
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
	};
	$inotify->poll if ($inotify);
	again:
	# print "list: commande reçue après again : $cmd\n";
	if (-f "list_coords" && $cmd eq "clear") {
		out::clear("list_coords");
		out::clear("info_coords");
		close_mode() if ($mode_opened);
		out::send_bmovl("image");
		next;
	} elsif ($cmd eq "refresh") {
		my $found0 = $found;
		read_list() if (!$inotify && $source eq "Enregistrements");
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
		next if (! -f "list_coords");
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
		if (($source eq "flux" && $found-9+$nb_elem > $#list) || $mode_opened) {
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
			if ($found < $#list) {
				$found += $nb_elem;
				$found = $#list if ($found > $#list);
			}
		}
		close_numero();
	} elsif ($cmd eq "left") {
		if ($mode_opened) {
			close_mode();
			out::send_bmovl("image");
			next;
		}
		if ($found < $nb_elem || $nb_elem == 0) {
			if ($source =~ "flux" && $base_flux) {
				if ($base_flux =~ /\//) {
					$base_flux =~ s/(.+)\/.+/$1/;
					if ($base_flux =~ /\//) {
						$mode_flux = "list";
						my ($name,$serv,$flav,$audio,$video) = get_name($list[$found]);
						print "left: $name,$serv,$flav,$audio,$video\n";
						$serv =~ s/\/$//; # supprime un éventuel / à la fin
						# Remet le "bon" service dans la liste
						$serv =~ s/(\/http.+)/\/http/; # vire un http (direct)
						# si $serv contient des /, alors il a déjà le
						# chemin complet pour la sélection actuelle, du
						# coup il faut virer 2 niveaux !
						if (!($serv =~ s/^(.+)\/.+\/.+/$1/)) {
							$base_flux =~ /.+\/(.+)/;
							$serv = $1;
							print "left: corr base_flux $serv\n";
						} else {
							print "left: replace $name,$serv\n";
						}
						$list[$found] = [[$found,$name,$serv,$flav,$audio,$video]];
						($name,$serv,$flav,$audio,$video) = get_name($list[$found]);
						print "left: après màj $name,$serv,$flav,$audio,$video\n";
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
		if ($source =~ /^(Fichiers|Enregistrements|livetv)/) {
			my $file = $list[$found][0][2];
			print "fichier à effacer $file\n";
			unlink $file;
			unlink "$file.info";
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
		my ($name,$serv,$flav,$audio,$video) = get_name($list[$found]);
		# Attention : fermer mode APRES get_name !!!
		close_mode if ($mode_opened);
		save_conf() if ($serv ne "..");
		if ($source eq "menu") {
			$source = $name;
			read_list();
			if ($source eq "cd") {
				# le cd est en "autostart" !
				goto again;
			}
		} elsif ($source eq "dvd") {
			mount_dvd();
			if ($base_flux eq "dvd") {
				next if (exec_file($name,$serv,$audio,$video));
			} elsif ($name eq "eject") {
				system("eject $dvd");
				next;
			} else {
				if (-d "$dvd/VIDEO_TS" || -d "$dvd/video_ts") {
					next if (load_file2("dvd","dvd",$name));
				} else {
					$base_flux = "dvd";
					list_files();
				}
			}
		} elsif ($source =~ /^(livetv|Enregistrements)$/) {
			next if (load_file2($name,$serv,$flav,$audio,$video));
		} elsif ($source =~ /^Fichiers/) {
			next if exec_file($name,$serv,$audio,$video);
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
				out::send_command("pause\n");
				system("$serv");
			}
		} elsif ($source =~ /^(flux|cd)/) {
#			print "list: serv $serv source pour lancement $source/$base_flux mode_flux $mode_flux\n";
			if (!$base_flux) {
				$base_flux = $name;
				$base_flux =~ s/pic:.+? //;
				$mode_flux = "";
				print "base_flux = $name\n";
				read_list();
			} elsif ($mode_flux eq "list" || (($serv !~ /\/\// ||
					($serv =~ / / && $base_flux !~ /youtube/)) && $mode_flux)) {
				$name =~ s/\//-/g;
				$base_flux .= "/$name";
				$base_flux =~ s/pic:.+? //;
				read_list();
			} else {
				print "lecture flux: load_file2 $serv\n";
				next if (load_file2($name,$serv,$flav,$audio,$video));
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
				# out::send_command...
				out::send_command("pause\n") if ($pid_player2);
				system("./run_mp1 \"$serv\" $flav $audio $video \"$source\" \"$name\"");
				out::send_command("quit\n") if ($pid_player2);
				unlink "fifo_cmd";
				kill "TERM" => $pid_player2 if ($pid_player2);
				system("kill -USR2 `cat info.pid`");
				unlink "id";
				if (open(F,"<current")) { # On récupère le nom de fichier
					(undef,undef,undef,undef,undef,undef,$serv) = <F>;
					chomp $serv;
					close(F);
				}
				print "lancement $name,$source,$serv,$flav,$audio,$video\n";
				$pid_player2 = fork();
				if ($pid_player2 == 0) {
					run_mplayer2($name,$source,$serv,$flav,$audio,$video);
				}
			}
			next;
		}
		next if (! -f "list_coords");
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
				print F "$name,$source/$base_flux\n";
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
				print $lout "$source/$base_flux,",join(",",@{$list[$n][$x]}),"\n";
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
				out::clear("numero_coords");
			}
		}

		open(F,">numero_coords");
		close(F);
		if (!-f "list_coords") {
			# Si la liste est affichée faut envoyer cette commande à la fin
			out::send_bmovl("numero $numero");
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
			out::send_cmd_info("refresh");
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
		if ($found > $#list) {
			if ($source =~ /^Fichiers /) {
				$found = 1; # Pointe sur ..
				my ($name,$serv,$flav,$audio,$video) = get_name($list[$found]);
				exec_file($name,$serv,$audio,$video);
				goto again;
			} else {
				$found = 0;
			}
		}
		if ($source =~ /^Fichiers /) {
			my ($name,$serv,$flav,$audio,$video) = get_name($list[$found]);
			if ($name =~ /\/$/) { # Répertoire
				exec_file($name,$serv,$audio,$video);
				$found = 1; # On se place au début...
				goto again; # et on y retourne !
			}
		}
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
	if ($source =~ /Fichiers/ && @list && !$inotify) {
		# Si on est sur une liste de fichiers, relit le répertoire à chaque
		# fois
		my ($old) = get_name($list[$found]);
		read_list();
		for (my $n=0; $n<=$#list; $n++) {
			my ($name) = get_name($list[$n]);
			if ($name eq $old) {
				$found = $n;
				last;
			}
		}
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
	disp_list();
}
close($l);
print "list à la fin input vide\n";

sub get_sort_key {
	my $key;
	if ($source eq "Fichiers vidéo" || $source eq "dvd") {
		$key = "tri_video";
	} else {
		$key = "tri_music";
	}
	$key;
}

sub exec_file {
	# Retour : 0 si la liste a changé, 1 autrement (next)
	my ($name,$serv,$audio,$video) = @_;
	my $path;
	if ($source eq "Fichiers vidéo") {
		$path = "video_path";
	} elsif ($source =~ / son/) {
		$path = "music_path";
	} elsif ($source eq "dvd") {
		$path = "dvd_path";
	}
	if ($serv =~ /^tri par/) {
		print "$name,$serv,$audio,$video\n";
		my $key = get_sort_key();
		$conf{$key} = substr($serv,8);
		print "$key = $conf{$key}.\n";
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
		return 1;
	}
	return 0;
}

sub disp_list {
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
	my $have_pic = undef;
	for (my $nb=1; $nb<=$nb_elem; $nb++) {
		last if (++$n > $#list);
		my $rtab = $list[$n];
		my ($num,$name,$service,$flavour,$audio,$video,$red,$pic) = @{$$rtab[0]};
		$have_pic = 1 if ($pic);
		if ($n == $found) {
			$cur .= "*";
		} elsif ($red) {
			$cur .= "R";
		} elsif ($name =~ /\/$/ && $source =~ /Fichiers/) {
			$cur .= "D"; # Directory (répertoire)
		} else {
			$cur .= " ";
		}
		if ($n == 0 && $name =~ /^Tri par/) {
			$name = "Tri par ".$conf{get_sort_key()};
		} else {
			foreach (@$rtab) {
				my ($temp,$name2) = @$_;
				$name = $name2 if (length($name2) < length($name));
			}
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
	if ($cmd ne "refresh" || $cur ne $last_list || $update_pic) {
		my $info = 0;
		if ($source =~ /Fichiers/) {
			$out = out::setup_output("fsel");
		} elsif ($source eq "flux" && $base_flux ne "stations" && !$have_pic) {
			$info = 1 if ($base_flux =~ /^(la-bas|podcasts|arte)/);
			$out = out::setup_output("longlist");
		} else {
			$out = out::setup_output(($cmd eq "refresh" ? "list-noinfo" : "bmovl-src/list"));
			$info = 1;
		}
		if (!$latin && $source ne "flux" && $encoding !~ /utf/) {
			# A priori il n'y a que les plugins de flux qui renvoient des
			# trucs en utf8 ou qui convertissent autrement, tout le reste
			# est en latin
			eval {
				Encode::from_to($cur, "iso-8859-1", "utf-8") ;
			};
			if ($@) {
				print "read_list2: pb conv utf $serv\n";
			}
		}
		print $out $cur;
		close($out);
		print "command prog source $source base_flux $base_flux\n";
		if ($found <= $#list) {
			my $rtab = $list[$found];
			my ($num,$name,$service,$flavour,$audio,$video,$red,$pic) = @{$$rtab[0]};
			if ($source =~ /(Enregistrement|livetv)/) {
				out::send_cmd_info("prog $service§$source/$base_flux") if ($info);
			} else {
				out::send_cmd_info("prog $name§$source/$base_flux,$service") if ($info);
			}
		}
		$last_list = $cur;
	}
	if ($cmd =~ /^(\d|backspace)$/i) {
		out::send_bmovl("numero $numero");
	}
	if (open(F,"<list_coords")) {
		<F>;
		$nb_elem = <F>;
		chomp $nb_elem;
		close(F);
		print "récup nb_elem $nb_elem\n";
	}
}

# vim: encoding=latin1

