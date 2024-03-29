#!/usr/bin/env perl

use strict;
use warnings;
use Encode;
use v5.10;

# R�cup�r�s par google images, voir le script search_radios.pl
my %icons = (
  "4U Classic Rock" => "http://db.radioline.fr/pictures/radio_959f92357a5d7a67f22b98f45d3ceb7d/logo200.jpg",
  "Accent 4" => "http://www.accent4.com/images/logo_accent4.png",
  "Alouette" => "http://www.myconseils.fr/wp-content/uploads/2011/03/ALOUETTE2.jpg",
  "Alpes 1" => "http://www.allzicradio.com/media/radios/alpes1_grenoble_600x600px_hq.png",
  "Alternantes" => "http://www.alternantesfm.net/images/logo_alternantes_300x170.jpg",
  "Atlantis FM" => "http://1.bp.blogspot.com/_EddTYk9zrag/TSeLNjaFQtI/AAAAAAAAAPg/V-22cLtSdh8/s1600/ATLANTIS%252BRADIO%252BLOGO.jpg",
  "BFM" => "http://cedrda.desertours.netdna-cdn.com/files/2015/03/logoBFMTV.png",
  "BFM Business" => "https://upload.wikimedia.org/wikipedia/fr/thumb/0/0d/BFM_Business_logo_2010.png/220px-BFM_Business_logo_2010.png",
  "Bide et Musique" => "http://www.bide-et-musique.com/images/logo/logo-fondnoir.jpg",
  "C9 Radio" => "http://www.allzicradio.com/media/radios/c9-radio.jpg",
  "CambosFM" => "http://i.img.co/radio/87/92/19287_145.png",
  "Ch�rie FM" => "http://players.nrjaudio.fm/live-metadata/player/img/player-files/cfm/logos/640x640/CHERIE_Default.png",
  "Ch�rie love songs" => "https://img.nrj.fr/zQCscFFmd2RrhkkDvjbn53Skb7g=/https%3A%2F%2Fplayers.nrjaudio.fm%2Flive-metadata%2Fplayer%2Fimg%2Fplayer-files%2Fcfm%2Flogos%2F173x173%2FP_CHERIE_LOVE_SONGS_3.png",
  "Ch�rie ZEN" => "https://img.nrj.fr/l6kRLoOqSNybFhkj6EoqR37eBj8=/https%3A%2F%2Fplayers.nrjaudio.fm%2Flive-metadata%2Fplayer%2Fimg%2Fplayer-files%2Fcfm%2Flogos%2F173x173%2FP_CHERIE_ZEN_3.png",
  "Ch�rie Love Songs" => "https://img.nrj.fr/zQCscFFmd2RrhkkDvjbn53Skb7g=/https%3A%2F%2Fplayers.nrjaudio.fm%2Flive-metadata%2Fplayer%2Fimg%2Fplayer-files%2Fcfm%2Flogos%2F173x173%2FP_CHERIE_LOVE_SONGS_3.png",
  "Ch�rie POP" => "https://img.nrj.fr/N2DpSreNO2To88RO8rEXes19G1A=/https%3A%2F%2Fplayers.nrjaudio.fm%2Flive-metadata%2Fplayer%2Fimg%2Fplayer-files%2Fcfm%2Flogos%2F173x173%2FP_CHERIE_POP.png",
  "Classic 21 128k mp3" => "https://upload.wikimedia.org/wikipedia/fr/thumb/6/68/Classic21.svg/150px-Classic21.svg.png",
  "Classic 21 64k aac" => "https://upload.wikimedia.org/wikipedia/fr/thumb/6/68/Classic21.svg/150px-Classic21.svg.png",
  "Clube Brazil" => "http://a2.ec-images.myspacecdn.com/images02/115/2553a924daf14c39967bca38bb319345/l.jpg",
  "Cocktail FM" => "http://www.cocktailfm.com/images/logo-cocktailfm.png",
  "Contact" => "http://www.radiocontact.be/GED/00000000/5900/5915.png",
  "Demoiselle FM" => "http://lesrosarines.trophee-roses-des-sables.org/files/2012/04/demoiselle-fm.jpg",
  "Enjoy Station" => "https://upload.wikimedia.org/wikipedia/commons/thumb/d/db/Logoenjoy33justplay.png/220px-Logoenjoy33justplay.png",
  "Euradio Nantes" => "http://euradio.fr/wp-content/uploads/Euradio-logoNB.png",
  "Europe 1" => "http://www.tv14.net/wp-content/uploads/2010/06/Europe-1-Radio.jpg",
  "FG" => "https://ecouter.lesindesradios.net/logos/orange65.png",
  "FG Chic" => "https://ecouter.lesindesradios.net/logos/orange235.png",
  "FG Mix" => "https://ecouter.lesindesradios.net/logos/orange237.png",
  "FG Deep Dance" => "https://ecouter.lesindesradios.net/logos/orange234.png",
  "FG Underground" => "http://images.radio.orange.com/radios/large_underground_fg.png",
  "FG Starter" => "https://ecouter.lesindesradios.net/logos/orange236.png",
  "FIP" => "http://www.tv14.net/wp-content/uploads/2010/06/FIP-Radio.jpg",
  "FMC Radio" => "http://rad.io/images/broadcasts/4420_4.gif",
  "Flash FM" => "http://cdn-radiotime-logos.tunein.com/s8171q.png",
  "France Culture" => "https://upload.wikimedia.org/wikipedia/fr/thumb/c/c9/France_Culture_-_2008.svg/langfr-180px-France_Culture_-_2008.svg.png",
  "France Info" => "https://upload.wikimedia.org/wikipedia/commons/thumb/0/03/Franceinfo.svg/langfr-220px-Franceinfo.svg.png",
  "France Inter" => "https://upload.wikimedia.org/wikipedia/fr/thumb/8/8d/France_inter_2005_logo.svg/langfr-220px-France_inter_2005_logo.svg.png",
  "France Musique" => "https://upload.wikimedia.org/wikipedia/fr/thumb/2/22/France_Musique_-_2008.svg/180px-France_Musique_-_2008.svg.png",
  "France bleu Gascogne" => "http://static.radio.fr/images/broadcasts/73/f9/8373/c175.png",
  "France bleu loire ocean" => "http://static.radio.fr/images/broadcasts/42/d0/7908/c175.png",
  "Frequence 3" => "http://www.frequence3.fr/bundles/frequence3frontend/images/playerlive/pl-f3-logowfull.png",
  "Frequence Terre" => "https://www.frequenceterre.com/wp-content/uploads/2021/01/logo-freq-terre-home-trans-2021-500x200-3.png",
  "Fun Radio" => "https://upload.wikimedia.org/wikipedia/fr/archive/e/eb/20090829110847!Fun_Radio.png",
  "Generations" => "http://generations.fr/assets/logo.jpg",
  "Graffiti Urban Radio" => "http://a4.ec-images.myspacecdn.com/images02/152/5ce85b0e0be249e49d767ca1f43977d0/l.jpg",
  "Hit West" => "http://www.myconseils.fr/wp-content/uploads/2011/10/logo_hit_west.jpg",
  "Hot Mix Radio - 100% Hits" => "http://www.hotmixradio.fr/player/playerhtm/img/picto/new/hits.png",
  "Hot Mix Radio - 80" => "http://www.hotmixradio.fr/player/playerhtm/img/picto/new/80.png",
  "Hot Mix Radio - 90" => "http://www.hotmixradio.fr/player/playerhtm/img/picto/new/90s.png",
  "Hot Mix Radio - Funky" => "http://db.radioline.fr/pictures/radio_a2141f4e314c2b35baea57c6c66e258a/logo200.jpg",
  "Hot Mix Radio - Rock & Pop" => "http://www.allzicradio.com/media/radios/hotmix-rock-v1.png",
  "Jazz Radio" => "https://upload.wikimedia.org/wikipedia/en/4/40/Jazz_Radio_Logo.png",
  "Kif Radio" => "http://thc-fungames.e-mengine.com/archiver/www.jammin-unity.be/wp-content/uploads/2010/01/logo_kif_978.jpg",
  "Kiss FM" => "http://www.inspiringbirthstories.com.au/wp-content/uploads/2012/09/kiss_fm.gif",
  "La Grosse Radio" => "http://www.lagrosseradio.com/_images/logos/officiels/Logo_GrosseRadio_300dpi.png",
  "La Grosse Radio Metal" => "http://www.lagrosseradio.com/_images/haut/logo_metal.png",
  "La Grosse Radio Reggae" => "http://lagrosseradio.com/_images/logos/officiels/Logo_GrosseRadioReggae_300dpi.png",
  "La Grosse Radio Rock" => "http://www.lagrosseradio.com/_images/haut/logo_rock.png",
  "Le Mouv'" => "https://upload.wikimedia.org/wikipedia/fr/thumb/d/d3/Le_Mouv'_logo_2008.svg/1024px-Le_Mouv'_logo_2008.svg.png",
  "M2 Radio" => "http://www.m2radio.fr/images/logos/M/m2_radiofr_t.png",
  "M2 Radio - Analog" => "http://www.liveonlineradio.net/wp-content/uploads/2011/11/M2-ANALOG.png",
  "M2 Radio - Chillout" => "https://cdn.webrad.io/images/logos/ecouterradioenligne-com/m2-chillout.png",
  "M2 Radio - Love" => "https://static-media.streema.com/media/cache/84/52/845277544821fff93e4b9d63905f0d50.jpg",
  "M2 Radio - Mix" => "http://www.m2radio.fr/images/logos/M/m2_radiofr_t.png",
  "M2 Radio - Sunshine" => "https://www.radiozenders.fm/media/images/stations/m2-sunshine.png",
#  "M2 Radio - Vinyl" => "http://www.radio-en-direct.com/radios/m2-radio-vinyl/logo_m2_vinyl.png",
  "MFM" => "https://upload.wikimedia.org/wikipedia/fr/b/bb/Logo-mfm.png",
  "MFM 100% Enfoir�s" => "http://www.allzicradio.com/media/radios/100-enfoires-512px.png",
  "MFM Culte 60 70" => "http://i.img.co/radio/86/17/31786_290.png",
  "MFM Culte 80 90" => "http://mfmradio.fr/media/radios/culte-80-90-80px.png",
  "MFM Duos" => "http://i.img.co/radio/88/17/31788_90.png",
  "MFM Goldman" => "http://db.radioline.fr/pictures/radio_b93abbfa5e1455cfdf5f8eb2f8198600/logo200.jpg",
  "MFM G�n�ration Toesca" => "https://upload.wikimedia.org/wikipedia/fr/b/bb/Logo-mfm.png",
  "MFM Lady" => "http://db.radioline.fr/pictures/radio_d316adb73a913e471a69834064cead8f/logo200.jpg",
  "MFM Lovers" => "http://i.img.co/radio/91/17/31791_290.png",
  "Maxi 80" => "http://www.stormacq.com/wp-content/uploads/2010/06/maxi80-logo.jpg",
  "NRJ" => "http://www.24enfants.org/wp-content/uploads/2011/12/logo-NRJ1.jpg",
  "NRJ Lounge" => "http://i.img.co/radio/11/37/23711_290.png",
  "NTI" => "http://www.radionti.com/images/logo.gif",
  "Nostalgie" => "https://www.cheyenneprod.com/wp-content/uploads/2017/07/Nostalgie-logo-2015-CMJN.png",
  "Nostalgie Cin� tubes" => "http://i.img.co/radio/80/34/33480_290.png",
  "Nostalgie stars 80" => "http://i.img.co/radio/91/52/35291_290.png",
  "Oui FM" => "https://upload.wikimedia.org/wikipedia/fr/f/ff/OUI_FM_2014_logo.png",
  "Oui FM Alternatif" => "http://i.img.co/radio/97/89/8997_290.png",
  "Oui FM Blues" => "http://i.img.co/radio/22/70/27022_290.png",
  "Oui FM Collector" => "http://i.img.co/radio/96/89/8996_290.png",
  "Oui FM DJ Zebra" => "http://djzebra.free.fr/pix/badge_DJZebra_OUiFm.jpg",
  "Oui FM Ind�" => "http://www.ouifm.fr/wp-content/uploads/head/-1200x630.jpg",
  "Oxyradio" => "https://upload.wikimedia.org/wikipedia/commons/thumb/e/e1/Oxyradio-logo.svg/2000px-Oxyradio-logo.svg.png",
  "Paris One Club" => "http://www.paris-one.com/wp-content/uploads/2012/04/club_ico2.png",
  "Paris One Dance" => "http://a4.ec-images.myspacecdn.com/images01/20/b25af6a19a0b4d4e9d042b3c06e90d4d/m.png",
  "Paris One Deeper" => "http://static.radio.fr/images/broadcasts/4a/2d/1782/c175.png",
  "Paris One Reverse" => "http://a1.ec-images.myspacecdn.com/images02/85/0d41ecd21410432bb171063893cc391e/l.jpg",
  "Paris One Trance" => "http://gsmusic.free.fr/images/flytsparisone.jpg",
  "Prun" => "http://www.prun.net/im/design/logo.png",
  "Puls Radio" => "https://upload.wikimedia.org/wikipedia/commons/thumb/e/e7/BR_puls_Logo.svg/2000px-BR_puls_Logo.svg.png",
  "Puls Radio - Version 8.0" => "http://www.allzicradio.com/media/radios/puls8.jpg",
  "Puls Radio - Version 9.0" => "http://www.pulsradio.com/logo-90.png",
  "Puls Radio - Version Trance" => "https://www.pulsradio.com/TRANCE.png",
  "R'courchevel" => "http://i.img.co/radio/15/14/1415_290.png",
  "RBI FM" => "http://www.bluegrassmuseum.org/_assets/photos/rbi/RBI_logo_small.jpg",
  "RDM - Lorraine" => "https://i3.radionomy.com/radios/400/420e4457-00ee-4e1c-a223-303c9312de24.png",
  "RFI Monde" => "https://upload.wikimedia.org/wikipedia/commons/thumb/d/dd/RFI_logo_2013.svg/600px-RFI_logo_2013.svg.png",
  "RFM" => "http://static1.ozap.com/articles/4/42/13/24/%40/4261418-le-logo-de-la-radio-rfm-diapo-1.jpg",
  "RFM Night Fever" => "http://a2.ec-images.myspacecdn.com/images01/59/59b88d05e8dd0a0c72ac601003ab84e7/l.jpg",
  "RFM Pop Rock" => "https://resize-rfm.lanmedia.fr/r/67,,forcex/crop/67,67,center-middle,forcex,ffffff/img/var/rfm/storage/images/programmes/les-webradios/rfm-pop-rock/19370-1-fre-FR/RFM-Pop-Rock.png",
  "RFM 100% Fran�ais" => "https://resize2-rfm.lanmedia.fr/r/67,,forcex/crop/67,67,center-middle,forcex,ffffff/img/var/rfm/storage/images/programmes/les-webradios/100-francais/50811-7-fre-FR/100-Francais.png",
  "RFM 80's" => "https://resize2-rfm.lanmedia.fr/r/67,,forcex/crop/67,67,center-middle,forcex,ffffff/img/var/rfm/storage/images/programmes/les-webradios/rfm-80-s/3281-3-fre-FR/RFM-80-s.png",
  "RFM Collector" => "https://resize3-rfm.lanmedia.fr/r/67,,forcex/crop/67,67,center-middle,forcex,ffffff/img/var/rfm/storage/images/programmes/les-webradios/rfm-collector/3275-3-fre-FR/RFM-Collector.png",
  "RMC" => "https://upload.wikimedia.org/wikipedia/commons/thumb/8/81/Logo_RMC_2002.svg/1200px-Logo_RMC_2002.svg.png",
  "RST" => "http://www.vdc-nrw.com/userfiles/image/Logo_RadioRST.png",
  "RTL" => "https://upload.wikimedia.org/wikipedia/commons/thumb/e/ec/RTL-Radio-Letzebuerg-Logo.svg/1280px-RTL-Radio-Letzebuerg-Logo.svg.png",
  "RTL 2" => "http://static.rtl2.fr/versions/www/6.0.127/img/rtl2_fb.jpg",
  "Radio Bresse" => "http://www.radiobresse.com/wp-content/uploads/2015/12/logo-radio-bresse.png",
  "Radio Classique" => "https://upload.wikimedia.org/wikipedia/fr/2/20/Radio_Classique_logo_2014.png",
  "Radio C�te d'Amour" => "http://www.franck-gergaud.com/images_content/Radio_Cote_signature.jpg",
  "Radio Intensite" => "http://www.le28.com/images/bann/logo_intensite_v.gif",
  "Radio Junior" => "http://img.over-blog-kiwi.com/1/05/32/00/20150204/ob_bc0701_23158085logo-radio-junior-jpg.jpg",
  "Radio Latina" => "http://www.latina.fr/images/header/latina_premium.png",
  "Radio Pulsar" => "http://www.bestseller-consulting.com/images/Image/Image/Logos/radio-pulsar1.jpg",
  "Radio RDL" => "https://ecouter.lesindesradios.net/logos/orange83.png",
  "Radio TeenTall" => "http://1.bp.blogspot.com/-skx7uKgFTD8/ULssmGzHcOI/AAAAAAAAAm4/suGjz-QaXvQ/s1600/RADIO%252BTEENTALL.jpg",
  "RCA / Radio c�te d'amour (Nantes)" => "http://www.rcalaradio.com/upload/design/588a15bb4ef961.11113250.png",
  "SUD Radio" => "http://france3-regions.blog.francetvinfo.fr/medias-midi-pyrenees/wp-content/blogs.dir/363/files/2014/12/Sud-radio.jpg",
  "Sun" => "https://lesonunique.com/logo-sun-jaune.png",
  "Top Music" => "https://www.topmusic.fr/images/logo_topmusic.png",
  "Vibration" => "https://upload.wikimedia.org/wikipedia/en/d/d6/Vibration_logo.jpg",
  "Virgin Radio" => "http://www.virginradio.fr/default/modules/network/images/logo/white_full/virginradio.png",
  "Virgin Radio club" => "http://cdn-musique.ladmedia.fr/var/musiline/storage/images/virginradio/webradios/virgin-radio-club/567-10-fre-FR/Virgin-Radio-Club_webradio_198x198.jpg",
  "Virgin radio pop rock" => "http://cdn-musique.ladmedia.fr/var/musiline/storage/images/virginradio/webradios/virgin-radio-poprock/557-8-fre-FR/Virgin-Radio-PopRock_webradio_198x198.jpg",
  "Voltage" => "https://upload.wikimedia.org/wikipedia/fr/thumb/b/bb/Voltage_logo_2011.png/120px-Voltage_logo_2011.png",
  "WIT FM" => "https://upload.wikimedia.org/wikipedia/fr/f/fb/Wit.png",
  "Ze Radio" => "http://www.startrackcrush.com/wp-content/uploads/2012/08/logo-Zeradio.gif",
);

sub get_radio_pic {
	my ($name,$rpic) = @_;
    if ($name =~ /[\xc3\xc5]/) { # d�tection utf8 � 2 balles...
        # le source est en latin1, faut faire correspondre
        eval {
            Encode::from_to($name, "utf-8", "iso-8859-1");
        };
    }
	my $url = $icons{$name};
    if (!$url) {
        say "get_radio_pic: pas d'icone pour $name";
    }
	my $test = 0;
	if ($url) {
		my ($ext) = $url =~ /.+\.(.+)/;
#		print STDERR "channel name $name from $url\n";
		$name =~ s/[ \/]/_/g;
		$name = "radios/$name.$ext";
		print "name $name\n" if ($test);
		if (! -f $name || (-s $name == 0)) {
#			print STDERR "no channel logo, trying to get it from web\n";
			push @$rpic,($name,$url);
		}
	} else {
		$name = "";
	}
	$name;
}

sub get_icons {
	%icons;
}

mkdir "radios" if (!-d "radios");
1;

