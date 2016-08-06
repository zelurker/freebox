package progs::html::finter;

use HTML::Entities;
use Time::Local "timelocal_nocheck";
use Encode;

sub get_date {
	my $time = shift;
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime($time);
	sprintf("%d/%02d/%02d",$mday,$mon+1,$year+1900);
}

sub decode_html {
	my ($p,$l,$name) = @_;
	my $rtab = [];
	my $pos = 0;
	my ($time,$date);
	if ($l =~ /<a href="\/programmes\/(\d+)-(..)-(..)" title="Jour pr/) {
		my ($y,$m,$d) = ($1,$2,$3);
		$y -= 1900;
		$m--;
		$time = timelocal_nocheck( 0, 0, 0, $d, $m, $y );
		$time += 24*3600; # jour actuel
		$date = get_date($time);
	}
	my $time0 = $time;
	while (($pos = index($l,"<span",$pos))> 0) {
		my $heure = substr($l,$pos+6,5);
		if ($heure !~ /^\d/) {
			$pos++;
			next;
		}
		# print "$time ";
		my ($h,$m) = $heure =~ /(\d+)h(\d+)/;
		if ($h < 5) {
			$time = $time0 + 24*3600;
			$date = get_date($time);
		}
		my $start = $time + $h*3600+$m*60;
		my $end = $time + ($h+1)*3600;
		my ($desc,$title,$img);
		while (1) {
			$pos = index($l,"<",$pos+1);
			if (substr($l,$pos+1,1) eq "a") {
				my $sub = substr($l,$pos+1);
				$sub =~ s/>.+//;
				my $class;
				if ($sub =~ /class="(.+?)"/) {
					$class = $1;
				}
				if ($sub =~ /title="(.+?)"/) {
					my $tit = $1;
					if ($class =~ /emission-title/) {
						$title = $tit;
						# Après faut sortir tout de suite de la boucle !!!
						$pos = index($l,"<span>",$pos+1);
						last;
					} elsif ($class =~ /content-title/) {
						$desc = $tit;
					}
				}
			} elsif (substr($l,$pos+1,3) eq "img") {
				my $sub = substr($l,$pos+1);
				$sub =~ s/>.+//;
				if ($sub =~ /data-pagespeed-high-res-src="(.+?)"/) {
					$img = $1;
				} elsif ($sub =~ / src="(.+?)"/) {
					$img = $1;
				}
			} elsif (substr($l,$pos+1,5) eq "span>") {
				last;
			}
		}
		if (substr($l,$pos+1,4) eq "span") {
			foreach ($desc,$title) {
				s/&#(\d+);/chr($1)/ge;
				s/&amp;/\&/g;
				# utf8::decode(decode_entities($_));
				s/\xe2\x80\x99/'/g;
				Encode::from_to($_, "utf-8", "iso-8859-1");
			}
			my @tab = (undef, $name, $title, $start,
				$end, "",
				$desc,
				"","",$img,0,0,$date);
			$p->insert(\@tab,$rtab,600);
			redo;
		}
	}
	$rtab;
}

1;

