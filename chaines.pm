#!/usr/bin/perl
package chaines;

use strict;
use LWP 5.64;

use out;

# Icones des chaines, merci google
# Le numéro est le numéro récupéré dans liste_chaines
our %icons = (
	1 => "http://upload.wikimedia.org/wikipedia/fr/thumb/6/60/Logo_TF1.svg/421px-Logo_TF1.svg.png",
	2 => "http://upload.wikimedia.org/wikipedia/fr/thumb/0/02/Logo_France_2.svg/80px-Logo_France_2.svg.png",
	3 => "http://upload.wikimedia.org/wikipedia/fr/thumb/5/5f/Logo_France_3.svg/80px-Logo_France_3.svg.png",
	4 => "http://upload.wikimedia.org/wikipedia/commons/thumb/1/1a/Canal%2B.svg/500px-Canal%2B.svg.png",
	5 => "http://upload.wikimedia.org/wikipedia/fr/thumb/a/a2/France5.svg/71px-France5.svg.png",
	6 => "http://upload.wikimedia.org/wikipedia/fr/thumb/2/26/Logo-M6.svg/120px-Logo-M6.svg.png",
	7 => "http://upload.wikimedia.org/wikipedia/fr/thumb/7/7e/ARTE_logo_1989.png/120px-ARTE_logo_1989.png",
	8 => "http://upload.wikimedia.org/wikipedia/fr/thumb/b/b8/Direct8-2010.svg/800px-Direct8-2010.svg.png",
	9 => "http://upload.wikimedia.org/wikipedia/fr/8/86/W9_2010.png",
	10 => "http://upload.wikimedia.org/wikipedia/fr/thumb/2/2e/TMC_new.svg/218px-TMC_new.svg.png",
	11 => "http://upload.wikimedia.org/wikipedia/fr/b/bc/NT1_logo2008.png",
	12 => "http://upload.wikimedia.org/wikipedia/fr/e/ea/NRJ12.png",
	13 => "http://upload.wikimedia.org/wikipedia/fr/thumb/0/0c/Logo_France_4.svg/346px-Logo_France_4.svg.png",
	14 => "http://upload.wikimedia.org/wikipedia/en/thumb/a/a8/LCP-Public_Senat.png/200px-LCP-Public_Senat.png",
	15 => "http://upload.wikimedia.org/wikipedia/fr/thumb/d/d4/BFM_TV_2004.jpg/120px-BFM_TV_2004.jpg",
	16 => "http://upload.wikimedia.org/wikipedia/fr/thumb/6/6e/I-tele_2008_logo.svg/78px-I-tele_2008_logo.svg.png",
	17 => "http://upload.wikimedia.org/wikipedia/fr/thumb/a/a9/D17_%282012-%29.png/593px-D17_%282012-%29.png",
	18 => "http://upload.wikimedia.org/wikipedia/en/thumb/a/a1/Gulli_Logo.png/200px-Gulli_Logo.png",
	20 => "http://upload.wikimedia.org/wikipedia/fr/thumb/6/6c/13eme_rue_Universal.svg/100px-13eme_rue_Universal.svg.png",
	23 => "http://upload.wikimedia.org/wikipedia/commons/8/8f/Logo_AB1_2011.gif",
	26 => "http://upload.wikimedia.org/wikipedia/fr/7/7e/ACTION_1996.gif",
	27 => "http://upload.wikimedia.org/wikipedia/fr/thumb/3/39/AB_Moteurs_logo.svg/545px-AB_Moteurs_logo.svg.png",
	29 => "http://upload.wikimedia.org/wikipedia/fr/5/59/ANIMAUX_1998_BIG.gif",
	70 => "http://upload.wikimedia.org/wikipedia/fr/thumb/2/26/Demain_TV_logo_2011.png/200px-Demain_TV_logo_2011.png",
	83 => "http://upload.wikimedia.org/wikipedia/fr/thumb/3/33/%C3%89quidia_Logo.svg/513px-%C3%89quidia_Logo.svg.png",
	84 => "http://upload.wikimedia.org/wikipedia/fr/thumb/c/c2/ESCALES_2003.jpg/120px-ESCALES_2003.jpg",
	87 => "http://upload.wikimedia.org/wikipedia/fr/thumb/d/d5/Euronews_logo_2008.svg/120px-Euronews_logo_2008.svg.png",
	89 => "http://upload.wikimedia.org/wikipedia/fr/thumb/c/cb/Eurosport_logo_2011.svg/180px-Eurosport_logo_2011.svg.png",
	119 => "http://upload.wikimedia.org/wikipedia/fr/thumb/8/8a/France_%C3%94_logo_2008.svg/347px-France_%C3%94_logo_2008.svg.png",
	120 => "http://upload.wikimedia.org/wikipedia/fr/6/6e/Funtv.gif",
	121 => "http://upload.wikimedia.org/wikipedia/fr/thumb/4/41/Logo_Game_One_2006.svg/735px-Logo_Game_One_2006.svg.png",
	135 => "http://upload.wikimedia.org/wikipedia/fr/thumb/a/a5/Liberty_TV_Logo.png/220px-Liberty_TV_Logo.png",
	142 => "http://upload.wikimedia.org/wikipedia/fr/4/46/Mangas_Logo.png",
	166 => "http://upload.wikimedia.org/wikipedia/fr/8/84/Nantes7.gif",
	173 => "http://upload.wikimedia.org/wikipedia/fr/0/0c/Logo_NRJ_Hits.jpg",
	174 => "http://upload.wikimedia.org/wikipedia/fr/a/ac/Logo_NRJ_Paris.gif",
	186 => "http://upload.wikimedia.org/wikipedia/fr/thumb/0/0b/Paris_premi%C3%A8re_1997_logo.svg/150px-Paris_premi%C3%A8re_1997_logo.svg.png",
	199 => "http://upload.wikimedia.org/wikipedia/fr/thumb/9/9a/RTL9logo.png/120px-RTL9logo.png",
	206 => "http://upload.wikimedia.org/wikipedia/fr/thumb/d/dc/Tcm.jpg/150px-Tcm.jpg",
	230 => "http://upload.wikimedia.org/wikipedia/fr/thumb/0/04/Poker_Channel_Logo.png/300px-Poker_Channel_Logo.png",
	237 => "http://upload.wikimedia.org/wikipedia/fr/thumb/3/3d/TV5Monde_Logo.svg/300px-TV5Monde_Logo.svg.png",
	245 => "http://upload.wikimedia.org/wikipedia/fr/c/c1/Logo_TV_Tours.gif",
	259 => "http://upload.wikimedia.org/wikipedia/en/thumb/9/95/Luxe_TV.png/200px-Luxe_TV.png",
	268 => "http://upload.wikimedia.org/wikipedia/fr/thumb/c/c7/Fashion_TV_Logo.png/300px-Fashion_TV_Logo.png",
	288 => "http://upload.wikimedia.org/wikipedia/fr/thumb/c/ce/FRANCE24.svg/100px-FRANCE24.svg.png",
	294 => "http://upload.wikimedia.org/wikipedia/fr/thumb/6/67/IDF1.png/100px-IDF1.png",
	4131 => "http://img.over-blog.com/550x300/1/59/49/25/TF1/HD1/HD1-logo.jpg",
	4132 => "http://www.mytivi.fr/wp-content/uploads/2012/12/l%C3%A9quipe-21.jpg",
	4133 => "http://thumb.info2tele.com/wp-content/uploads//2012/11/20121115-logo-6ter-info2tele.jpg",
	4134 => "http://upload.wikimedia.org/wikipedia/fr/archive/f/fe/20121119164338!Num%C3%A9ro_23_logo.png",
	4135 => "http://upload.wikimedia.org/wikipedia/fr/e/ed/RMC_D%C3%A9couverte_logo_2012.png",
	4136 => "https://upload.wikimedia.org/wikipedia/fr/thumb/1/1f/Ch%C3%A9rie_25_logo.svg/605px-Ch%C3%A9rie_25_logo.svg.png",
	1500 => "http://upload.wikimedia.org/wikipedia/fr/thumb/3/3f/Logo_nolife.svg/208px-Logo_nolife.svg.png",
);

