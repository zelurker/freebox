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

use strict;
use LWP::Simple;
use Encode;
use Fcntl;
use File::Glob 'bsd_glob'; # le glob dans perl c'est n'importe quoi !
require "output.pl";
require "mms.pl";

open(F,">info_list.pid") || die "info_list.pid\n";
print F "$$\n";
close(F);
my $numero = "";
my $time_numero = undef;
my $last_list = "";

$SIG{PIPE} = sub { print "list: sigpipe ignoré\n" };

my @modes = (
	"freeboxtv",  "dvb", "Enregistrements", "Fichiers vidéo", "Fichiers son", "livetv", "flux","radios freebox",
	"cd");
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
		while (<F>) {
			chomp;
			if (/(ID.+?)\=(.+)/) {
				my ($name,$val) = ($1,$2);
				print "scanning $name = $val\n";
				if ($name eq "ID_CDDB_INFO_ARTIST") {
					$base_flux = "$val - ";
				} elsif ($name eq "ID_CDDB_INFO_ALBUM") {
					$base_flux .= $val;
				} elsif ($name =~ /ID_CDDB_INFO_TRACK_\d+_NAME/) {
					$track = $val;
					print "track = $track\n";
				} elsif ($name =~ /ID_CDDB_INFO_TRACK_(\d+)_MSF/) {
					push @list,[[$1,"$track ($val)","cddb://$1-99"]];
				} elsif ($name =~ /ID_CDDA_TRACK_(\d+)_MSF/) {
					push @list_cdda,[[$1,"pas d'info cddb ($val)","cdda://$1-99"]] if ($val ne "00:00:00");
				}
			} elsif (/500 Internal Server Error/) {
				$error = 1;
			}
		}
		close(F);
	} while ($error && ++$tries <= 3);
	$found = 0;
	@list = @list_cdda if (!@list);
}

sub read_freebox {
	my $list;
	open(F,"<freebox.m3u") || die "can't read freebox playlist\n";
	@list = <F>;
	close(F);
	$list = join("\n",@list);
	@list = ();
	$list;
}

