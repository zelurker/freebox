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

# Récupérés par google images, voir le script search_radios.pl
my %icons = (
"4U Classic Rock" => "http://i.img.co/radio/91/11/1191_290.png",
"Accent 4" => "http://www.accent4.com/images/logo_accent4.png",
"Alouette" => "http://www.myconseils.fr/wp-content/uploads/2011/03/ALOUETTE2.jpg",
"Alpes 1" => "http://rad.io/images/broadcasts/1417_4.jpeg",
"Alternantes" => "http://www.alternantesfm.net/images/logo_alternantes_300x170.jpg",
"Atlantis FM" => "http://1.bp.blogspot.com/_EddTYk9zrag/TSeLNjaFQtI/AAAAAAAAAPg/V-22cLtSdh8/s1600/ATLANTIS%252BRADIO%252BLOGO.jpg",
"BFM" => "http://www.lesinsurges.com/blog/wp-content/uploads/2012/09/Bfm.jpg",
"Bide et Musique" => "http://www.bide-et-musique.com/images/logo/logo-fondnoir.jpg",
"C9 Radio" => "http://a1.twimg.com/profile_images/841373176/c9-lite-violet.png",
"CambosFM" => "http://i.img.co/radio/87/92/19287_145.png",
"Clube Brazil" => "http://a2.ec-images.myspacecdn.com/images02/115/2553a924daf14c39967bca38bb319345/l.jpg",
"Cocktail FM" => "http://www.cocktailfm.com/images/logo-cocktailfm.png",
"Demoiselle FM" => "http://lesrosarines.trophee-roses-des-sables.org/files/2012/04/demoiselle-fm.jpg",
"Enjoy Station" => "http://blog.camtoya.com/wp-content/uploads/2010/03/LogoEnjoyOrange1.png",
"Euradio Nantes" => "http://www.eng.notre-europe.eu/images/bibli/euradionantes.jpg_574_800_2",
"Europe 1" => "http://www.tv14.net/wp-content/uploads/2010/06/Europe-1-Radio.jpg",
"FG DJ Radio" => "http://www.panthersounds.com/cms/general/upload/1353512918_fg-dj-radio-france.jpg",
"FG Underground" => "http://radio.fr/images/broadcasts/1578_4.gif",
"FIP" => "http://www.tv14.net/wp-content/uploads/2010/06/FIP-Radio.jpg",
"FMC Radio" => "http://rad.io/images/broadcasts/4420_4.gif",
"France Culture" => "http://www.institutfrancais.es/bilbao/adjuntos/logo-france-culture.jpg",
"France Inter" => "http://www.scholastiquemukasonga.net/home/wp-content/uploads/2012/03/France-inter.jpg",
"France Musique" => "http://www.radiosnumeriques.com/wp-content/uploads/2012/07/france-musique.jpg",
"Frequence 3" => "http://www.leclubradio.com/wp-content/uploads/2012/03/Logo-Frequence3.jpg",
"Frequence Terre" => "http://www.blog.terracites.fr/wp-content/uploads/2011/05/LogoFrequenceTerre.jpg",
"Fun Radio" => "http://www.tignes.net/data/fckeditor/Logo-Fun-Radio.jpg",
"Graffiti Urban Radio" => "http://a4.ec-images.myspacecdn.com/images02/152/5ce85b0e0be249e49d767ca1f43977d0/l.jpg",
"Hit West" => "http://www.myconseils.fr/wp-content/uploads/2011/10/logo_hit_west.jpg",
"Hot Mix Radio - 80" => "http://en.lixty.net/upload/stations/100/41174_hot_mix_radio_80.png",
"Hot Mix Radio - 90" => "http://www.hotmixradio.fr/player/playerhtm/img/picto/new/90s.png",
"Hot Mix Radio - Funky" => "http://en.lixty.net/upload/stations/100/59205_hot_mix_radio_funky.png",
"Kif Radio" => "http://thc-fungames.e-mengine.com/archiver/www.jammin-unity.be/wp-content/uploads/2010/01/logo_kif_978.jpg",
"Kiss FM" => "http://www.inspiringbirthstories.com.au/wp-content/uploads/2012/09/kiss_fm.gif",
"La Grosse Radio" => "http://www.lagrosseradio.com/_images/logos/officiels/Logo_GrosseRadio_300dpi.png",
"La Grosse Radio Rock" => "http://www.lagrosseradio.com/_images/haut/logo_rock.png",
"La Grosse Radio Metal" => "http://www.lagrosseradio.com/_images/haut/logo_metal.png",
"La Grosse Radio Reggae" => "http://lagrosseradio.com/_images/logos/officiels/Logo_GrosseRadioReggae_300dpi.png",
"Le Mouv'" => "http://radiotraque.imca.fr/files/2011/09/Logo-le-mouv.jpg",
"M2 Radio" => "http://rad.io/images/broadcasts/3028_4.jpeg",
"M2 Radio - Chillout" => "http://www.m2radio.fr/images/logos/M/m2_chillout_t.png",
"M2 Radio - Love" => "http://www.m2radio.fr/images/logos/M/m2_love_t.png",
"M2 Radio - Sunshine" => "http://www.m2radio.fr/images/logos/M/m2_sunshine_t.png",
"Maxi 80" => "http://rad.io/images/broadcasts/1726_4.gif",
"Maxxima" => "https://twimg0-a.akamaihd.net/profile_images/1107883540/maxxima_bg_w.png",
"MFM" => "http://final6rugby2012.com/wp-content/uploads/2012/03/Logo-MFM-1.jpg",
"MFM Lovers" => "http://i.img.co/radio/91/17/31791_290.png",
"MFM Goldman" => "http://en.lixty.net/upload/stations/100/24658_mfm_100_jean_jacques_goldman.png",
"MFM Duos" => "http://i.img.co/radio/88/17/31788_90.png",
"MFM Culte 60 70" => "http://i.img.co/radio/86/17/31786_290.png",
"MFM Culte 80 90" => "http://mfmradio.fr/media/radios/culte-80-90-80px.png",
"Nostalgie" => "http://www.creads.org/blog/wp-content/uploads/2009/05/nouveau_logo_nostalgie2.jpg",
"Nostalgie stars 80" => "http://i.img.co/radio/91/52/35291_290.png",
"Nostalgie Ciné tubes" => "http://i.img.co/radio/80/34/33480_290.png",
"NRJ" => "http://www.24enfants.org/wp-content/uploads/2011/12/logo-NRJ1.jpg",
"NRJ Lounge" => "http://i.img.co/radio/11/37/23711_290.png",
"NTI" => "http://www.radionti.com/images/logo.gif",
"Oui FM" => "http://www.radiosnumeriques.com/wp-content/uploads/2012/06/ouifm.jpeg",
"Oui FM Alternatif" => "http://i.img.co/radio/97/89/8997_290.png",
"Oui FM Collector" => "http://i.img.co/radio/96/89/8996_290.png",
"Oui FM Blues" => "http://i.img.co/radio/22/70/27022_290.png",
"Oui FM DJ Zebra" => "http://djzebra.free.fr/pix/badge_DJZebra_OUiFm.jpg",
"Paris One Club" => "http://a1.ec-images.myspacecdn.com/images02/70/47fc89ff1e4c4a0987fb8249fab3164c/m.jpg",
"Paris One Reverse" => "http://a1.ec-images.myspacecdn.com/images02/85/0d41ecd21410432bb171063893cc391e/l.jpg",
"Paris One Deeper" => "https://twimg0-a.akamaihd.net/profile_images/639108742/P1Deeper_320.png",
"Paris One Trance" => "http://gsmusic.free.fr/images/flytsparisone.jpg",
"Paris One Dance" => "http://a4.ec-images.myspacecdn.com/images01/20/b25af6a19a0b4d4e9d042b3c06e90d4d/m.png",
"Prun" => "http://www.prun.net/im/design/logo.png",
"Puls Radio" => "http://rad.io/images/broadcasts/1813_4.gif",
"Radio Alpine Meilleure" => "http://perlbal.hi-pi.com/blog-images/221828/gd/1140613570/Radio-Alpine-Meilleure.jpg",
"Radio Bresse" => "http://www.bresse-bourguignonne.com/bibliotheque/logos/partenaires2012/locaux/Radio_Bresse.jpg",
"Radio Classique" => "http://www.radiosnumeriques.com/wp-content/uploads/2012/06/radio_classique1.jpg",
"Radio Côte d'Amour" => "http://www.franck-gergaud.com/images_content/Radio_Cote_signature.jpg",
"R'courchevel" => "http://i.img.co/radio/15/14/1415_290.png",
"Radio Intensite" => "http://www.le28.com/images/bann/logo_intensite_v.gif",
"Radio RDL" => "http://www.bieres.tv/wp-content/uploads/2010/07/logo-RDL.jpg",
"Radio TeenTall" => "http://1.bp.blogspot.com/-skx7uKgFTD8/ULssmGzHcOI/AAAAAAAAAm4/suGjz-QaXvQ/s1600/RADIO%252BTEENTALL.jpg",
"RBI FM" => "http://www.bluegrassmuseum.org/_assets/photos/rbi/RBI_logo_small.jpg",
"RFM" => "http://static1.ozap.com/articles/4/42/13/24/%40/4261418-le-logo-de-la-radio-rfm-diapo-1.jpg",
"RFM Night Fever" => "http://a2.ec-images.myspacecdn.com/images01/59/59b88d05e8dd0a0c72ac601003ab84e7/l.jpg",
"RST" => "http://www.vdc-nrw.com/userfiles/image/Logo_RadioRST.png",
"RTL" => "http://www.dorea-deco.com/wp-content/uploads/2010/12/logo-rtl1.jpg",
"RTL 2" => "http://www.radiosnumeriques.com/wp-content/uploads/2012/06/rtl2.jpg",
"Sun" => "http://www.lafrap.fr/sites/default/files/u56/sun.png",
"Virgin Radio" => "http://logok.org/wp-content/uploads/2010/09/virgin-radio1.jpg",
"Virgin Radio club" => "http://cdn-musique.ladmedia.fr/var/musiline/storage/images/virginradio/webradios/virgin-radio-club/567-10-fre-FR/Virgin-Radio-Club_webradio_198x198.jpg",
"Virgin radio pop rock" => "http://cdn-musique.ladmedia.fr/var/musiline/storage/images/virginradio/webradios/virgin-radio-poprock/557-8-fre-FR/Virgin-Radio-PopRock_webradio_198x198.jpg",
"Ze Radio" => "http://www.startrackcrush.com/wp-content/uploads/2012/08/logo-Zeradio.gif",
);

sub get_radio_pic {
	my ($name,$rpic) = @_;
	my $url = $icons{$name};
	if ($url) {
		($name) = $url =~ /.+\/(.+)/;
#		print STDERR "channel name $name from $url\n";
		$name = "radios/$name";
		if (! -f $name) {
#			print STDERR "no channel logo, trying to get it from web\n";
			push @$rpic,($name,$url);
		}
	} else {
		$name = "";
	}
	$name;
}

mkdir "radios" if (!-d "radios");
1;

