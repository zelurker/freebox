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
	"hbo (east)" => "https://www.ontvtonight.com/guide/listings/channel/69046988/hbo-east.html",
	"hbo (west)" => "https://www.ontvtonight.com/guide/listings/channel/69035526/hbo-west.html",
	"hbo 2 (east)" => "https://www.ontvtonight.com/guide/listings/channel/69022958/hbo-2-east.html",
	"hbo 2 (west)" => "https://www.ontvtonight.com/guide/listings/channel/69047094/hbo-2-west.html",
	"hbo comedy (east)" => "https://www.ontvtonight.com/guide/listings/channel/69047950/hbo-comedy-east.html",
	"hbo family (east)" => "https://www.ontvtonight.com/guide/listings/channel/69032418/hbo-family-east.html",
	"hbo signature (east)" => "https://www.ontvtonight.com/guide/listings/channel/69032052/hbo-signature-east.html",
	"hbo zone (east)" => "https://www.ontvtonight.com/guide/listings/channel/69047953/hbo-zone-east.html",
);

sub init {
	# Procédure pour remplir le cache avec les pages html des chaines, à
	# appeler dans un fork
	my $p = shift;
	return if (!$p);
	foreach my $myurl (keys %urls) {
		$p->get($myurl);
	}
}

sub update {
	my ($p,$channel,$offset) = @_;
	my $list = $p->{list};
	my $num = $$list{$channel}[0];
	my $nom = $$list{$channel}[2];
	die "pas de nom pour $channel num $num list $list" if (!$nom);
	my $dt = DateTime->now(time_zone => "Europe/Paris");
	$dt->set_time_zone("US/Eastern");
	if ($offset) {
		my $dur = DateTime::Duration->new(days => $offset);
		$dt += $dur;
	}
	my ($mday,$mon,$year) = ($dt->day,$dt->month,$dt->year);

	my $date = sprintf("%02d%02d%d",$dt->day,$dt->month,$dt->year);
	my $conv2 = $channel;
	$conv2 =~ s/ /_/g;
	$conv2 =~ s/[\(\)]//g;
	my $html = http::myget($urls{$channel}."?dt=".$dt->ymd,"cache/$conv2-$date.html",7);
	@_ = split /\n/,$html;
	my ($title,$url,$find_title) = ();
	my @tab = ();
	foreach (@_) {
		last if (/<\/table/);
		if (/<a href="(https.+?)"/) {
			$url = $1;
			$find_title = 1;
		} elsif ($find_title && /^[ \t]+(.+)<\/a/) {
			$title = $1;
			add_entry(\@tab,$mday,$mon,$year,$url,$nom,$title,$num) if ($title);
			$find_title = 0;
		}
	}
	$p->{chaines}->{$channel} = \@tab;
	\@tab;
}

sub get {
	my ($p,$channel,$source,$base_flux,$serv) = @_;
	my $conv = chaines::conv_channel($channel);
	return undef if (!$urls{$conv});
	# p->{chaines} est initialisé dans new de telerama, spécifique à
	# telerama & hbo
	my $rtab = $p->{chaines}->{$conv};
	$rtab = $p->update($conv) if (!$rtab);
	# Note sur les last_chan : tous ces trucs c pour les command next et
	# prev qui commencent par tester la chaine en cours et vérifier que
	# conv_channel(chennel) eq last_channel, du coup on est obligé de
	# convertir la chaine ici alors que ça ne nous sert à rien !!!
	$p->{last_chan} = $conv;
	my $time = time();
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

sub add_entry {
	my ($rtab,$mday,$mon,$year,$url,$source,$title,$num) = @_;
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
	my $dt;
	foreach (@_) {
		if (/(\d\d?):(\d\d) (am|pm) - (\d\d?):(\d\d) (am|pm)/) {
			my ($h1,$m1,$am1,$h2,$m2,$am2) = ($1,$2,$3,$4,$5,$6);
			$h1 += 12 if ($am1 eq "pm" && $h1 < 12);
			$h2 += 12 if ($am2 eq "pm" && $h2 < 12);
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
	push @$rtab, ([$num, # chan id
		"$source", $title,
		$deb,
		$fin, "", # fin
		"", # sub
		$desc, # details
		"",
		"", # img
		0,0,
		$dt->dmy("/")]);
}

1;

