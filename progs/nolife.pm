package progs::nolife;
#
#===============================================================================
#
#         FILE: nolife.pm
#
#  DESCRIPTION: 
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

use strict;
use warnings;
use out;
use Time::Local "timegm_nocheck";
 
sub new {
	my $class = shift;
	return bless {},$class;
}

sub update {
	print STDERR "updating noair...\n";
	my $xml = out::request("http://www.nolife-tv.com/noair/noair.xml");
	rename "air.xml", "air0.xml";
	open(F,">air.xml");
	print F $xml;
	close(F);
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

sub get {
	my ($p,$channel) = @_;
	return undef if (lc($channel) ne "nolife");

	if (!open(F,"<air.xml")) {
		update();
		if (!open(F,"<air.xml")) {
		   print "can't get noair listing\n";
		   return undef;
	   }
	}

	my $xml = "";
	while (<F>) {
		$xml .= $_;
	}
	close(F);
	Encode::from_to($xml, "utf-8", "iso-8859-15");
	$xml =~ s/½/oe/g;
	$xml =~ s/\&quot\;/\"/g;
	$xml =~ s/\&amp\;/\&/g;

	my ($title,$start,$old_title,$sub,$desc,$old_sub,$old_shot,$shot,
	$old_cat,$cat);
	my $date;
	my $cut_date = undef;
	my $rtab = undef;
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
			my @tab = (1500, "Nolife", $old_title, $start, $date, $old_cat,
				$desc,"","",$old_shot,0,0,get_date($start));
			push @$rtab,\@tab;
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
	# Test le dernier programme !
	my @tab = (1500, "Nolife", $old_title, $start, $date, $old_cat,
		$desc,"","",$old_shot,0,0,get_date($start));
	\@tab;
}

1;

