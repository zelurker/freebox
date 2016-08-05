package progs::json;

our ($tstart,$tend,$ttitle,$tdesc);
use strict;

sub get_date {
	my $time = shift;
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime($time);
	sprintf("%d/%02d/%02d",$mday,$mon+1,$year+1900);
}

sub decode_str {
	my $title = shift;
	$title =~ s/[\r\n]//g; # retours chariots à virer aussi !
	$title;
}

sub get_desc($) {
	my $hash = $_;
	decode_str($hash->{$tdesc});
}

sub decode_json {
	my ($json,$file,$name) = @_;
	($tstart,$tend,$ttitle,$tdesc) = ("start","end","conceptTitle","expressionTitle");
	if ($file =~ /fculture/) {
		$ttitle = "surtitle";
		$tdesc = "title";
	} elsif ($file =~ /fmusique/) {
		($tstart,$tend,$ttitle,$tdesc) = ("debut","fin","title_emission","desc_emission");
	}

	# On récupère l'heure de création du fichier, correspond à la desc étendue
	my $time = time() - (-M "$file")*24*3600;
	my $rtab = [];
	my $inserted = 0;
	my $cont = 0;
	my @fields;
	$json = $json->{diffusions} if (ref($json) ne "ARRAY");
	print "on y va avec $tstart $tend ttitle $ttitle json $json\n";
	foreach (@$json) {
		my %hash = %$_;
		# France inter fait ça aussi...
		my $title = $hash{$ttitle};
		next if (!$title);
		$title = decode_str($title);
		my $img = $hash{path_img_emission}; # Uniquement france musique en 2016 !
		if ($hash{$tstart}) {
			my $found = 0;
			foreach (@$rtab) {
				if ($$_[3] == $hash{$tstart} && $$_[4] == $hash{$tend}) {
					$found = 1;
					last;
				}
			}
			if (!$found) {
				$inserted = 1;

				my @tab = (undef, $name, $title, $hash{$tstart},
					$hash{$tend}, "",
					get_desc(\%hash),
					"","",$img,0,0,get_date($hash{$tstart}));
				if ($hash{personnes}) {
					$tab[6] .= decode_str(" (".join(",",@{$hash{personnes}}).")");
				}
				my $fin = $hash{$tstart};
				if ($#$rtab >= 0) {
					$fin = $$rtab[$#$rtab][4];
					if ($fin < $hash{$tstart}) {
						push @$rtab, [ undef, $name, ($fin % 3600 == 0 ? "Flash ?" : "Programme inconnu"),
							$fin,$hash{$tstart}, "",
							"",
							"","",undef,0,0,get_date($hash{$tstart})];
					}
				}
				push @$rtab,\@tab;
				if ($fin > $hash{$tstart}) {
					$$rtab[$#$rtab-1][4] = $hash{$tstart};
				}
			}
		} elsif ($inserted) {
			# met à jour la description
			$$rtab[$#$rtab][6] = get_desc(\%hash) if (!$$rtab[$#$rtab][6]);
		}
	}
	$rtab;
}

1;

