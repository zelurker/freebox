package progs::hbo;

use http;
use progs::telerama;
use DateTime;
use common::sense;
use HTML::Entities;
use chaines;
use out;

@progs::hbo::ISA = ("progs::telerama");

our %urls = (
	"hbo (east)" => "https://www.tvpassport.com/tv-listings/stations/hbo-eastern-feed/614",
	"hbo (west)" => "https://www.tvpassport.com/tv-listings/stations/hbo-hd-pacific-feed/2629",
	"hbo 2 (east)" => "https://www.tvpassport.com/tv-listings/stations/hbo-2-eastern-feed-hd/6313",
	"hbo 2 (west)" => "https://www.tvpassport.com/tv-listings/stations/hbo-2-pacific-feed-hd/6314",
	"hbo comedy (east)" => "https://www.tvpassport.com/tv-listings/stations/hbo-comedy-east/629",
	"hbo family (east)" => "https://www.tvpassport.com/tv-listings/stations/hbo-family-eastern-feed/628",
	"hbo signature (east)" => "https://www.tvpassport.com/tv-listings/stations/hbo-signature-hbo-3-eastern-hd/7099",
	"hbo zone (east)" => "https://www.tvpassport.com/tv-listings/stations/hbo-zone-east/630",
	"hbo 1 ca" => "https://www.tvpassport.com/tv-listings/stations/hbo/84",
	"hbo 2 (east) ca" => "https://www.tvpassport.com/tv-listings/stations/hbo-canada-2-west/292",
);

sub init {
	# Procédure pour remplir le cache avec les pages html des chaines, à
	# appeler dans un async de coro
	# problème : le site a l'air de mettre une pause de 1s sur chaque page,
	# du coup ça prend un temps fou si on fait plusieurs chaines, et en + y
	# a vraiment beaucoup de fichiers, du coup on change de tactique, voir
	# fonction valid, appelée au moment de l'affichage d'une entrée
	my $p = shift;
	return if (!$p);
	foreach my $myurl (keys %urls) {
		$p->get($myurl);
	}
}

sub parse_tvpassport {
	my ($html,$num,$nom) = @_;
	@_ = split /\n/,$html;
	my @tab;
	foreach (@_) {
		if (/<div id="itemheader/) {
			s/^[ \t]+//;
			my @items = split /<div id="itemheader/;
			foreach (@items) {
				next if (!$_);
				my ($year,$month,$day,$hour,$minute,$second) = /data-st="(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/;
				my ($duration) = /data-duration="(\d+)/;
				my ($stars) = /data-starRating="(\d)/i;
				my ($desc) = /data-description="(.+?)"/;
				my ($title) = /data-showName="(.+?)"/;
				my ($eptitle) = /data-episodeTitle="(.*?)"/;
				if ($title eq "Movie") {
					$title = $eptitle;
					my ($annee) = /data-year="(.*?)"/;
					$title .= " ($annee)" if ($annee);
				} else {
					my ($episode) = /data-episodeNumber="(\d*?)"/;
					$desc = "Episode : $episode ".($eptitle ? "($eptitle)" : "")."\n$desc";
				}
				my ($cast) = /data-cast="(.*?)"/;
				my ($director) = /data-director="(.*?)"/;
				my $details = "";
				my ($type) = /data-showType="(.+?)"/;
				my ($pic) = /data-showPicture="(.*?)"/;
				$pic = "https://cdn.tvpassport.com/image/show/240x360/$pic" if ($pic);
				$details = "Avec : $cast" if ($cast);
				$details .= "\nDirector : $director" if ($director);
				# indique la time_zone sinon epoch retourne le nombre de
				# secondes pour l'utc, on veut pas ça.
				my $dt = DateTime->new(year => $year, month => $month, day => $day, hour => $hour, minute => $minute, second => $second,time_zone => "Europe/Paris");
				push @tab, ([$num, # chan id
						$nom, $title,
						$dt->epoch,
						$dt->epoch+$duration*60, # fin
						$type, # category
						$desc,
						$details, # details
						"", # rating
						$pic, # img
						$stars,0,
						$dt->dmy("/")]);
			}
		} # if
	} # foreach (@_)
	return @tab;
}

