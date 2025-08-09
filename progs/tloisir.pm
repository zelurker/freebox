package progs::tloisir;

use strict;
use warnings;
use progs::telerama;
use Cpanel::JSON::XS qw(decode_json);
use HTML::Entities;
use Time::Local "timelocal_nocheck","timegm_nocheck";
use v5.10;
use Data::Dumper;
# require "http.pl";

@progs::tloisir::ISA = ("progs::telerama");

my %chaines;

sub update {
	my ($p,$channel,$offset) = @_;
	my $prog = $p->{list}->{$channel}[4];
	return undef if ($offset); # que le jour même pour l'instant
	if (!$prog) {
		$p->error("pas de prog pour cette chaine");
		return undef;
	}

	my ($sec,$min,$hour,$mday,$mon,$year) = localtime();
	my $chan = $channel;
	$chan =~ s/ /-/g;
	my $f = sprintf("%02d%02d%d-$chan",$mday,$mon+1,$year+1900);
	my $r = http::myget($prog,"cache/tloisir/$f");
	if ($r) {
		my ($img,$start,$title,$details,$duration,$sub,$stop);
		my $nb = 0;
		while (1) {
			($img,$start,$title,$details,$duration,$sub) = undef;
			while($r =~ s/<div class="pictureTagGenerator(.+?)<div//s) {
				$img = $1;
				next if ($img =~ /noPlaceHolder/i);
				next if ($img =~ /url\(/);
				last if (!$img || $img =~ /<img/);
			}
			last if (!$img);
			if ($img =~ /data-src/) {
				$img =~ /data-src="(.+?)"/; $img = $1;
			} else {
				$img =~ /src="(.+?)"/; $img = $1;
			}
			$r =~ s/<p class="mainBroadcastCard-startingHour.+?>(.+?)<\/p//s;
			$start = $1;
			last if (!$start);
			$start =~ s/^.+(\d\d)h(\d\d).+/$1h$2/s;
			$start = timelocal_nocheck(0,$2,$1,$mday,$mon,$year);
			# Y a pas toujours de sous titre, donc on récupère le titre jusqu'au tag d'après, brodcast type dont on se fout pour inclure le sous titre éventuel
			$r =~ s/<h3 class="mainBroadcastCard-title(.+?)<div class="mainBroadcastCard-type//s;
			$title = $1;
			$title =~ /href="(.+?)"/;
			$details = $1;
			if ($title =~ s/<p class="mainBroadcastCard-subtitle">(.+?)<\/p>//s) {
				$sub = $1;
				$sub =~ s/ +/ /;
				$sub =~ s/(\n|\r)//g;
				$sub =~ s/^ //;
				$sub = decode_entities($sub);
			}
			$title =~ /title="(.+?)"/;
			$title = decode_entities($1);
			$r =~ s/<span class="mainBroadcastCard-durationContent">(.+?)<\/span//s;
			$duration = $1;
			if ($duration =~ /(\d+)h(\d+)min/) {
				$duration = $2*60 + $1*3600;
			} else {
				$duration =~ /(\d+)min/;
				$duration = $1*60;
			}
			$stop = $start + $duration;
			# say "nb $nb got img $img start $start title $title details $details duration $duration stop $stop sub $sub";
			my @sub = (1, # num ?
				$details,$title,
				$start,$stop,
				"", # genre, on l'a mais en s'en fout
				$sub,"",
				0, # rating
				$img,
				0, # stars
				"", # critique
				sprintf("%d/%d/%d",$mday,$mon+1,$year+1900),
				"" # showview
			);
			my $rtab = $chaines{$channel};
			if ($rtab) {
				push @$rtab,\@sub;
			} else {
				$chaines{$channel} = [\@sub];
			}
		}

		return $chaines{$channel};
	}
}

1;
