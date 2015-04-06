package progs::series;

use strict;
use warnings;
# use utf8;
use HTML::Entities;
use progs::telerama;
use WWW::Mechanize;
use Encode;

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
	my $sum = "";
	my $img = "";
	my $cast = "";
	my $sub;

	if (!-f "$channel.info") {
		if (!open(F,">$channel.info")) {
			print STDERR "séries : impossible de créer $channel.info\n";
			return undef;
		}
		my $mech = WWW::Mechanize->new();
		$mech->agent_alias("Linux Mozilla");
		$mech->timeout(10);
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
		foreach ($mech->links) {
			my $u = $_->url;
			if ($u =~ /url.q=(http.+?)&/) {
				$u = $1;
				print "lien : $_->text soit $u\n";
				$mech->get($u);
				last;
			}
		}
		$_ = $mech->content;
		my $first = 0;
		foreach (split /\n/,$_) {
			if (/Ep\. $episode/) {
				s/\<.+?\>//g;
				$sum .= decode_entities($_);
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
		open(F,"<$channel.info");
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
