package progs::finter;

# Refonte été 2016 de finter : ça ne marche plus par de l'xml apparemment,
# maintenant c'est de la page html brute apparemment ! Heuremsent ça n'a
# pas l'air trop dur d'extraire l'info... !

use strict;
# use warnings;
use progs::telerama;
@progs::finter::ISA = ("progs::telerama");
use Data::Dumper;
use HTML::Entities;
use Time::Local "timelocal_nocheck";
use Encode;

my $debug = 0;

our %fb = (
	"bleu loire ocean" => "http://www.francebleu.fr/sites/default/files/lecteur_commun_json/timeline-13125.json",
	"bleu gascogne" => "http://www.francebleu.fr/sites/default/files/lecteur_commun_json/timeline-13113.json",
);

sub update_prog($) {
	my $file = shift;
	my $url = $file;
	my ($base,$date) = $url =~ /^(.+?)-(.+)/;
	if ($base eq "finter") {
		$url = "https://www.franceinter.fr/programmes/$date";
	}
	my ($status,$prog) = chaines::request($url);
	print STDERR "update_prog: got status $status, prog $prog\n" if ($debug && $prog);
	return if (!$prog);
	open(my $f,">cache/$file");
	return if (!$f);
	print $f $prog;
	close($f);
	return $prog;
}

sub get_date {
	my $time = shift;
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime($time);
	sprintf("%d/%02d/%02d",$mday,$mon+1,$year+1900);
}

sub decode_html {
	my ($l,$name,$rtab) = @_;
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
			push @$rtab,\@tab;
			if ($$rtab[$#$rtab-1][4] > $start) {
				$$rtab[$#$rtab-1][4] = $start;
			}
			redo;
		}
	}
	$rtab;
}

sub update {
	my ($p,$channel,$offset) = @_;
	return undef if (lc($channel) !~ /france (inter)/); # |culture|musique|bleu )/);
	$offset = 0 if (!defined($offset));

	my $file;
	if ($channel =~ /inter/) {
		$file = "finter";
	} elsif ($channel =~ /culture/) {
		$file = "fculture";
	} elsif ($channel =~ / bleu loire/) {
		$file = "bleu loire ocean";
	} elsif ($channel =~ /bleu gasco/) {
		$file = "bleu gascogne";
	} else {
		$file = "fmusique";
	}
	my $name = $file;
	$name =~ s/^f//;
	$name = "France ".uc(substr($name,0,1)).substr($name,1);
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime();
	if ($hour < 5 && !$offset) { # Avant 5h c'est le prog de la veille
		($sec,$min,$hour,$mday,$mon,$year) = localtime(time()-24*3600);
	}
	$file .= sprintf("-%d-%02d-%02d",$year+1900,$mon+1,$mday);

	my $res;
	if (!-f "cache/$file" || -M "cache/$file" >= 1/24) {
		$res = update_prog($file);
	} else {
		open(my $f,"<cache/$file");
		# binmode $f; # ,":utf8";
		return undef if (!$f);
		$res = join("\n",<$f>);
		close($f);
	}
	my $rtab = $p->{chaines}->{$channel};
	my $rtab2 = decode_html($res,$name);
	if ($rtab) {
		if ($$rtab2[0][3] < $$rtab[0][3]) {
			push @$rtab2,$rtab;
			$rtab = $rtab2;
		} else {
			push @$rtab,$rtab2;
		}
	} else {
		$rtab = $rtab2;
	}
	undef $rtab2;
	$p->{chaines}->{$channel} = $rtab;
	$rtab;
}

1;