sub read_list {
#	print "list: read_list source $source base_flux $base_flux mode_flux $mode_flux\n";
	if ($base_flux) {
		$found = $conf{"sel_$source\_$base_flux"};
	} else {
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
	} elsif ($source eq "cd") {
		cd_menu();	
	} elsif ($source =~ /freebox/) {
		my $list;
		my ($name,$serv,$flav,$audio,$video) = get_name($list[$found]);
		if (!-f "freebox.m3u" || -M "freebox.m3u" >= 1) {
			$list = get "http://mafreebox.freebox.fr/freeboxtv/playlist.m3u";
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

		Encode::from_to($list, "utf-8", "iso-8859-15");

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

				my @cur = ($num,$name,$service,$flavour,$audio,$video,$red);
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
		open(F,"<$ENV{HOME}/.mplayer/channels.conf") || die "can't open channels.conf\n";
		@list = ();
		my $num = 1;
		while (<F>) {
			chomp;
			my @fields = split(/\:/);
			my $service = $fields[0];
			my $name = $service;
			$name =~ s/\(.+\)//; # name sans le transpondeur
			push @list,[[$num++,$name,$service]];
		}
		close(F);
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
				$serv = "" if (!$mode_flux);
				open(F,"flux/$b $serv|");
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
				push @list,[[$num++,$name,$service]];
			}
			print "list: ".($#list+1)." flux\n";
			$found = 0 if ($found > $#list);
			close(F);
		}
	} else {
		print "read_list: source inconnue $source\n";
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

sub switch {
	my $source = shift;
	if ($source eq "dvb") {
		if (! -f "$ENV{HOME}/.mplayer/channels.conf" || ! -d "/dev/dvb") {
			return 0;
		}
	}
	return 1;
}

sub reset_current {
	# replace tout sur current
	if (open(A,"<current")) {
		my $name  = <A>;
		my $src = <A>;
		close(A);
		chomp($name, $src);
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

sub load_file($) {
	my $serv = shift;
	# charge le fichier pointé dans la liste (contenu dans $serv)
	send_command("pause\n");
	my $p1 = undef;
	if (-f "player1.pid") {
	    $p1 = 1;
	    my $pid = `cat player1.pid`;
	    chomp $pid;
	    print "pid à tuer $pid.\n";
	    kill "TERM",$pid;
	    unlink "player1.pid";
	}
	send_command("loadfile '$serv'\n");
	print "loadfile envoyée ($serv)\n";
	send_command("pause\n") if (!$p1);
	open(F,">live");
	close(F);
	unlink( "list_coords","info_coords");
}

sub load_file2($$$$$) {
	# Même chose que load_file mais en + radical, ce coup là on kille le player
	# pour redémarrer à froid sur le nouveau fichier. Obligatoire quand on vient
	# d'une source non vidéo vers une source vidéo par exemple.
	my ($name,$serv,$flav,$audio,$video) = @_;
	$serv =~ s/ (http.+)//;
	my $prog = $1;
	send_command("pause\n");
	if (-f "player1.pid") {
	    my $pid = `cat player1.pid`;
	    chomp $pid;
	    print "pid2 à tuer $pid.\n";
	    kill "TERM",$pid;
	    unlink "player1.pid";
	}
	if ($serv !~ /(mp3|ogg|flac|mpc|wav|aac|flac)$/i) {
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
		unlink( "list_coords","info_coords","video_size");
		system("kill -USR2 `cat info.pid`");
		open(G,">current");
		my $src = ($source eq "cd" ? "flux" : $source);
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
		system("kill `cat player2.pid`");
		send_command("quit\n");
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
system("rm -f fifo_list && mkfifo fifo_list");
$SIG{TERM} = sub { unlink "fifo_list"; };
my $nb_elem = 16;
while (1) {
	open(F,"<fifo_list") || die "can't read fifo_list\n";
	my $cmd = <F>;
	chomp $cmd;
	close(F);
	again:
	print "list: commande reçue après again : $cmd\n";
	if (-f "list_coords" && $cmd eq "clear") {
		clear("list_coords");
		clear("info_coords");
		close_mode() if ($mode_opened);
		my $out = open_bmovl();
		print $out "image\n";
		close($out);
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
			next;
		}
		if ($source eq "flux" && $base_flux && 
		    ($found < $nb_elem || $nb_elem == 0)) {
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
			load_file($serv);
			next;
		} elsif ($source =~ /^Fichiers/) {
			my $path = ($source eq "Fichiers vidéo" ? "video_path" : "music_path");
			if ($serv eq "tri par") {
				$conf{tri_video} = ($conf{tri_video} eq "nom" ? "date" : "nom");
				read_list();
			} elsif ($name =~ /\/$/) { # Répertoire
				if ($serv eq "..") {
					$conf{$path} =~ s/^(.*)\/.+/$1/;
					$conf{$path} = "/" if (!$conf{$path});
				} else {
					$conf{$path} = $serv;
				}
				read_list();
			} else {
				load_file2($name,$serv,$flav,$audio,$video);
				next;
			}
		} elsif ($source eq "flux" || $source eq "cd") {
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
				print "lancement ./run_mp1 \"$serv\" $flav $audio $video \"$source\" \"$name\"\n";
				# Si player2 ne démarre pas correctement freebox peut se
				# retrouver à boucler dessus et la pipe de commande n'est
				# jamais ouverte dans ce cas là. Il vaut mieux passer par
				# send_command...
				send_command("pause\n");
				system("./run_mp1 \"$serv\" $flav $audio $video \"$source\" \"$name\"");
				send_command("quit\n");
				unlink "fifo_cmd";
				# La séquence suivante est un hack pas beau mais jusqu'ici
				# je n'ai pas trouvé mieux : on quitte mplayer en lui envoyant
				# quit, mais du coup ça provoque le message id_exit=quit avant
				# de sortir, du coup il n'y a aucun moyen de le différencier
				# d'une commande quit envoyée par l'utilisateur. Et là en l'
				# occurence vu qu'on vient de relancer run_mp1, il faut que
				# freebox boucle. Donc je kille carrément le filtre dont le pid
				# est maintenant dans player2.pid avant qu'il ait pu recopier
				# le message de fin et je vire id pour être sûr !
				# Pas terrible tout ça, vraiment ! Mais bon ça a l'air de
				# marcher...
				system("kill `cat player2.pid`; kill -USR2 `cat info.pid`");
				unlink "id";
			}
			next;
		}
	} elsif ($cmd =~ /^name /) {
		open(F,">fifo_list") || die "can't write fifo_list\n";
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
		open(R,">fifo_list") || die "can't write to fifo_list\n";
		my $next;
		$next = $cmd =~ s/^next //;
		$cmd =~ s/^prev //;
		if (!$cmd) {
			print R "syntax: next|prev <nom de la chaine>\n";
		} else {
			reset_current() if (!-f "list_coords");
			my ($n,$x) = find_name($cmd);
			if (!defined($n)) {
				print R "not found $cmd\n";
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
				print R "$name\n";
			}
		}
		close(R);
		next;
	} elsif ($cmd =~ s/^info //) {
		open(R,">fifo_list") || die "can't write to fifo_list\n";
		if (!$cmd) {
			print R "syntax: info <nom de la chaine>\n";
		} else {
			# si la commande est envoyée par le bandeau d'info tout seul
			# revenir à la source utilisée par la chaine courante
			reset_current() if (! -f "list_coords");
			my ($n,$x) = find_name($cmd);
			if (!defined($n)) {
				print R "not found $cmd\n";
			} else {
				print "cmd info: $source,",join(",",@{$list[$n][$x]}),"\n";
				print R "$source,",join(",",@{$list[$n][$x]}),"\n";
			}
		}
		close(R);
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
		do {
			$found++;
			$found = 0 if ($found > $#modes);
			$source = $modes[$found];
		} while (!switch($source));
		read_list();
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
			my $out = open_bmovl();
			if ($out) {
				print $out "numero $numero\n";
				close($out);
			}
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
		my $old = $found;
		for (; $found <= $#list; $found++) {
			my ($name,$serv,$flav,$audio,$video) = get_name($list[$found]);
			last if ($name =~ /^$cmd/i);
		}
		if ($found > $#list) {
			# not found
			$found = $old;
			next;
		}
	} elsif ($cmd eq "nextchan") {
		reset_current() if (! -f "list_coords");
		$found++;
		if ($found <= $#list) {
			$cmd = "zap1";
			goto again;
		} else {
			$found = $#list;
		}
	} elsif ($cmd eq "prevchan") {
		reset_current() if (! -f "list_coords");
		$found--;
		if ($found >= 0) {
			$cmd = "zap1";
			goto again;
		} else {
			$found = 0;
		}
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
		my ($num,$name,$service,$flavour,$audio,$video,$red) = @{$$rtab[0]};
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
		$cur .= sprintf("%3d:%s",$num,$name);
		if ($#$rtab > 0) {
			$cur .= ">";
		}
		$cur .= "\n";
	}
	if ($cmd ne "refresh" || $cur ne $last_list) {
		if ($source =~ /Fichiers/) {
			$out = setup_output("fsel");
		} else {
			$out = setup_output(($cmd eq "refresh" ? "list-noinfo" : "bmovl-src/list"));
		}
		print $out $cur;
		close($out);
		$last_list = $cur;
	}
	if ($cmd =~ /^(\d|backspace)$/i) {
		my $out = open_bmovl();
		if ($out) {
			print $out "numero $numero\n";
			close($out);
		}
	}
}

