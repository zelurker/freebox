package progs::nolife;
#
#===============================================================================
#
#         FILE: nolife.pm
#
#  DESCRIPTION: Ca fait un bon exemple d'héritage de la telerama
#  Seule méthode surchargée : update. new, next et prev doivent marcher tout
#  seuls !
#
#        FILES: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Emmanuel Anne (), emmanuel.anne@gmail.com
# ORGANIZATION: 
#      VERSION: 1.0
#      CREATED: 05/03/2013 12:57:07
#     REVISION: ---
#===============================================================================

use progs::telerama;
@ISA = ("progs::telerama");
use strict;
use warnings;
use Time::Local "timegm_nocheck";
use Encode;
use chaines;
 
my $last_time;
my $debug = 0;

sub update_noair {
	return if ($last_time && time()-$last_time < 60);
	$last_time = time();
	print STDERR "updating noair...\n" if ($debug);
	my $xml = chaines::request("http://www.nolife-tv.com/noair/noair.xml");
	rename "air.xml", "air0.xml";
	open(F,">air.xml");
	print F $xml;
	close(F);
	return 1;
}

sub conv_date {
	my $date = shift;
	my ($a,$mois,$j,$h,$m,$s) = $date =~ /^(....).(..).(..) (..).(..).(..)/;
	timegm_nocheck($s,$m,$h,$j,$mois-1,$a-1900);
}

sub get_date {
	my $time = shift;
	my ($sec,$min,$hour,$mday,$mon,$year) = gmtime($time); 
	sprintf("%d/%02d/%02d",$mday,$mon+1,$year+1900);
}

sub get_field {
	my ($line,$field) = @_;
	$line =~ /$field\=\"(.*?)\"/;
	$1;
}

sub update {
	my ($p,$channel) = @_;
	print "nolife: update $channel\n" if ($debug);
	return undef if (lc($channel) ne "nolife");

	my $f;
	if (!open($f,"<air.xml")) {
		update_noair();
		if (!open($f,"<air.xml")) {
		   print "can't get noair listing\n";
		   return undef;
	   }
	}

	my $xml = "";
	while (<$f>) {
		$xml .= $_;
	}
	close($f);
	Encode::from_to($xml, "utf-8", "iso-8859-15");
	$xml =~ s/½/oe/g;
	$xml =~ s/\&quot\;/\"/g;
	$xml =~ s/\&amp\;/\&/g;

	my ($title,$start,$old_title,$sub,$desc,$old_sub,$old_shot,$shot,
	$old_cat,$cat);
	$title = $old_title = "";
	my $date;
	my $cut_date = undef;
	my $rtab = $p->{chaines}->{nolife};
	$cut_date = $$rtab[0][3] if ($rtab);
	foreach (split /\n/,$xml) {
		next if (!/\<slot/);

		$date = conv_date(get_field($_,"dateUTC"));
		# print get_time($date)," ",$_->{title},"\n";
		$start = $date if (!$start);
		if ($cut_date) {
			if ($start > $cut_date) {
				# Des fois nolife corrige ses programmes, le nouveau qui arrive a
				# priorité dans ce cas là
				my $n;
				for ($n=0; $n<=$#$rtab; $n++) {
					last if ($$rtab[$n][3] >= $start);
				}
				splice @$rtab,$n if ($n < $#$rtab);
			}
			$cut_date = undef;
		}

		$old_title = $title;
		$old_sub = $sub;
		$old_shot = $shot;
		$old_cat = $cat;
		$title = get_field($_,"title");
		$sub = get_field($_,"sub-title");
		$title = $sub if (!$title);
		$shot = get_field($_,"screenshot");
		if ($title eq $old_title && !$shot) {
			$shot = $old_shot; # On garde l'image si le titre ne change pas
		}
		$cat = get_field($_,"type");
		if ($start && $old_title && $old_title ne $title) {
			my $found = 0;
			foreach (@$rtab) {
				if ($$_[3] == $start && $$_[4] == $date) {
					$found = 1;
					last;
				}
			}
			if (!$found) {
				my @tab = (1500, "Nolife", $old_title, $start, $date, $old_cat,
					$desc,"","",$old_shot,0,0,get_date($start));
				push @$rtab,\@tab;
			}
			$start = $date;
			$desc = "";
		}
		my $d = get_field($_,"description");
		if ($d ne $title) {
			$desc .= "\n" if ($desc);
			$desc .= "$d";
			my $d = get_field($_,"detail");
			$desc .= " $d" if ($d);
		}
	}
	if ($date < time()) {
		# programme périmé !
		# Apparemment le nouveau programme de nolife s'étend sur une 20aine
		# de jours, donc là on peut forcer une update
		if (update_noair()) {
			return $p->get($channel);
		}
	}
	# Test le dernier programme !
	my @tab = (1500, "Nolife", $old_title, $start, $date, $old_cat,
		$desc,"","",$old_shot,0,0,get_date($start));

	push @$rtab,\@tab;
	$p->{chaines}->{nolife} = $rtab;
	$rtab;
}

1;