our %chan;

sub conv_channel {
	my $channel = shift;
	my %corresp =
	(
		"Poker Channel" => "The Poker Channel",
		"RTL9" => "RTL 9",
		"Luxe.TV" => "Luxe TV",
		"AB 1" => "AB1",
		"IDF 1" => "IDF1",
		"i>TELE" => "iTélé",
		"i> TELE" => "iTélé",
		"TV5 Monde" => "TV5MONDE",
		"France ô" => "France Ô",
		"france o" => "France Ô",
		"Télénantes Nantes 7" => "Nantes 7",
		"NRJ12" => "NRJ 12",
		"LCP" => "La chaîne parlementaire",
		"Onzeo" => "Onzéo",
		"TEVA" => "Téva",
		"Equidia live" => "Equidia",
		"Luxe.TV" => "Luxe TV",
		"D8" => "Direct 8",
		"telenantes" => "Télé Nantes",
		"NUMERO 23" => "Numéro 23",
		"RMC DECOUVERTE" => "RMC Découverte",
	);
	$channel =~ s/ \(.+\)//;
	$channel =~ s/ ?hd$//i;
	$channel =~ s/ sat$//i;
	$channel =~ s/^Télénantes //;
	$channel =~ s/ *$//;
	$channel = lc($channel);
	foreach (keys %corresp) {
		if (lc($_) eq $channel) {
			return  lc($corresp{$_});
		}
	}
	return lc($channel);
}

