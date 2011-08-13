#!/usr/bin/perl

# Gestion de la liste de chaines
# Accepte les commandes par une fifo : fifo_list
# commandes reconnues :
# down, up, right, left : déplacement dans la liste
# name service flavour : renvoie le nom de la chaine sur la fifo
# next/prev service flavour : renvoie le nom de la chaine suivante/précédente
# zap1 : zappe sur la chaine sélectionnée dans la liste
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

open(F,"<current") || die "no current file\n";
my ($chan,$source,$serv,$flav) = <F>;
close(F);
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
			} elsif (/^audio-track-id=(\d+)/) {
				$audio = $1;
			} elsif (/service=(\d+)/) {
				$service = $1;
				if (/flavour=(.+)/) {
					$flavour = $1;
				}
				die "pas de numéro pour $_\n" if (!$num);
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
	# retourne nom, service, flavour
	# print  "*** get_name: $$sel[1],$$sel[2],$$sel[3]\n";
	return ($$sel[1],$$sel[2],$$sel[3]);
}

sub find_channel {
	my ($serv,$flav) = @_;
	if ($source eq "freebox") {
		for (my $n=0; $n<=$#list; $n++) {
			for (my $x=0; $x<=$#{$list[$n]}; $x++) {
				if ($list[$n][$x][2] == $serv &&
					$list[$n][$x][3] eq $flav) {
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
	} elsif ($cmd eq "zap1") {
		my ($name,$serv,$flav) = get_name($list[$found]);
		unlink( "list_coords","info_coords");
		system("(echo pause > fifo_cmd && ./run_mp1 \"$serv\" $flav && ".
		"kill `cat player2.pid` && echo 'End of file' > id) &");
		next;
	} elsif ($cmd =~ /^name /) {
		open(F,">fifo_list") || die "can't write fifo_list\n";
		my @arg = split(/ /,$cmd);
		if ($#arg != 2 && $source eq "freebox") {
			print F "syntax: name service [flavour] $#arg\n";
		} else {
			if ($source eq "dvb") {
				$cmd =~ s/^name //;
				$arg[1] = $cmd;
			}
			my ($n,$x) = find_channel($arg[1],$arg[2]);
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
		open(F,">fifo_list") || die "can't write fifo_list\n";
		my @arg = split(/ /,$cmd);
		if ($#arg != 2) {
			print F "syntax: next|prev service flavour\n";
		} else {
			my ($n,$x) = find_channel($arg[1],$arg[2]);
			if (!defined($n)) {
				print F "not found $arg[1] $arg[2]\n";
			} else {
				my $name;
				if ($cmd =~ /^next/) {
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
	} elsif ($cmd eq "switch_mode") {
		if ($source eq "freebox") {
			if (-f "$ENV{HOME}/.mplayer/channels.conf") {
				$source = "dvb";
				read_list();
			}
		} else {
			$source = "freebox";
			read_list();
		}
	} elsif ($cmd ne "list") {
		print "unknown command :$cmd!\n";
		next;
	}

	$found -= $#list+1 while ($found > $#list);
	$found += $#list+1 while ($found < 0);

	my $beg = $found - 9;
	$beg += $#list+1 if ($beg < 0);
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