sub parse_ontvtonight {
	my ($html,$num,$nom,$year,$mon,$mday) = @_;
	@_ = split /\n/,$html;
	my ($title,$url,$find_title) = ();
	my @tab = ();
	my $dt;
	my $tz = "US/Eastern";
	my $desc;
	$tz = "US/Pacific" if ($nom =~ /West/i);
	foreach (@_) {
		last if (/<\/table/);
		if (/<h5.+?>(\d\d?):(\d\d) (am|pm)/) {
			my ($h1,$m1,$am1) = ($1,$2,$3);
			$h1 += 12 if ($am1 eq "pm" && $h1 < 12);
			$h1 = 0 if ($am1 eq "am" && $h1 == 12); # 12am -> 0h !!!
			$dt = DateTime->new(year => $year, month => $mon, day => $mday, hour => $h1, minute => $m1, time_zone => $tz);
		} elsif (/<a href="(https.+?)"/) {
			$url = $1;
			$find_title = 1;
		} elsif ($find_title && /^[ \t]+(.+)<\/a/) {
			$title = $1;
			# add_entry(\@tab,$mday,$mon,$year,$url,$nom,$title,$num) if ($title);
			push @tab, ([$num, # chan id
					$nom, $title,
					$dt->epoch,
					$dt->epoch+1, "", # fin
					"", # sub
					$url, # details
					"",
					"", # img
					0,0,
					$dt->dmy("/")]);
			$tab[$#tab-1][4] = $dt->epoch if ($#tab > 0);
			$find_title = 0;
		}
	}
	return @tab;
}

sub update {
	my ($p,$channel,$offset) = @_;
	my $list = $p->{list};
	say "*** update $channel offset $offset";
	my $num = $$list{$channel}[0];
	my $nom = $$list{$channel}[2];
	die "pas de nom pour $channel num $num list $list" if (!$nom);
	my $dt = DateTime->now(time_zone => "Europe/Paris");
	if ($urls{$channel} =~ /ontvtonight/) {
		$dt->set_time_zone("US/Eastern");
	}
	if ($offset) {
		my $dur = DateTime::Duration->new(days => $offset);
		$dt += $dur;
	}
	my ($mday,$mon,$year) = ($dt->day,$dt->month,$dt->year);
	say "update date ",$dt->dmy;

	my $date = sprintf("%02d%02d%d",$dt->day,$dt->month,$dt->year);
	my $conv2 = $channel;
	$conv2 =~ s/ /_/g;
	$conv2 =~ s/[\(\)]//g;
	my $html;
	my @tab;
	if ($urls{$channel} =~ /ontvtonight/) {
		$html = http::myget($urls{$channel}."?dt=".$dt->ymd,"cache/$conv2-$date.html",7);
		@tab = parse_ontvtonight($html,$num,$nom,$year,$mon,$mday);
	} else { # tvpassport
		$html = http::myget($urls{$channel}."/".$dt->ymd,"cache/$conv2-$date.html",7);
		@tab = parse_tvpassport($html,$num,$nom);
	}

	my $rtab = $p->{chaines}->{$channel};
	if (!$rtab) {
		$p->{chaines}->{$channel} = \@tab;
	} elsif ($tab[$#tab][3] <= $$rtab[0][3]) {
		if ($tab[$#tab][3] == $$rtab[0][3] && $tab[$#tab][4] == $$rtab[0][4]) {
			shift @$rtab;
		}
		unshift @$rtab,@tab;
	} elsif ($tab[0][3] >= $$rtab[$#$rtab][3]) {
		if ($tab[0][3] == $$rtab[$#$rtab][3] && $tab[0][4] == $$rtab[$#$rtab][4]) {
			shift @tab;
		}
		push @$rtab,@tab;
	} else {
		say STDERR "hbo::update: anomalie, sait pas où mettre le tableau résultat !";
		say STDERR "actuel commence en $tab[0][3] comparé à fin de rtab $$rtab[$#$rtab][3]";
		say STDERR "actuel finit en $tab[$#tab][3] comparé à début de rtab $$rtab[0][3]";
		exit(0);
	}
	$p->{chaines}->{$channel}
}

sub get {
	my ($p,$channel,$source,$base_flux,$serv) = @_;
	my $conv = chaines::conv_channel($channel);
	return undef if (!$urls{$conv});
	# p->{chaines} est initialisé dans new de telerama, spécifique à
	# telerama & hbo
	my $rtab = $p->{chaines}->{$conv};
	$rtab = $p->update($conv) if (!$rtab);

	$p->{last_chan} = $conv;
	my $time = time();
	if ($time > $$rtab[$#$rtab][4]) {
		# Si le cache dans chaines{} est trop vieux, on met à jour
		$p->update($conv);
		$rtab = $p->{chaines}->{$channel};
	}
	if ($$rtab[0][3] > $time) {
		# Heure de début du 1er prog dans le futur -> récupérer l'offset d'avant
		$p->update($conv,-1);
	}
	for (my $n=0; $n<=$#$rtab; $n++) {
		my $sub = $$rtab[$n];
		my $start = $$sub[3];
		my $end = $$sub[4];
		if ($start > $time && $n > 0) {
			$p->{last_prog} = $n-1;
			return $$rtab[$n-1];
		}
	}
	die "pas trouvé d'heure locale ? channel $channel time $time rtab $#$rtab";
}

sub valid {
	my ($p,$rtab,$refresh) = @_;
	my $url = $$rtab[7];
	my $title = $$rtab[2];
	return 1 if ($url !~ /^http/);
	my $source = $$rtab[1];
	$url =~ s/\&amp;/\&/g;
	my ($deb,$fin);
	my ($pid) = $url =~ /pid=(.+?)\&/;
	my ($tm) = $url =~ /tm=(.+?)\&/;
	my $tz = "US/Eastern";
	$tz = "US/Pacific" if ($source =~ /West/i);
	die "pas de pid : $url" if (!$pid);
	my $html = http::myget($url,"cache/hbo/$pid-$tm",7);
	die "pas de html" if (!$html);
	@_ = split /\n/,$html;
	my $infos = 0;
	my $desc = "";
	my $dt = DateTime->from_epoch(epoch => $$rtab[3], time_zone => $tz);
	my ($mday,$mon,$year) = ($dt->day,$dt->month,$dt->year);
	foreach (@_) {
		if (/(\d\d?):(\d\d) (am|pm) - (\d\d?):(\d\d) (am|pm)/) {
			my ($h1,$m1,$am1,$h2,$m2,$am2) = ($1,$2,$3,$4,$5,$6);
			$h1 += 12 if ($am1 eq "pm" && $h1 < 12);
			$h2 += 12 if ($am2 eq "pm" && $h2 < 12);
			$h1 = 0 if ($am1 eq "am" && $h1 == 12); # 12am -> 0h !!!
			$h2 = 0 if ($am2 eq "am" && $h2 == 12); # 12am -> 0h !!!
			$dt = DateTime->new(year => $year, month => $mon, day => $mday, hour => $h1, minute => $m1, time_zone => $tz);
			$dt->set_time_zone("Europe/Paris");
			$deb = $dt->epoch;
			$dt = DateTime->new(year => $year, month => $mon, day => $mday, hour => $h2, minute => $m2, time_zone => $tz);
			$dt->set_time_zone("Europe/Paris");
			$fin = $dt->epoch();
			if ($am1 eq "pm" && $am2 eq "am") {
				$fin += 24*3600;
			}
		} elsif (/<p>\&nbsp;<\/p/) {
			# c'est vraiment fragile comme test, faudra pas s'étonner quand
			# ça marchera plus !
			$infos = 1;
		} elsif ($infos) {
			s/^ +//;
			$_ .= "\n" if (/(Season|Episode) \d/);
			$_ .= "\n" if (/h4>$/); # titre d'épisode
			if (/<br>/) {
				last;
			} else {
				$desc .= $_;
			}
		}
	}
	die "pas de début title $title url $url" if (!$deb);
	$desc = decode_entities($desc);
	$desc =~ s/\t+/ /g;
	$desc =~ s/<br\/>/\n/g;
	$desc =~ s/<.+?>//g; # vire tous les tags html
	$desc =~ s/^[ \t]+//;
	$title = decode_entities($title);
	$$rtab[2] = $title;
	$$rtab[3] = $deb;
	$$rtab[4] = $fin;
	$$rtab[7] = $desc;
	return 1;
}

1;

