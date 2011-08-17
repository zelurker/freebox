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
require "output.pl";

open(F,">info_list.pid") || die "info_list.pid\n";
print F "$$\n";
close(F);

if (open(F,"<current")) {
	@_ = <F>;
	close(F);
}
my ($chan,$source,$serv,$flav) = @_;
chomp ($chan,$source,$serv,$flav);
$chan = lc($chan);
# print "list: obtenu chan $chan source $source serv $serv flav $flav\n";

my (@list);
my $found = undef;

sub read_list {
	if ($source eq "freebox") {
		my $list;
		if (!-f "freebox.m3u" || -M "freebox.m3u" >= 1) {
			$list = get "http://mafreebox.freebox.fr/freeboxtv/playlist.m3u";
			die "can't get freebox playlist\n" if (!$list);
			open(F,">freebox.m3u") || die "can't create freebox.m3u\n";
			print F $list;
			close(F);
		} else {
			open(F,"<freebox.m3u") || die "can't read freebox playlist\n";
			@list = <F>;
			close(F);
			$list = join("\n",@list);
			@list = ();
		}
		my @rejets;
		if (open(F,"<rejets/freebox")) {
			while (<F>) {
				chomp;
				my ($serv,$flav,$audio,$video) = split(/:/);
				push @rejets,[$serv,$flav,$audio,$video];
			}
			close(F);
		}

		Encode::from_to($list, "utf-8", "iso-8859-15");

		my ($num,$name,$service,$flavour,$audio,$video);
		my $last_num = undef;
		@list = ();
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
				foreach (@rejets) {
					if ($$_[0] == $service && $_[1] == $flavour &&
						$$_[3] eq $audio && $$_[4] eq $video) {
						$reject = 1;
						last;
					}
				}
				next if ($reject);

				my @cur = ($num,$name,$service,$flavour,$audio,$video);
				if ($last_num != $num) {
					$last_num = $num;
					push @list,[\@cur];
				} else {
					my $rtab = $list[$#list];
					push @$rtab,\@cur;
				}
				if ($serv == $service && $flav eq $flavour) {
					$found = $#list;
				}
			}
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
			if ($serv eq $service) {
				$found = $#list;
			}
		}
		close(F);
	} elsif ($source eq "livetv") {
		@list = ();
		my $num = 1;
		while (<livetv/*.ts>) {
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
			if ($serv eq $service) {
				$found = $#list;
			}
		}
		print "lecture livetv: $#list\n";
	} else {
		print "read_list: source inconnue $source\n";
	}
}

sub get_name {
	my $rtab = shift;
	my $name = $$rtab[0][1];
	my $sel = $$rtab[0];
	# print "list: looking for $name\n";
	foreach (@$rtab) {
		if (length($$_[1]) < length($name)) {
			$sel = $_;
		}
	}
	# retourne nom, service, flavour, audio, video
	# print  "*** get_name: $$sel[1],$$sel[2],$$sel[3]\n";
	return ($$sel[1],$$sel[2],$$sel[3],$$sel[4],$$sel[5]);
}

sub find_channel {
	my ($serv,$flav,$audio) = @_;
	$flav = "" if ($flav eq "0");
	if ($source eq "freebox") {
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
	return undef;
}

sub switch {
	if ($source eq "dvb") {
		if (! -f "$ENV{HOME}/.mplayer/channels.conf" || ! -d "/dev/dvb") {
			return 0;
		}
	} elsif ($source eq "livetv") {
		my @tab = <livetv/*.ts>;
		return 0 if (!@tab);
	}
	return 1;
}

read_list();
system("rm -f fifo_list && mkfifo fifo_list");
my $nb_elem = 16;
while (1) {
	open(F,"<fifo_list") || die "can't read fifo_list\n";
	my $cmd = <F>;
	chomp $cmd;
	close(F);
	if (-f "list_coords" && $cmd eq "clear") {
		clear("list_coords");
		clear("info_coords");
		next;
	} elsif ($cmd eq "down") {
		$found++;
	} elsif ($cmd eq "up") {
		$found--;
	} elsif ($cmd eq "right") {
		$found += $nb_elem;
	} elsif ($cmd eq "left") {
		$found -= $nb_elem;
	} elsif ($cmd eq "home") {
		$found = 0;
	} elsif ($cmd eq "end") {
		$found = $#list;
	} elsif ($cmd eq "reject") {
		if (open(F,">>rejets/$source")) {
			foreach (@{$list[$found]}) {
				my ($num,$name,$service,$flavour,$audio,$video) = @{$_};
				print F "$service:$flavour:$audio:$video\n";
			}
			close(F);
		} else {
			print "list: Can't open rejects\n";
		}
		splice @list,$found,1;
	} elsif ($cmd =~ /^zap(1|2)/) {
		if ($cmd =~ s/^zap2 //) {
			($found) = find_name($cmd);
		}
		my ($name,$serv,$flav,$audio,$video) = get_name($list[$found]);
		unlink( "list_coords","info_coords");
		if ($source eq "livetv") {
			if (open(F,">fifo_cmd")) {
				print F "pause\n";
				my $pid = `cat player1.pid`;
				chomp $pid;
				print "pid à tuer $pid.\n";
				kill 1,$pid;
			   	unlink "player1.pid";
				print F "loadfile '$serv'\n";
				close(F);
				open(F,">live");
				close(F);
			}
			next;
		}
		$flav = 0 if (!$flav);
		$video = 0 if (!$video);
		$audio = 0 if (!$audio);
		print "lancement ./run_mp1 \"$serv\" $flav $audio $video $source\n";
		system(<<END);
(name=`head -n 7 current|tail -n 1`
 if [ "\$name" != "" ]; then
   mv stream.dump "\$name"
 fi
 echo pause > fifo_cmd
 ./run_mp1 \"$serv\" $flav $audio $video "$source"
 kill `cat player2.pid`
 echo 'End of file' > id) &
END
		next;
	} elsif ($cmd =~ /^name /) {
		open(F,">fifo_list") || die "can't write fifo_list\n";
		my @arg = split(/ /,$cmd);
		if ($#arg < 2 && $source eq "freebox") {
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
		open(F,">fifo_list") || die "can't write to fifo_list\n";
		my $next;
		$next = $cmd =~ s/^next //;
		$cmd =~ s/^prev //;
		if (!$cmd) {
			print F "syntax: next|prev <nom de la chaine>\n";
		} else {
			if (open(A,"<current")) {
				<A>;
				my $src = <A>;
				close(A);
				chomp $src;
				if ($src ne $source) {
					$source = $src;
					read_list();
				}
			}
			my ($n,$x) = find_name($cmd);
			if (!defined($n)) {
				print F "not found $cmd\n";
			} else {
				my $name;
				if ($next) {
					my $next = $n+1;
					$next = 0 if ($next > $#list);
					($name) =get_name($list[$next]); 
				} else {
					my $prev = $n-1;
					$prev = $#list if ($prev < 0);
					($name) =get_name($list[$prev]); 
				}
				print F "$name\n";
			}
		}
		close(F);
		next;
	} elsif ($cmd =~ /^switch_mode/) {
		my @arg = split(/ /,$cmd);
		my @src = (
			"freebox", "dvb", "livetv");
		my $found = 0;
		if ($#arg == 1) {
			for (my $n=0; $n<=$#src; $n++) {
				if ($src[$n] eq $arg[1]) {
					$found = $n;
					last;
				}
			}
			$found--;
		} else {
			for (my $n=0; $n<=$#src; $n++) {
				if ($source eq $src[$n]) {
					$found = $n;
					last;
				}
			}
		}
		do {
			$found++;
			$found = 0 if ($found > $#src);
			$source = $src[$found];
		} while (!switch());
		read_list();
	} elsif ($cmd ne "list") {
		print "list: unknown command :$cmd!\n";
		next;
	}
	$nb_elem = 16;
	$nb_elem = $#list+1 if ($nb_elem > $#list);

	$found -= $#list+1 while ($found > $#list);
	$found += $#list+1 while ($found < 0);

	my $beg = $found - 9;
	$beg = 0 if ($beg < 0);
	my $out = setup_output("bmovl-src/list");
	print $out "$source\n";
	my $n = $beg-1;
	for (my $nb=1; $nb<=$nb_elem; $nb++) {
		$n = 0 if (++$n > $#list);
		if ($n == $found) {
			print $out "*";
		} else {
			print $out " ";
		}
		my $rtab = $list[$n];
		my ($num,$name,$service,$flavour,$audio,$video) = @{$$rtab[0]};
		foreach (@$rtab) {
			my ($temp,$name2) = @$_;
			$name = $name2 if (length($name2) < length($name));
		}
		if (!$num) {
			die "list split failed\n";
		}
		print $out sprintf("%3d:%s",$num,$name);
		if ($#$rtab > 0) {
			print $out ">";
		}
		print $out "\n";
	}
	close($out);
}

