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

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $t0 = timelocal(0,0,12,$mday,$mon,$year);
	$t0 -= 24*3600 if ($hour < 15 && ($wday >= 1 && $wday <= 5)); # Si on est avant l'heure de diffusion
	$t0 -= 24*3600 if ($wday == 6);
	$t0 -= 48*3600 if ($wday == 0 || $wday == 7);
	$base_flux =~ s/^.+?\///; # Dégage la partie la-bas, ne garde que la date
	my @t = split(/\//,"$base_flux/$channel");
	return undef if ($#t < 2);
	my $t = timelocal(0,0,12,$channel,$t[1]-1,$t[0]-1900);
	if ($t > $t0) {
		# Dans le futur ?!!
		@tab = (undef, "la-bas.org", "-",
			undef, # début
			undef, "", # fin
			"Pas encore d'info", # desc
			"","",
			"", # img
			0,0,
			"$channel/$t[1]/$t[0]");
		return \@tab;
	}
	my $ecart = 0;
	while ($t < $t0) {
		# calcule le nombre de jours d'émission (ecart)
		# C'est merdique parce que ça revient à calculer le nombre de jours
		# travaillés, il devrait y avoir une fonction pour ça dans le module
		# date, y a peut-être un module quelconque qui fait ça mais bon... !
		my ($sec,$min,$hour,$mday,$mon,$year,$wday) = localtime($t);
		if ($wday == 5) { # vendredi
			$t += 3*24*3600;
		} else {
			$t += 24*3600;
		}
		$ecart++;
	}

	print STDERR "écart calculé $ecart à partir de $base_flux/$channel\n";
	# En fait y a des articles qui s'intercalent en dehors des émissions donc
	# on ne peut pas déduire directement le numéro de l'article.
	# Par contre on peut le retrouver en une seule requête
	my $index = chaines::request("http://www.la-bas.org/mot.php3?id_mot=63&debut_lb=$ecart");
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
