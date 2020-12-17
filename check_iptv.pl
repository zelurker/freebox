#!/usr/bin/perl

use common::sense;
no utf8;
use Fcntl;
use NDBM_File;

# vu que le site de listes iptv met un captcha javascript sur leur écran de
# login c'est pas possible facilement de se loguer par un script. Du coup
# il faut passer la page html résultat de la recherche à ce script qui se
# charge de vérifier les urls listées. Une url est validée si y a un canal
# vidéo et un audio. Il vérifie aussi si une url n'est pas présentée + d'1
# fois parce que j'avais des doutes, mais apparemment non, il y a toujours
# une légère différence ! En tous cas, beaucoup + efficace que de faire ça
# à la main !

my %valid = ();
my %bad;
my ($name,$search);
my $fich = shift @ARGV || die "pass file to check (html)";
my $path = $fich;
($path) = $path =~ /^(.+)\//;
open(F,"<$fich") || die "can't open $fich";
my $get_link = 0;
while(<F>) {
	if (/<input.*type="search".*value="(.+?)"/) {
		$search = $1;
		say "search results for $search";
		mkdir "badips";
		tie(%bad, "NDBM_File","badips/$search", O_RDWR|O_CREAT,0666) || die "can't tie bad $!";
		my @keys = keys %bad;
		say "bad ips : ",$#keys+1;
	} elsif (/<h2 .*<img src="(.+?)"/) {
		my $data = $1;
		$data =~ s/%20/ /g;
		$data =~ s/%c2%ab/«/gi;
		$data =~ s/%c2%bb/»/gi;
		$data =~ s/%e2%80%94/—/gi;
		$data = "$path/$data";
		if (-s $data == 307) {
			$get_link = 1;
		} elsif (-s $data == 565) {
			$get_link = 0;
		} else {
			die "taille fichier image $data non reconnue : ".(-s $data);
		}
	} elsif ($get_link && /^ *<a.*class="playlist__title-link.+?>(.+?)<\/a/) {
		say "$1.";
		$name = $1;
	} elsif ($get_link && /<div class="playlist_syntax-stream">(.+?)</) {
		my $url = $1;
		if ($bad{$url}) {
			say "already tested $url (bad)";
		} else {
			test($url);
		}
	}
}
close(F);

say;
say "au final :";
foreach (sort { $a cmp $b } keys %valid) {
	say "$_ : $valid{$_}";
}
untie %bad if ($search);

sub test {
	my $url = shift;
	print "testing link $url ";
	my ($pid,$g);
	eval {
		local $SIG{ALRM} = sub { die "alarm"; };
		alarm(5);
		$pid = open($g,"mpv -frames 1 --network-timeout=5 '$url' 2> /dev/null|");
		if (!$pid) {
			die "pas de commande mpv ?!!!\n";
		}
		my $valid = 0;
		while (<$g>) {
			chomp;
			print "$_ " if (/Failed/);
			if (/ (Audio|Video) /) {
				$valid++;
			}
		}
		close($g);
		$g = undef;
		if ($valid == 2) {
			print STDERR "ok\n";
			$valid{$url} = $name;
		} else {
			$bad{$url} = 1;
			print "not ok\n";
		}
		alarm(0);
	};
	if ($g) {
		kill TERM => $pid;
		say "not ok (timeout)";
		$bad{$url} = 1;
		close($g);
	}
}


