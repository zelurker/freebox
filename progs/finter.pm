package progs::finter;

# Refonte été 2016 de finter : ça ne marche plus par de l'xml apparemment,
# maintenant c'est de la page html brute apparemment ! Heuremsent ça n'a
# pas l'air trop dur d'extraire l'info... !

use strict;
# use warnings;
use progs::telerama;
@progs::finter::ISA = ("progs::telerama");
use progs::html::finter;
use progs::html::fb;
use progs::json;
use Time::Local "timegm_nocheck";
use Cpanel::JSON::XS qw(decode_json);
use Data::Dumper;
use Time::Local "timelocal_nocheck";
use Encode;
use HTML::Entities;

my $debug = 0;
our ($file,$use_json);

our %fb = (
	"fbleu_loire_ocean" => "https://www.francebleu.fr/emissions/grille-programmes/loire-ocean",
	"fbleu_gascogne" => "https://www.francebleu.fr/emissions/grille-programmes/gascogne"
);

sub disp_heure {
	my $time = shift;
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime($time);
	sprintf("%02d:%02d:%02d",$hour,$min,$sec);
}

sub update_prog_html($) {
	my $file = shift;
	my $url = $file;
	my ($base,$date) = $url =~ /^(.+?)-(.+)/;
	if ($base eq "finter") {
		$url = "https://www.franceinter.fr/programmes/$date";
	} elsif ($fb{$base}) {
		$url = $fb{$base};
	} else {
		# html pas supporté !
		return undef;
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

sub update_prog_json($) {
	my $file = shift;
	my $url = $file;
	$url =~ s/^json-//;
	$url =~ s/^f//;
	$url =~ s/-(\d+).+//;
	if ($file =~ /fmusique/) {
		# Bizarrement fmusique attend une date obligatoire à la fin de son json
		my ($sec,$min,$hour,$mday,$mon,$year) = localtime();
		my $d = timegm_nocheck(0,0,12,$mday,$mon,$year);
		$url = "http://www.france$url.fr/sites/default/files/lecteur_commun_json/reecoute-$d.json";
		print "url $url\n";
	} elsif ($file =~ /bleu/) {
		print "france bleu : json non supporté!\n";
		return undef;
	} elsif ($file =~ /fip/) {
		$url = "http://www.fipradio.fr/livemeta/7"; # c'est koi ce 7 ???
	} elsif ($file =~ /le_mouv/) {
		$url = "http://www.mouv.fr/sites/default/files/import_si/si_titre_antenne/leMouv_player_current.json";
		# l'url suivante est sensée avoir les émissions qui viennent sauf
		# que testé dans la nuit de samedi à dimanche, ça s'arrête à
		# dimanche minuit, donc pas très utile !
		# $url = "http://www.mouv.fr/sites/default/files/lecteur_commun_json/timeline.json";
	} else {
		# $url = "http://www.france$url.fr/sites/default/files/lecteur_commun_json/timeline.json";
		$url = "https://www.france$url.fr/programmes?xmlHttpRequest=1";
	}
	my ($status,$prog) = chaines::request($url);
	print STDERR "update_prog_json: got status $status, prog $prog\n" if ($debug && $prog);
	return if (!$prog);
	if ($file !~ /(fip|le_mouv)/) {
		open(my $f,">cache/$file");
		return if (!$f);
		print $f $prog;
		close($f);
	}
	return $prog;
}

sub update {
	my ($p,$channel,$offset) = @_;
	return undef if (lc($channel) !~ /france (inter|culture|musique|bleu )/ &&
	lc($channel) !~ /(le mouv|fip)/);
	$offset = 0 if (!defined($offset));

	my ($suffix) = $channel =~ /france (.+)/;
	if ($suffix) {
		$file = "f$suffix";
	} else {
		$file = lc($channel);
	}
	$file =~ s/ /_/g;
	$file =~ s/[^a-zA-Z0-9_]//g;
	my $name = $p->{name};

	my ($sec,$min,$hour,$mday,$mon,$year) = localtime();
	if ($hour < 5 && !$offset && $channel eq "france inter") { # Avant 5h c'est le prog de la veille
		($sec,$min,$hour,$mday,$mon,$year) = localtime(time()-24*3600);
	}
	$file .= sprintf("-%d-%02d-%02d",$year+1900,$mon+1,$mday);

	my $res;
	$use_json = 0;
	for ($use_json = 0; $use_json <= 1; $use_json++) {
		if (!-f "cache/$file") {
			if ($use_json) {
				$res = update_prog_json($file);
			} else {
				$res = update_prog_html($file);
			}
		} else {
			open(my $f,"<cache/$file");
			# binmode $f; # ,":utf8";
			return undef if (!$f);
			$res = join("\n",<$f>);
			close($f);
		}
		if (!$res) {
			$file = "json-$file";
		} else {
			last;
		}
	}
	return undef if (!$res);
	my $rtab = $p->{chaines}->{$channel};
	my $rtab2;
	my $json;
    if (!$use_json) {
		if ($file =~ /inter/) {
			$rtab2 = progs::html::finter::decode_html($p,$res,$name);
		} elsif ($file =~ /bleu/) {
			$rtab2 = progs::html::fb::decode_html($p,$res,$name);
		}
	} else {
		eval  {
			$json = decode_json $res;
		};
		if ($@) {
			print "finter: couille dans le potage au niveau json à partir de $res\n";
			return undef;
		}
		open(F,">json");
		print F Dumper($json);
		close(F);
		$rtab2 = progs::json::decode_json($p,$json,$file,$name);
	}
	if ($rtab) {
		if ($$rtab2[0][3] < $$rtab[0][3]) {
			for (my $n=0; $n<=$#$rtab; $n++) {
				push @$rtab2,$$rtab[$n];
			}
			$rtab = $rtab2;
		} else {
			for (my $n=0; $n<=$#$rtab2; $n++) {
				push @$rtab,$$rtab2[$n];
			}
		}
	} else {
		$rtab = $rtab2;
	}
	undef $rtab2;
	$p->{chaines}->{$channel} = $rtab;
	$rtab;
}

sub insert {
	my ($p,$rtab2,$rtab,$min_delay) = @_;
	# La fonction d'insertion d'un nouveau prog en commun pour tous les
	# décodeurs parce qu'on retrouve le même genre de problème à traiter
	# (correction de l'heure de fin de celui d'avant ou insertion d'un prog
	# inconnu ou d'un flash).
	foreach ($$rtab2[6],$$rtab2[2]) { # desc & titre
		s/&#(\d+);/chr($1)/ge;
		# s/&amp;/\&/g;
		$_ = decode_entities($_);
		# utf8::decode(decode_entities($_));
		s/\xe2\x80\x99/'/g;
		Encode::from_to($_, "utf-8", "iso-8859-1") if (!$use_json);
	}

	my $fin = $$rtab2[3];
	$min_delay = 12*3600 if (!$min_delay);
	if ($#$rtab >= 0) {
		$fin = $$rtab[$#$rtab][4];
		if ($fin < $$rtab2[3] && $$rtab2[3] - $fin < $min_delay) { # 10 minutes pour finter
			push @$rtab, [ undef, $$rtab2[1],
			   ($fin % 3600 == 0 && $$rtab2[3]-$fin < 600 ? "Flash ?" : "Programme inconnu"),
				$fin,$$rtab2[3], "",
				"",
				"","",undef,0,0,$$rtab2[12]];
		}
	}
	push @$rtab,$rtab2;
	if ($#$rtab > 0 && ($fin > $$rtab2[3] || $fin < $$rtab2[3]-120)) {
		$$rtab[$#$rtab-1][4] = $$rtab2[3];
	}
}

sub get_date {
	my ($p,$time) = @_;
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime($time);
	sprintf("%d/%02d/%02d",$mday,$mon+1,$year+1900);
}

sub init_time {
	my $p = shift;
	my ($time,$date);
	if ($file =~ /-(\d+)-(\d+)-(\d+)/) {
		my ($y,$m,$d) = ($1,$2,$3);
		$y -= 1900;
		$m--;
		$time = timelocal_nocheck( 0, 0, 0, $d, $m, $y );
		$date = $p->get_date($time);
	}
	($time,$date);
}

1;

