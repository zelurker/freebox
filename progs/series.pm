package progs::series;

use strict;
use warnings;
use progs::telerama;
use WWW::Mechanize;

@progs::series::ISA = ("progs::telerama");

our $debug = 0;

sub get {
	my ($p,$channel,$source,$base_flux) = @_;
	return undef if ($source !~ /Fichiers/);

	if ($channel !~ /^(.+)[ \.]s(\d+)e(\d+)/i) {
		print STDERR "series: format de nom incorrect $channel\n";
		return undef;
	}
	my ($titre,$saison,$episode) = ($1,$2,$3);
	$episode =~ s/^0//; # tronque le 0 éventuel de l'épisode, pour allocine
	$saison =~ s/^0//;
	my $sum = "";
	my $img = "";
	my $cast = "";
	my $sub;

	if (!-f "cache/$channel.info") {
		if (!open(F,">cache/$channel.info")) {
			print STDERR "séries : impossible de créer cache/$channel.info\n";
			return undef;
		}
		my $mech = WWW::Mechanize->new();
		$mech->agent_alias("Linux Mozilla");
		$mech->timeout(12);
		$mech->default_header('Accept-Encoding' => scalar HTTP::Message::decodable());
		$mech->get("https://www.google.fr/");
		my $r = $mech->submit_form(
			form_number => 1,
			fields      => {
				q => "allocine $titre saison $saison",
			}
		);
		# On récupère le lien du haut du résultat :
		my $dump = 0;
		my $actor = 0;
		my $u;
		foreach ($mech->links) {
			$u = $_->url;
			if ($u =~ /url.q=(http.+?)&/) {
				$u = $1;
				last;
			}
		}
		for (my $page=1; $page<=2; $page++) {
			print STDERR "url $u page $page\n" if ($debug);
			# passer ajax avant ?page pour une version text only
			# mais si on veut les images il faut la totale...
			eval {
				$mech->get($u."?page=$page");
			};
			if ($@) {
				print STDERR "mechanize error $@\n";
				return undef;
			}
			$_ = $mech->content;
			my $first = 0;
			foreach (split /\n/,$_) {
				if (/Ep\. $episode /) {
					s/\<.+?\>//g;
					$sum .= $_;
					$dump = 1;
					next;
				} elsif ($dump) {
					if (/\/td/) {
						$dump = 0;
						next;
					}
					s/\<.+?\>//g;
					if ($sum =~ /\w$/) {
						if (!$first) {
							$first = 1;
							$sub = $sum;
							print STDERR "sub $sub\n";
							$sum = "";
						} else {
							$sum .= "\n";
						}
					}
					$sum .= $_;
				} elsif (/itemprop="actor"/) {
					$actor = 1;
					next;
				} elsif ($actor) {
					if (/\/li/) {
						$actor = 0;
						next;
					}
					if (/img src='(http.+?)'/) {
						$img = $1 if (!$img);
					} elsif (/alt='(.+?)'/) {
						$cast .= "$1 ";
					} elsif (/(Rôle .+?)<\//) {
						$cast .= "$1 ";
					}
				}
			} # foreach
			last if ($sum ne "");
		}
		print F "$titre Saison $saison Episode $episode\n$sub\n";
		if ($img) {
			print F "img:$img\n";
		}
		print F "$sum\n\n";
		if ($cast) {
			print F "Casting :\n";
			print F $cast;
		}
		close(F);
	} else {
		open(F,"<cache/$channel.info");
		<F>; # title
		$sub = <F>;
		$sum = "";
		chomp $sub;
		while (<F>) {
			$sum .= $_;
			if ($sum =~ /^img:/) {
				chomp $sum;
				$sum =~ /img:(.+)/;
				$img = $1;
				$sum = "";
			}
		}
		close(F);
	}
	my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
		$atime,$mtime,$ctime,$blksize,$blocks) = stat($channel);
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
	localtime($mtime);
	my $date = sprintf("%02d/%02d/%d",$mday,$mon+1,$year+1900);

	my @tab = (undef, # chan id
		"$source", "$titre Saison $saison Episode $episode",
		undef, # début
		undef, "", # fin
		$sub, # desc
		$sum, # details
		"",
		$img, # img
		0,0,
		$date);
	return \@tab;
}

1;
