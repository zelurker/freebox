package progs::html::finter;

use HTML::Entities;
use Time::Local "timelocal_nocheck";
use v5.10;

sub get_tag {
	my ($s,$t) = @_;
	if ($s =~ /$t"?="?(.+?)"?([ >]|$)/) {
		return $1;
	}
	undef;
}

sub find_closing_tag {
	my ($body,$pos,$tag) = @_;
	my $level = 1;
	while ($level && ($pos = index($body,$tag,$pos+1))>=0) {
		if (substr($body,$pos-2,2) eq "</") {
			$level--;
		} elsif (substr($body,$pos-1,1) eq "<") {
			$level++;
		}
	}
	$pos;
}

sub decode_html {
	my ($p,$l,$name) = @_;
	my $rtab = [];
	my $pos = 0;
	my $date;
	while (($pos = index($l,"<",$pos))>= 0) {
		my $bl = index($l," ",$pos);
		my $instr = substr($l,$pos+1,$bl-$pos-1);
		my $sub_pos = index($l,">",$pos);
		my ($start,$end);
		my $sub = substr($l,$pos+1,$sub_pos-$pos-1);
		my ($desc,$title,$img);
		$pos = $sub_pos;

		if ($instr eq "article") { # finter
			# bien pratique france inter ils ont ajouté un tag <article>
			# pour séparer leurs programmes.
			# Par contre y a ni heure de fin, ni durée, donc faut deviner,
			# un peu le bordel... Y des zolies images par contre ! :)
			$start = get_tag($sub,"data-start-time");
			my ($sec,$min,$hour,$mday,$mon,$year) = localtime($start+3600);
			$date = sprintf("$mday/%d/%d",$mon+1,$year+1900);
			$end = timelocal_nocheck(0,0,$hour,$mday,$mon,$year);
			my $body = substr($l,$sub_pos+1);
			$body =~ s/<\/article.+//s;
			while ($body =~ s/<a (.+?)>//s) {
				my $args = $1;
				my $class;
				if ($args =~ /class="(.+?)"/) {
					$class = $1;
				}
				if ($args =~ /title="(.+?)"/) {
					$tit = $1;
				}
				# print "tit $tit args $args\n";
				if ($class =~ /emission-title/) {
					$title = $tit;
					# Après faut sortir tout de suite de la boucle !!!
					# $pos = index($l,"<span>",$pos+1);
					# last;
				} elsif ($class =~ /content-title/ || !$class) {
					$desc = $tit;
				}
			}
			if ($body =~ s/<img(.+?)>//s) {
				my $args = $1;
				if ($args =~ /data-pagespeed-(.+?)-src="(.+?)"/) {
					$img = $2;
				} elsif ($args =~ / src="(.+?)"/) {
					$img = $1;
				}
			}
		} elsif ($instr eq "div") { # fmusique
			$start = get_tag($sub,"data-start-time");
			$end = get_tag($sub,"data-end-time"); # fculture
			next if (!$start);
			my $body = substr($l,$sub_pos+1);
			my $end_pos = find_closing_tag($body,0,"div");

			# On ne fait pas pos += end_pos parce que quand il y a des sous
			# programmes, appelés rubriques dans leur programme, ils
			# apparaissent avec exactement le même format, donc autant les
			# laisser se faire traiter par la boucle principale !
			# $pos += $end_pos;

			$body = substr($body,0,$end_pos);
			($title) = $body =~ /<h2.*?>(.+?)<\/h2>/s;
			($desc) = $body =~ /<h3.+?>(.+?)<\/h3>/s;
			($desc) = $body =~ /<div class=".+?subtitle">(.+?)<\//s if (!$desc);
			my ($duration) = $body =~ /<div class=".+?duration">(.+?)<\/div/s;
			my ($h,$m) = (0,0);
			if ($duration =~ /h/) {
				($h,$m) = $duration =~ /(\d+) ?h ?(\d+)/;
				($h) = $duration =~ /(\d+) ?h/ if (!$h);
			}
			$duration =~ /(\d+) ?m/;
			$m = $1 if (!$m);
			$end = $start + $h*3600+$m*60;
			my ($sec,$min,$hour,$mday,$mon,$year) = localtime($start+3600);
			$date = sprintf("$mday/%d/%d",$mon+1,$year+1900);
			my ($args) = $body =~ /<img(.+?)>/s;
			if ($args) {
				# pas d'images sur france culture !
				$args =~ s/dejavu-src="(.+?)"//;
				$img = $1;
				$args =~ s/src="(.+?)"//;
				$img = $1 if (!$img);
			}
			# et sur fculture y a des retours à la ligne et des espaces en
			# trop dans les champs donc faut un peu filtrer...
			$title =~ s/[\r\n]//g;
			$desc =~ s/[\r\n]//g;
			$title =~ s/^ +//;
			$desc =~ s/^ +//;
		} elsif ($instr eq "li") { # fbleu
			next if ($sub !~ /class="emission/);
			my $body = substr($l,$sub_pos+1);
			my $end_pos = find_closing_tag($body,0,"li");
			my ($time,$date) = $p->init_time();
			$body = substr($body,0,$end_pos);
			my ($hd,$hf) = $body =~ /div class="quand">(\d+h\d+).+?- (\d+h\d+)/s;
			($title) = $body =~ /h3 class="titre">(.+?)<\/h3/;
			my ($h,$m) = split(/h/,$hd);
			$start = $time + $h*3600+$m*60;
			($h,$m) = split(/h/,$hf);
			$end = $time + $h*3600+$m*60;
			$desc = "";
			my $old_pos = $pos + $end_pos;
			$pos = 0;
			my $nb = 0;
			while (($pos = index($body,'<li class="chronique',$pos+1)) >= 0) {
				$end_pos = find_closing_tag($body,$pos+2,"li");
				my $chro = substr($body,$pos,$end_pos-$pos);
				$desc .= "$1 " if ($chro =~ /div class="horaire".+?(\d+h\d+)/s);
				$desc .= "$1" if ($chro =~ /p class="titre.+?>(.+?)<\/p>/);
				$desc .= " ($1)" if ($chro =~ /class="titre">(.+?)<\/a/);
				$desc .= "\n";
			}
			$pos = $old_pos;
		} else {
			$pos++;
			next;
		}

		my @tab = (undef, $name, $title, $start,
			$end, "",
			$desc,
			"","",$img,0,0,$date);
		$p->insert(\@tab,$rtab,600);
		redo;
	}
	$rtab;
}

1;

