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
);

sub update_prog {
	my $prog = chaines::request("http://www.franceinter.fr/sites/default/files/rf_player/player-direct.json");
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
	my @list = split(/"theme_functions":\[/,$res);
	my $rtab = $p->{chaines}->{"france inter"};
	my $inserted = 0;
	foreach (@list) {
		my %hash = ();
		# France inter fait �a aussi...
		my @fields = split(/\,"/);
		foreach (@fields) {
			s/^(.+?)"://;
			my $key = $1;
			next if (!$key);
			s/(^"|"$)//g;
			s/\\\//\//g;
			print STDERR "$key = $_\n" if ($debug);
			$hash{$key} = $_;
		}
		print STDERR "\n" if ($debug);
		my $title = $hash{title};
		next if (!$title);
		foreach (keys %codage) {
			my $index;
			do {
				$index = index($title,$_);
				substr($title,$index,length($_),$codage{$_}) if ($index >= 0);
			} while ($index >= 0);
		}
		my $img = $hash{image};
		$img = "http://www.franceinter.fr/$img";
		if ($hash{heure_debut}) {
			my $found = 0;
			foreach (@$rtab) {
				if ($$_[3] == $hash{heure_debut} && $$_[4] == $hash{heure_fin}) {
					$found = 1;
					last;
				}
			}
			if (!$found) {
				$inserted = 1;
				my @tab = (undef, "France Inter", $title, $hash{heure_debut}, 
					$hash{heure_fin}, "",
					"", # desc
					"","",$img,0,0,get_date($hash{heure_debut}));
				push @$rtab,\@tab;
			}
		} elsif ($inserted) {
			# met � jour la description
			$$rtab[$#$rtab][6] = $title;
		}
	}
	$p->{chaines}->{"france inter"} = $rtab;
	$rtab;
}

1; 

