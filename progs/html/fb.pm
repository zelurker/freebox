package progs::html::fb; # france bleu

my ($rtab,$titre,$sub,$desc,$start,$end,$time,$img,$t,$date,$name);

# C'est + une preuve de concept qu'autre chose, je n'écoute quasiment
# jamais ces radios, mais radio france a fait une jolie page de programme
# et j'étais curieux de voir si on pouvait la récupérer par script... et je
# suis étonné de voir à quel point le script pour ça est court !!!

sub conv_time {
	my $t = shift;
	my ($h,$m) = split (/h/,$t);
	$h*3600+$m*60+$time;
}

sub disp_titre {
	my $p = shift;
	if ($start && $titre) {
		# Pas encore affiché !
		$p->insert([undef, $name, $titre, $start,
			$end, "",
			"",
			"","",$img,0,0,$date],$rtab);
# 		print disp_time($start)," - ",disp_time($end)," : $titre" .
# 		($img ? "img $img" : "")."\n";
		$img = undef;
		undef $titre;
	}
}

sub decode_html {
	my ($p,$l);
	($p,$l,$name) = @_;
	my $pos = 0;
	$rtab = [];
	($time,$date) = $p->init_time();

	my @lines = split (/\n/,$l);
	for (my $n=0; $n<=$#lines; $n++) {
		$_ = $lines[$n];
		if (/div class="quand">(.+) - (.+)<\/div/) {
			disp_titre($p);
			($start,$end) = ($1,$2);
			foreach ($start,$end) {
				$_ = conv_time($_);
			}
		} elsif (/h3 class="titre">(.+)<\/h3/) {
			$titre = $1;
		} elsif (/<img.*src="(http.+?)"/) {
			my $old = $1;
			if ($img) {
				disp_titre($p);
			}
			$img = $old;
		} elsif (/div class="horaire">/) {
			$t = conv_time($lines[$n++]);
		} elsif (/p class="titre-emission">(.+)<\/p/) {
			$sub = $1;
		} elsif (/(<a .*class="titre">|<p class="titre">)(.+)<\//) {
			$desc = $2;
			if ($start && $t > $start) {
				$p->insert([undef, $name, $titre, $start,
						$end, "",
						"",
						"","",$img,0,0,$date],$rtab);
				undef $start;
			}
			$p->insert([undef, $name, $titre, $start,
					$end, "",
					"$sub\n$desc",
					"","",$img,0,0,$date],$rtab);
			undef $t;
			undef $desc;
		} elsif (/p class="titre-sidebar"/) {
			disp_titre($p);
			last;
		}
	}
	foreach (@$rtab) {
		print "$$_[3] $$_[4] $$_[2]\n";
	}
	$rtab;
}

1;
