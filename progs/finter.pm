package progs::finter;

# Refonte été 2016 de finter : ça ne marche plus par de l'xml apparemment,
# maintenant c'est de la page html brute apparemment ! Heuremsent ça n'a
# pas l'air trop dur d'extraire l'info... !

use strict;
# use warnings;
use progs::telerama;
@progs::finter::ISA = ("progs::telerama");
use progs::html::finter;
use progs::json;
use Time::Local "timegm_nocheck";
use Cpanel::JSON::XS qw(decode_json);
use Data::Dumper;

my $debug = 0;

our %fb = (
	"bleu loire ocean" => "http://www.francebleu.fr/sites/default/files/lecteur_commun_json/timeline-13125.json",
	"bleu gascogne" => "http://www.francebleu.fr/sites/default/files/lecteur_commun_json/timeline-13113.json",
);

sub update_prog_html($) {
	my $file = shift;
	my $url = $file;
	my ($base,$date) = $url =~ /^(.+?)-(.+)/;
	if ($base eq "finter") {
		$url = "https://www.franceinter.fr/programmes/$date";
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
		$url = $fb{$file};
	} else {
		# $url = "http://www.france$url.fr/sites/default/files/lecteur_commun_json/timeline.json";
		$url = "https://www.france$url.fr/programmes?xmlHttpRequest=1";
	}
	my ($status,$prog) = chaines::request($url);
	print STDERR "update_prog_json: got status $status, prog $prog\n" if ($debug && $prog);
	return if (!$prog);
	open(my $f,">cache/$file");
	return if (!$f);
	print $f $prog;
	close($f);
	return $prog;
}

sub update {
	my ($p,$channel,$offset) = @_;
	return undef if (lc($channel) !~ /france (inter|culture|musique|bleu )/);
	$offset = 0 if (!defined($offset));

	my $file;
	my ($suffix) = $channel =~ /france (.+)/;
	$file = "f$suffix";
	$file =~ s/ /_/g;
	my $name = $file;
	$name =~ s/^f//;
	$name = "France ".uc(substr($name,0,1)).substr($name,1);
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime();
	if ($hour < 5 && !$offset && $channel eq "france inter") { # Avant 5h c'est le prog de la veille
		($sec,$min,$hour,$mday,$mon,$year) = localtime(time()-24*3600);
	}
	$file .= sprintf("-%d-%02d-%02d",$year+1900,$mon+1,$mday);

	my $res;
	my $use_json = 0;
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
			print "lecture de $file : ",length($res),"\n";
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
		$rtab2 = progs::html::finter::decode_html($res,$name);
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
		$rtab2 = progs::json::decode_json($json,$file,$name);
	}
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

