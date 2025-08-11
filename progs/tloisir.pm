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

sub conv_time {
	my $time = shift;
	# convertit en affichable, debugage uniquement
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime($time);
	sprintf("%d/%d/%d, %02d:%02d",$mday,$mon+1,$year+1900,$hour,$min);
}

sub update {
	my ($p,$channel,$offset) = @_;
	my $prog = $p->{list}->{$channel}[4];
	my ($base,$suffix) = $prog =~ /^(.+)(\/.+)/;
	my $label = $p->{list}->{$channel}[2];
	if (!$prog) {
		$p->error("pas de prog pour cette chaine");
		return undef;
	}

	my ($sec,$min,$hour,$mday,$mon,$year) = localtime(time()+$offset*24*3600);
	my $orig = $#{$chaines{$channel}};
	$prog = $base.sprintf("/%d-%02d-%02d",$year+1900,$mon+1,$mday).$suffix;
	my $chan = $channel;
	$chan =~ s/ /-/g;
	my $f = sprintf("%02d%02d%d-$chan",$mday,$mon+1,$year+1900);
	my $r = http::myget($prog,"cache/tloisir/$f");
	if ($r) {
		my ($img,$start,$title,$details,$duration,$sub,$stop);
		while (1) {
			($img,$start,$title,$details,$duration,$sub) = undef;
			while($r =~ s/data-broadcast-id(.+?)<\/div//s) {
				$img = $1;
				next if ($img =~ /noPlaceHolder/i);
				next if ($img =~ /url\(/);
				last if (!$img || $img =~ /<(img|svg)/);
			}
			if (!$img) {
				say "sortie sur pas d'image";
				last;
			}
			if ($img =~ /data-src/) {
				$img =~ /data-src="(.+?)"/; $img = $1;
				my $size;
				if ($img =~ /, /) {
					($size) = $img =~ /(\d+)x/;
					foreach (split /, /,$img) {
						my ($s2) = /(\d+)x/;
						if ($s2 > $size) {
							say "found greater size $s2 > $size";
							$size = $s2;
							$img = $_;
						}
					}
				}
			} else {
				if ($img =~ /src="(.+?)"/) {
					$img = $1;
				} else {
					$img = undef;
				}
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
			} elsif ($duration =~ /(\d+)min/) {
				$duration = $1*60;
			} elsif ($duration =~ /(\d+)h/) {
				$duration = $1*3600;
			}
			$stop = $start + $duration;
			# say "got img $img start ",conv_time($start)," title $title details $details duration $duration stop ",conv_time($stop)," sub $sub";
			my @sub = ($details, # num ?
				$label,$title,
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
		$p->{chaines} = \%chaines; # pour prev/next prog
		if ($orig > 0) {
			my @tab = sort { $$a[3] <=> $$b[3] } @{$chaines{$channel}};
			$chaines{$channel} = \@tab;
		}

		return $chaines{$channel};
	}
}

sub valid {
	my ($p,$rtab,$refresh) = @_;
	# la chance de valider avant affichage, de quoi récupérer les trucs qui manquent
	my $url = $$rtab[0];
	my ($prog) = $url =~ /.+\/(.+)/;
	$prog =~ s/\/$//;
	$url = "https://www.programme-tv.net$url" if ($url =~ /^\//);
	my $img;
	my $r = http::myget($url,"cache/tloisir/$prog");
	while($r =~ s/<div class="pictureTagGenerator(.+?)<div//s) {
		$img = $1;
		next if ($img =~ /noPlaceHolder/i);
		next if ($img =~ /url\(/);
		last if (!$img || $img =~ /<img/);
	}
	$img =~ /srcset="(.+?)"/;
	my $set = $1;
	$img =~ /src="(.+?)"/;
	$img = $1;
	my ($size) = $img =~ /(\d+)x/;
	foreach (split /, /,$set) {
		my ($s2) = /(\d+)x/;
		if ($s2 > $size) {
			$size = $s2;
			s/ \d+w$//;
			$img = $_;
		}
	}
	$$rtab[9] = $img;
	my $sub;
	if ($r =~ s/div class="synopsis-text">(.+?)<\/div//s ||
		$r =~ s/<span class="programCollectionSeason.episodesListItemSynopsisText.+?>(.+?)<\/span>//s) {
		$sub = $1;
		$sub =~ s/&nbsp;/ /g; # caractère bizarre au lieu de l'espace pour decode_entities!
		$sub =~ s/<span.+?>//g;
		$sub =~ s/<\/span>//g;
		$sub =~ s/ +/ /g;
		$sub =~ s/(\n|\r)//g;
		$sub =~ s/^ //;
		$sub = decode_entities($sub);
		$$rtab[7] = $sub;
	}
	while ($r =~ s/li class="overview-stickerInfoListItem(.+?)<\/li>//s) {
		my $info = $1;
		$info =~ /strong>(.+)<\/strong>(.+)/;
		$sub = "" if (!defined($sub));
		$sub .= "$1$2\n";
		$$rtab[7] = $sub;
	}
	while ($r =~ s/<span class="ratingsReport-typeTitle">(.+?)<\/span>.+?([\d\.]+)<\/span>//s) {
		my $stars = "$1 : $2";
		next if ($stars =~ /^votre note/i);
		$$rtab[10] = "" if (!$$rtab[10]);
		$$rtab[10] .= "\n" if ($$rtab[10]);
		$$rtab[10] .= $stars;
	}
}

1;
