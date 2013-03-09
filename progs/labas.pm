package progs::labas;
#
#===============================================================================
#
#         FILE: labas.pm
#
#  DESCRIPTION: contenu site la-bas.org.
#  Très particulier comme module, il n'y a pas d'heures du tout, du coup
#  on surcharge get, next et prev pour une fois...
#
#        FILES: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Emmanuel Anne (), emmanuel.anne@gmail.com
# ORGANIZATION: 
#      VERSION: 1.0
#      CREATED: 09/03/2013 00:53:47
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use Time::Local qw(timelocal);
use progs::telerama;
@progs::labas::ISA = ("progs::telerama");
 
our @tab;
our $last_chan;

sub get {
	my ($p,$channel,$source,$base_flux) = @_;
	return undef if ($source ne "flux" || $base_flux !~ /^la-bas/);
	return \@tab if ($last_chan && $last_chan eq $channel);
	$last_chan = $channel;

	# Calcule le nombre d'épisodes depuis vendredi 8/3/2013 (2710ème !)
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $t0 = timelocal(0,0,12,$mday,$mon,$year);
	$t0 -= 24*3600 if ($wday == 6);
	$t0 -= 48*3600 if ($wday == 0 || $wday == 7);
	$base_flux =~ s/^.+?\///; # Dégage la partie la-bas, ne garde que la date
	my @t = split(/\//,"$base_flux/$channel");
	return undef if ($#t < 2);
	my $t = timelocal(0,0,12,$channel,$t[1]-1,$t[0]-1900);
	my $ecart = ($t - $t0) / (24*3600);
	# En fait y a des articles qui s'intercalent en dehors des émissions donc
	# on ne peut pas déduire directement le numéro de l'article.
	# Par contre on peut le retrouver en une seule requête
	my $nb_s = int($ecart/7);
	my $nb = abs($ecart-$nb_s*2);
	my $index = chaines::request("http://www.la-bas.org/mot.php3?id_mot=63&debut_lb=$nb");
	$index =~ /Micro.gif.+?article=(.+?)"/;
	$ecart = $1;
	
	my $prog = chaines::request("http://www.la-bas.org/article.php3?id_article=$ecart");
	$prog =~ s/\&\#8217\;/'/g;
	$prog =~ s/\&nbsp\;/ /g;
	# A priori les images sont de la forme arton<numéro d'article>.jpg
	# mais on peut toujours récupérer ça dans le source...
	my ($img,$titre,$desc);
	if ($prog =~ /img border=0 src='(.+?)'/) {
		$img = $1;
	}
	if ($prog =~ /font size="5".+?<b>(.+?)<\/b/s) {
		$titre = $1;
	}
	$desc = "";
	while ($prog =~ s/p class="spip">(.+?)<\/p>//s) {
		$desc .= $1;
		$desc =~ s/<br>/\n/g;
	}

	@tab = (undef, "la-bas.org", "$titre",
		undef, # début
		undef, "", # fin
		$desc, # desc
		"","",
		$img, # img
		0,0,
		"$channel/$t[1]/$t[0]");
	return \@tab;
}

sub next {
	my ($p,$channel) = @_;
	return \@tab if ($channel eq $last_chan);
}

sub prev {
	my ($p,$channel) = @_;
	return \@tab if ($channel eq $last_chan);
}

1;
