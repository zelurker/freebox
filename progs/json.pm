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
	my ($p,$json,$file,$name) = @_;
	($tstart,$tend,$ttitle,$tdesc) = ("start","end","conceptTitle","expressionTitle");
	if ($file =~ /fculture/) {
		$ttitle = "surtitle";
		$tdesc = "title";
	} elsif ($file =~ /fip/) {
		$ttitle = "title";
	} elsif ($file =~ /le_mouv/) {
		($tstart,$tend,$ttitle,$tdesc) = ("startTime","endTime","titre","expressionTitle");

	} elsif ($file =~ /fmusique/) {
		($tstart,$tend,$ttitle,$tdesc) = ("debut","fin","title_emission","desc_emission");
	}

	# On récupère l'heure de création du fichier, correspond à la desc étendue
	my $time = time() - (-M "$file")*24*3600;
	my $rtab = [];
	my $inserted = 0;
	my $cont = 0;
	my @fields;
	$json = $json->{diffusions} if (ref($json) ne "ARRAY" && $json->{diffusions});
	if ($file =~ /le_mouv/) {
		my $current = $json->{current};
		my $emission = $current->{emission};
		my $song = $current->{song};
		if ($song ) {
			if (time() > $song->{endTime}) {
				$song->{endTime} = time()+12;
			}
			$song->{titre} .= " (emission : $emission->{titre})";
			$json = [$song]; # faut coller ça dans un tableau d'1 élément !
		} else {
			# pour forcer une màj d'ici 30s, 1 chance de choper 1 chanson !
			$emission->{endTime} = time()+30;
			$json = [$emission];
		}
	} elsif ($file =~ /fip/) {
		$json = $json->{steps};
		my @tab;
		foreach (sort { $json->{$a}->{start} <=> $json->{$b}->{start} } keys %$json) {
			push @tab,$json->{$_};
		}
		$json = \@tab;
	}
	print "on y va avec $tstart $tend ttitle $ttitle json $json\n";
	foreach (@$json) {
		my %hash = %$_;
		# France inter fait ça aussi...
		my $title = $hash{$ttitle};
		if ($file =~ /fip/) {
			# fip a une playlist uniquement, cas très particulier !
			$title = "$hash{authors} - $title";
		} elsif ($file =~ /le_mouv/) {
			$title = "$hash{interpreteMorceau} - $title";
		}
		next if (!$title);
		$title = decode_str($title);
		my $img = $hash{path_img_emission}; # Uniquement france musique en 2016 !
		$img = $hash{visual} if (!$img); # fip !
		if ($hash{visuel}) {
			$img = $hash{visuel}->{medium};
		}
		if ($hash{$tstart}) {
			my $found = 0;
			foreach (@$rtab) {
				if ($$_[3] == $hash{$tstart} && $$_[4] == $hash{$tend}) {
					print "json: collision !\n";
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
				if ($hash{personnes} && $#{$hash{personnes}} >= 0) {
					$tab[6] .= decode_str(" (".join(",",@{$hash{personnes}}).")");
				}
				$p->insert(\@tab,$rtab);
			}
		} elsif ($inserted) {
			# met à jour la description
			$$rtab[$#$rtab][6] = get_desc(\%hash) if (!$$rtab[$#$rtab][6]);
		}
	}
#	foreach (@$rtab) {
#		print disp_heure($$_[3])," ",disp_heure($$_[4])," $$_[2]\n";
#	}
	$rtab;
}

1;