# Cette fonction est uniquement pour pouvoir vérifier les urls
# pour le script check_channels
sub get_icons() { %icons }

sub get_browser {
	my $useragt = 'Telerama/1.0 CFNetwork/445.6 Darwin/10.0.0d3';
	my $browser = LWP::UserAgent->new(keep_alive => 0,
		agent =>$useragt);
	$browser;
}

sub setup_image {
	# Renvoie un nom de fichier à partir du numéro de chaine
	# (celui contenu dans liste_chaines renvoyé par télérama).
	my ($field,$rpic) = @_;
	my $url = $icons{$field};
	my $name = "";
	if ($url) {
		($name) = $url =~ /.+\/(.+)/;
#		print STDERR "channel name $name from $url\n";
		$name = "chaines/$name";
		if (! -f $name || -z $name) {
#			print STDERR "no channel logo, trying to get it from web\n";
			push @$rpic,($name,$url);
		}
	}
	$name;
}

sub request {
    my $url = shift;
	my $browser = get_browser();
    my $response = $browser->get($url);

	if (!$response->is_success) {
		print "$url error: ",$response->status_line,"\n";
		return ($response->status_line,undef);
	}

	# Renvoie le type d'abord pour qu'en contexte scalar on obtienne la réponse
    return ($response->header("Content-type"),$response->content);
}

sub getListeChaines($) {
	my $net = shift;
	my $r = undef;
	my $tries = 1;
	my @chan;
	do {
		if (!-f "liste_chaines" || -M "liste_chaines" > 30 || -s "liste_chaines" < 512) {
			return "" if (!$net);
			print "geting liste_chaines from web...\n";
			my $site_addr = "guidetv-iphone.telerama.fr";
			my $site_prefix = "http://$site_addr/verytv/procedures/";
			my $url = $site_prefix."ListeChaines.php";

			# Ce truc est un peu particulier
			# comme la requète impose d'avoir un useragent iphone et que je ne veux
			# pas ramener
			$r = request($url);
			if ($r) {
				if (open(F,">liste_chaines")) {
					print F $r;
					close(F);
				} else {
					print "can't create liste_chaines\n";
				}
			} else {
				print "getlistechaines: pas de contenu\n";
			}
		}
		if (!$r) {
			print "using cache for liste_chaines\n";
			if (open(F,"<liste_chaines")) {
				while (<F>) {
					$r .= $_;
				}
				close(F);
			} else {
				print "can't read liste_chaines\n";
			}
		}
		@chan = split(/\:\$\$\$\:/,lc($r));
		if ($#chan <= 0) {
			unlink "liste_chaines";
		}
	} while ($tries++ < 2 && $#chan <= 0);
	foreach (@chan) {
		my ($num,$name) = split /\$\$\$/;
		if ($name) {
			$chan{$name} = $num;
		}
	}
	return lc($r);
}

sub get_chan_pic {
	my ($name,$rpic) = @_;
	if ($name =~ /^Nolife/) {
		return setup_image(1500);
	}
	if (!%chan) {
		getListeChaines(out::have_net());
	}
	$name = conv_channel($name);
	return setup_image($chan{$name},$rpic);
}

1;
