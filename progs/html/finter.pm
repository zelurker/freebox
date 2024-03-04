package progs::html::finter;

use HTML::Entities;
use Time::Local "timelocal_nocheck", "timegm_nocheck";
# use Cpanel::JSON::XS qw(decode_json);
use common::sense;
use Data::Dumper;

sub get_tag {
	my ($s,$t) = @_;
	if ($s =~ /$t"?="(.+?)"/) { # la version normale, avec des "
		return $1;
	}
	if ($s =~ /$t"?="?(.+?)"?([ >]|$)/) { # sinon on essaye de deviner !
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

sub disp_date {
	my $start = shift;
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime($start);
	return sprintf("%d/%d/%d %02d:%02d",$mday,$mon+1,$year+1900,$hour,$min);
}

sub check_start {
	my ($ref, $prev_start) = @_;
	# les programmes de la nuit de finter sont pétés en avril 22, les
	# heures indiquent l'heure de la 1ère diffusion pour les redifs !
	if ($$ref < $prev_start-3600) {
		# on teste avec prev_start-3600 parce qu'ils collent leur playlist
		# de la nuit comme bouche trou si il reste de la place, mais vu
		# qu'on est obligé de mettre 1h pour chaque programme, y a des
		# jours où il en reste pas, elle doit être plutôt courte cette
		# playlist... !
		my ($sec,$min,$hour,$mday,$mon,$year) = localtime($prev_start+3600);
		if ($hour == 0 && $min == 0) { # journal de 23h, c'est encore pire !
			($sec,$min,$hour,$mday,$mon,$year) = localtime($prev_start+15*60); # on dit 23h15 pour le suivant ? C'est variable, mais si c'est pas indiqué... !
			$$ref = timelocal_nocheck(0,$min,$hour,$mday,$mon,$year);
			return;
		}
		$$ref = timelocal_nocheck(0,5,$hour,$mday,$mon,$year);
	}
}

sub decode_html {
	my ($p,$l,$name) = @_;
	my $rtab = [];
	my $pos = 0;
	my $date;
	my $prev_start;
	my $keep_date = undef;
	my $rtab2 = $p->{chaines}->{lc($name)};
	if ($rtab2) {
		$prev_start = $$rtab2[$#$rtab2][3];
		say "prev_start init ".disp_date($prev_start);
	}
	while (($pos = index($l,"<",$pos))>= 0) {
		my $bl = index($l," ",$pos);
		my $instr = substr($l,$pos+1,$bl-$pos-1);
		my $sub_pos = index($l,">",$pos);
		my ($start,$end);
		my $sub = substr($l,$pos+1,$sub_pos-$pos-1);
		my ($desc,$title,$img);
		$pos = $sub_pos;

		if ($instr eq "li") {
			my $class = get_tag($sub,"class");
			if ($class =~ /^date-time-field/) {
				$date = get_tag($l,"value");
				$keep_date = 1;
			}
			if ($class =~ /^TimeSlot/) {
				my $body = substr($l,$sub_pos+1);
				my $end_pos = find_closing_tag($body,0,"li");
				$pos += $end_pos;
				$body = substr($body,0,$end_pos);
				my $btn = index($body,"<time ");
				if ($btn >= 0) {
					$sub_pos = index($body,">",$btn+1);
					$sub = substr($body,$btn,$sub_pos-$btn-1);
					$class = get_tag($sub,"datetime");
					my ($year,$month,$day,$hour,$min,$sec) = $class =~ /(....)-(..)-(..)T(..):(..):(..)/;
					$date = "$day/$month/$year" if (!$date);
					$start = timegm_nocheck($sec,$min,$hour,$day,$month-1,$year-1900);
					say "start from datetime $start";
				} else {
					$btn = index($body,"<div class=\"time ");
					if ($btn >= 0) {
						$btn = index($body,">",$btn+1)+1;
						$sub_pos = find_closing_tag($body,$btn+1,"div")-1;
						$start = substr($body,$btn,$sub_pos-$btn-1);
						($start,$end) = $start =~ /(.+) - (.+)/;
						my ($hstart,$mstart) = $start =~ /(\d+)h(\d+)/;
						my ($hend,$mend) = $end =~ /(\d+)h(\d+)/;
						my ($mday,$mon,$year) = split (/\//,$date);
						$mon--;
						$year -= 1900;
						$start = timegm_nocheck(0,$mstart,$hstart,$mday,$mon,$year);
						$end = timegm_nocheck(0,$mend,$hend,$mday,$mon,$year);
					}
				}

				$btn = index($body,"<picture");
				if ($btn >= 0) {
					$sub_pos = find_closing_tag($body,$btn+1,"picture");
					$sub = substr($body,$btn,$sub_pos-$btn-1);
					$img = get_tag($sub,"srcset");
				}
				$btn = index($body,"<div class=\"TimeSlot-info");
				if ($btn >= 0) {
					$btn = index($body,"<a ",$btn+1)+1;
					$sub_pos = index($body,"</a",$btn+1);
					$btn = index($body,">",$btn+1)+1;
					$title = substr($body,$btn,$sub_pos-$btn);
				} else {
					$btn = index($body,"<div class=\"title svelte");
					if ($btn >= 0) {
						$btn = index($body,">",$btn+1)+1;
						$sub_pos = find_closing_tag($body,$btn+1,"div")-1;
						$title = substr($body,$btn,$sub_pos-$btn-1);
					}
				}
				$btn = index($body,"<div class=\"TimeSlot-subtitle");
				if ($btn >= 0) {
					$sub_pos = find_closing_tag($body,$btn+1,"div")-1;
					$btn = index($body,">",$btn+1)+1;
					$desc = substr($body,$btn,$sub_pos-$btn-1);
				}
				say "start $start date $date title $title img $img";
			} else {
				next;
			}
		}
		elsif ($instr eq "article") { # finter avant 2022... !
			# bien pratique france inter ils ont ajouté un tag <article>
			# pour séparer leurs programmes.
			# Par contre y a ni heure de fin, ni durée, donc faut deviner,
			# un peu le bordel... Y des zolies images par contre ! :)
			$start = get_tag($sub,"data-start-time");
			my $class0 = get_tag($sub,"class");
			my $rubrique = $class0 =~ / step/;
			my ($sec,$min,$hour,$mday,$mon,$year) = localtime($start+3600);
			$date = sprintf("$mday/%d/%d",$mon+1,$year+1900);
			$end = timelocal_nocheck(0,0,$hour,$mday,$mon,$year);
			my $body = substr($l,$sub_pos+1);
			$body =~ s/<\/article.+//s;
			my $tit;
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
				} elsif ($class =~ /content-title/) { # || !$class) {
					$desc = $tit;
				}
			}
			if ($body =~ s/<img(.+?)>//s) {
				my $args = $1;
				if ($args =~ /data-(.+?)-src="(.+?)"/) {
					$img = $2;
				} elsif ($args =~ / src="(.+?)"/) {
					$img = $1;
				}
			}
			if ($rubrique) {
				# donc les rubriques d'une émission, le titre et l'image
				# sont récupérées dans l'émission, càd le dernier programme
				# stocké dans $rtab
				$img = $$rtab[$#$rtab][9];
				$title = $$rtab[$#$rtab][2];
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
		$prev_start = $start;
		($title,$start,$end,$desc,$img) = undef;
		$date = undef if (!$keep_date);
		redo;
	}
	$rtab;
}

1;

