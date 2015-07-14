package progs::finter;
#
#===============================================================================
#
#         FILE: finter.pm
#
#  DESCRIPTION: progs france inter
#
#        FILES: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Emmanuel Anne (), emmanuel.anne@gmail.com
# ORGANIZATION:
#      VERSION: 1.0
#      CREATED: 08/03/2013 18:13:21
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use progs::telerama;
@progs::finter::ISA = ("progs::telerama");
use chaines;
use Encode;
use Data::Dumper;
use Cpanel::JSON::XS qw(decode_json);
use Time::Local "timegm_nocheck";

my $debug = 0;

our %codage = (
	'\u00e0' => '�',
	'\u00e2' => '�',
	'\u00e4' => '�',
	'\u00e7' => '�',
	'\u00e8' => '�',
	'\u00e9' => '�',
	'\u00ea' => '�',
	'\u00eb' => '�',
	'\u00ee' => '�',
	'\u00ef' => '�',
	'\u00f4' => '�',
	'\u00f6' => '�',
	'\u00f9' => '�',
	'\u00fb' => '�',
	'\u00fc' => '�',
	'\u2019' => "'",
	'\u00c7' => '�',
	'\u20ac' => 'euros',
);

our %fb = (
	"bleu loire ocean" => "http://www.francebleu.fr/sites/default/files/lecteur_commun_json/timeline-13125.json",
	"bleu gascogne" => "http://www.francebleu.fr/sites/default/files/lecteur_commun_json/timeline-13113.json",
);

sub update_prog($) {
	my $file = shift;
	my $url = $file;
	$url =~ s/^f//;
	if ($file eq "fmusique") {
		# Bizarrement fmusique attend une date obligatoire � la fin de son json
		my ($sec,$min,$hour,$mday,$mon,$year) = localtime();
		my $d = timegm_nocheck(0,0,12,$mday,$mon,$year);
		$url = "http://www.france$url.fr/sites/default/files/lecteur_commun_json/reecoute-$d.json";
	} elsif ($file =~ /^bleu/) {
		$url = $fb{$file};
	} else {
		$url = "http://www.france$url.fr/sites/default/files/lecteur_commun_json/timeline.json";
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

sub decode_str {
	my $title = shift;
	foreach (keys %codage) {
		my $index;
		do {
			$index = index($title,$_);
			substr($title,$index,length($_),$codage{$_}) if ($index >= 0);
		} while ($index >= 0);
	}
	if ($ENV{LANG} =~ /UTF/) {
		$title = Encode::encode("utf-8",$title);
	} else {
		$title = Encode::encode("iso-8859-15",$title );
	}
	$title =~ s/[\r\n]//g; # retours chariots � virer aussi !
	$title;
}

sub get_desc($) {
	my $hash = $_;
	decode_str(
		($hash->{diffusions}[0]->{title} ?
			$hash->{diffusions}[0]->{title}." : " :
			"").
		($hash->{diffusions}[0]->{desc_emission} ?
			$hash->{diffusions}[0]->{desc_emission}." "
			: "").
		($hash->{diffusions}[0]->{texte_emission} ?
			$hash->{diffusions}[0]->{texte_emission}
			: ""));
}

sub update {
	my ($p,$channel) = @_;
	return undef if (lc($channel) !~ /france (inter|culture|musique|bleu )/);

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
	my $json = decode_json $res;

	# On r�cup�re l'heure de cr�ation du fichier, correspond � la desc �tendue
	my $time = time() - (-M "$file")*24*3600;
	my $rtab = $p->{chaines}->{$channel};
	my $inserted = 0;
	my $cont = 0;
	my @fields;
	$json = $json->{diffusions} if (ref($json) ne "ARRAY");
	foreach (@$json) {
		my %hash = %$_;
		# France inter fait �a aussi...
		print STDERR "\n" if ($debug);
		my $title = $hash{title_emission};
		next if (!$title);
		$title = decode_str($title);
		my $img = $hash{path_img_emission};
		if ($hash{debut}) {
			my $found = 0;
			foreach (@$rtab) {
				if ($$_[3] == $hash{debut} && $$_[4] == $hash{fin}) {
					$found = 1;
					last;
				}
			}
			if (!$found) {
				$inserted = 1;

				my @tab = (undef, $name, $title, $hash{debut},
					$hash{fin}, "",
					get_desc(\%hash),
					"","",$img,0,0,get_date($hash{debut}));
				if ($hash{personnes}) {
					$tab[6] .= decode_str(" (".join(",",@{$hash{personnes}}).")");
				}
				push @$rtab,\@tab;
			}
		} elsif ($inserted) {
			# met � jour la description
			$$rtab[$#$rtab][6] = get_desc(\%hash) if (!$$rtab[$#$rtab][6]);
		}
	}
	for (my $n=1; $n<$#$rtab; $n++) {
		if ($$rtab[$n][3] > $$rtab[$n-1][4]+60) { # gros �cart entre les progs
			# Arrive surtout pour france musique en fait...
			# Sans d�conner ce bout de code est absolument horrible, �a montre
			# le + gros point faible de perl5 : on ne veut qu'ins�rer un �l�ment
			# dans un tableau ici. Sauf que si on ne passe pas par chunk alors
			# la r�f�rence vers $$rtab[n] se retrouve dupliqu�e !
			my @chunk = @{$$rtab[$n]};
			splice @$rtab,$n,0,[@chunk];
			$$rtab[$n][3] = $$rtab[$n-1][4]+60;
			$$rtab[$n][4] = $$rtab[$n+1][3]-60;
			$$rtab[$n][2] = "Aucun programme";
			$$rtab[$n][6] = $$rtab[$n][9] = undef;
		}
	}
	$p->{chaines}->{$channel} = $rtab;
	$rtab;
}

1;

