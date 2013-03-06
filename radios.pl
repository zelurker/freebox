#!/usr/bin/env perl 
#===============================================================================
#
#         FILE: radios.pl
#
#        USAGE: ./radios.pl  
#
#  DESCRIPTION: 
#
#      OPTIONS: ---
# REQUIREMENTS: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Emmanuel Anne (), emmanuel.anne@gmail.com
# ORGANIZATION: 
#      VERSION: 1.0
#      CREATED: 06/03/2013 00:58:04
#     REVISION: ---
#===============================================================================

use strict;
use warnings;

my %icons = (
"Activ radio" => "http://upload.wikimedia.org/wikipedia/fr/8/85/Activ_radio_2012_logo.png",
"BFM" => "http://upload.wikimedia.org/wikipedia/fr/0/0d/BFM_Business_logo_2010.png",
"Bide et Musique" => "http://upload.wikimedia.org/wikipedia/commons/f/f7/BM_icone.png",
"Demoiselle FM" => "http://upload.wikimedia.org/wikipedia/fr/e/e2/Logo_Demoiselle_FM_%282012%29.jpg",
"FIP" => "http://upload.wikimedia.org/wikipedia/fr/3/35/Logo_Fip.jpg",
"France bleu Gascogne" => "http://upload.wikimedia.org/wikipedia/fr/4/43/France_Bleu_Gascogne.jpg",
"France Culture" => "http://upload.wikimedia.org/wikipedia/fr/5/55/Logo_France_Culture.png",
"France Musique" => "http://upload.wikimedia.org/wikipedia/fr/6/64/France_Musique_logo_2008.png",
"Fun Radio" => "http://upload.wikimedia.org/wikipedia/fr/e/eb/Fun_Radio.png",
"Graffiti Urban Radio" => "http://upload.wikimedia.org/wikipedia/fr/8/86/Graffiti_Radio.jpg",
"Hit West" => "http://upload.wikimedia.org/wikipedia/fr/b/bd/HitWestLogo.jpg",
"Le Mouv'" => "http://upload.wikimedia.org/wikipedia/fr/5/57/Logo_mouv_2005.png",
"MFM" => "http://upload.wikimedia.org/wikipedia/fr/b/bb/Logo-mfm.png",
"Nostalgie" => "http://upload.wikimedia.org/wikipedia/fr/9/9d/Logo_Nostalgie.png",
"Oxyradio" => "http://upload.wikimedia.org/wikipedia/commons/e/e1/Oxyradio-logo.png",
"Prun" => "http://upload.wikimedia.org/wikipedia/fr/0/02/Logo-prun-3wprunnet-%2B-92fm.jpg",
"Top Music" => "http://upload.wikimedia.org/wikipedia/fr/a/a2/Top_Music_logo.png",
);

sub get_radio_pic {
	my $name = shift;
	my $url = $icons{$name};
	if ($url) {
		($name) = $url =~ /.+\/(.+)/;
#		print STDERR "channel name $name from $url\n";
		$name = "radios/$name";
		if (! -f $name) {
#			print STDERR "no channel logo, trying to get it from web\n";
			my $browser = get_browser();
			my $response = $browser->get($url);

			if ($response->is_success) {
				open(my $f,">$name") || die "can't create channel logo $name\n";
				print $f $response->content;
				close($f);
			} else {
#				print STDERR "could not get logo from $url\n";
				$name = "";
			}
		}
	} else {
		$name = "";
	}
	$name;
}

mkdir "radios" if (!-d "radios");
1;

