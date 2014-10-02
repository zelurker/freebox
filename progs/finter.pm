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

my $debug = 0;

our %codage = (
	'\u00e0' => 'à',
	'\u00e2' => 'â',
	'\u00e4' => 'ä',
	'\u00e7' => 'ç',
	'\u00e8' => 'è',
	'\u00e9' => 'é',
	'\u00ea' => 'ê',
	'\u00eb' => 'ë',
	'\u00ee' => 'î',
	'\u00ef' => 'ï',
	'\u00f4' => 'ô',
	'\u00f6' => 'ö',
	'\u00f9' => 'ù',
	'\u00fb' => 'û',
	'\u00fc' => 'ü',
	'\u2019' => "'",
	'\u00c7' => 'Ç',
	'\u20ac' => 'euros',
);

sub update_prog {
	my $prog = chaines::request("http://www.franceinter.fr/sites/default/files/lecteur_commun_json/timeline.json");
	return if (!$prog);
	open(my $f,">finter");
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
	$title;
}

sub update {
	my ($p,$channel) = @_;
	return undef if (lc($channel) ne "france inter");

	my $res;
	if (!-f "finter" || -M "finter" >= 1/24) {
		$res = update_prog();
	} else {
		open(my $f,"<finter");
		return undef if (!$f);
		$res = join("\n",<$f>);
		close($f);
	}
	# On récupère l'heure de création du fichier, correspond à la desc étendue
	my $time = time() - (-M "finter")*24*3600;
	$res =~ s/^\[//;
	my @list = split(/\},/,$res);
	my $rtab = $p->{chaines}->{"france inter"};
	my $inserted = 0;
	foreach (@list) {
		my %hash = ();
		# France inter fait ça aussi...
		my @fields = split(/\,"/);
		# Reconstitution des tableaux [...]
		for (my $n=0; $n<=$#fields; $n++) {
			while ($fields[$n] =~ /\[/ && $fields[$n] !~ /\]/) {
				$fields[$n] .= ",".$fields[$n+1];
				if ($n == $#fields) {
					die "error case $fields[$n]\n";
				}
				splice @fields,$n+1,1;
			}
		}
		foreach (@fields) {
			s/^(.+?)"://;
			my $key = $1;
			next if (!$key);
			s/(^"|"$)//g;
			s/\\\//\//g;
			if (/^\{/) {
				s/(^\{|\})//g;
				@_ = split(/\:/);
				my $s = "";
				foreach (@_) {
					s/(^"|"$)//g;
					next if (/^\d+$/);
					$s .= ", " if ($s);
					$s .= $_;
				}
				$_ = $s;
			}
			print STDERR "$key = $_\n" if ($debug);
			$hash{$key} = decode_str($_);
		}
		print STDERR "\n" if ($debug);
		my $title = $hash{title_emission};
		next if (!$title);
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
				my @tab = (undef, "France Inter", $title, $hash{debut},
					$hash{fin}, "",
					$hash{desc_emission}, # desc
					"","",$img,0,0,get_date($hash{debut}));
				if ($hash{personnes}) {
					$tab[6] .= " ($hash{personnes})";
				}
				push @$rtab,\@tab;
			}
		} elsif ($inserted) {
			# met à jour la description
			$$rtab[$#$rtab][6] = $title if (!$$rtab[$#$rtab][6]);
		}
	}
	$p->{chaines}->{"france inter"} = $rtab;
	$rtab;
}

1;

