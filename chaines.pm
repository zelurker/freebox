#!/usr/bin/perl
package chaines;

use strict;
use http;
use Cpanel::JSON::XS qw(decode_json);
use Data::Dumper;
use out;
use v5.10;
use Encode;
use progs::telerama;

our %chan;
our $latin = ($ENV{LANG} !~ /UTF/i);

sub conv_channel {
	my $channel = shift;
	# chaine pass�e -> chaine dans liste_chaines
	if ($channel =~ /[\xc3\xc5]/ && !$latin) {
		Encode::from_to($channel,"utf8","iso-8859-1");
	}
	my %corresp =
	(
		# Note : la plupart de ces conversions sont vieilles et je
		# soup�onne telerama d'avoir compl�tement chang� toute sa base,
		# donc il est fort possible que tout �a soit p�rim� !
		"NT1" => "NT 1",
		"France �" => "france �",
		"L'Equipe 21" => "L'Equipe",
		"Poker Channel" => "The Poker Channel",
		"RTL9" => "RTL 9",
		"Luxe.TV" => "Luxe TV",
		"IDF 1" => "IDF1",
		"TV5 Monde" => "TV5MONDE",
		"france o" => "France �",
		"NRJ12" => "NRJ 12",
		"LCP" => "La cha�ne parlementaire",
		"Onzeo" => "Onz�o",
		"TEVA" => "T�va",
		"Equidia live" => "Equidia",
		"Luxe.TV" => "Luxe TV",
		"telenantes" => "T�l�nantes",
		"NUMERO 23" => "Num�ro 23",
		"RMC DECOUVERTE" => "RMC D�couverte",
		"PARIS PREMIERE" => "PARIS Premi�re",
		"Science & Vie" => "Science & Vie TV",
		"TCM Cinema" => "TCM Cin�ma",
		"VH1 European" => "VH1",
		"Discovery" => "Discovery Channel",
		"Automoto tv" => "Automoto",
		"Sciences & Vie" => "Science & Vie TV",
		"L Equipe 21" => "L'Equipe",
		"Toute L Histoire" => "Toute L'histoire",
		"Chasse et peche" => "Chasse et P�che",
		"Cherie 25" => "Ch�rie 25",
		"MCM France" => "MCM",
		"Mezzo live" => "Mezzo",
		"Teletoon +1" => "T�l�toon+1",
		"Teletoon" => "T�l�toon+",
		"France Info tv" => "Franceinfo",
		"Nickelod�on 4 teen" => "Nickelod�on teen",
		"Plan�te+ A&E" => "Plan�te+ Aventure Exp�rience",
		"com�die" => "com�die+",
		"tf1 series" => "tf1 s�ries films",
		"numero 23" => "num�ro 23",
	);
	$channel =~ s/ \(hd\)//i;
	$channel =~ s/ fhd$//i;
	$channel =~ s/ (fr|ch|us|se|br)$//i;
	$channel =~ s/^cine\+? /cin�\+ /i;
	$channel =~ s/^brava stingray classica/stingray brava/i;
	$channel =~ s/^ab1/ab 1/i;
	$channel =~ s/^arte f /arte /i;
	$channel =~ s/^c star/cstar/i;
	$channel =~ s/^ocs geants?/ocs g�ants/i;
	$channel =~ s/^polar \+/polar+/i;
	$channel =~ s/^canal\+ decale/canal+ d�cal�/i;
	$channel =~ s/^canal\+ series/canal+ s�ries/i;
	$channel =~ s/^13 eme/13eme/i;
	$channel =~ s/^comedie/com�die/i;
	$channel =~ s/^serie club/serieclub/i;
	$channel =~ s/^tv breizh/tvbreizh/i;
	$channel =~ s/^tf1 series \&? ?/tf1 s�ries /i;
	$channel =~ s/^syfyfr/syfy/i;
	$channel =~ s/^canal\+ cinema/canal+ cin�ma/i;
	$channel =~ s/^planete \+/planete+/i;
	$channel =~ s/^planete c\.i\./planete+ ci/i;
	$channel =~ s/^National Geo( |$)/National Geographic$1/i;
	$channel =~ s/^Nat Geo( |$)/National Geographic$1/i;
	$channel =~ s/^ushuaia/ushua�a/i;
	$channel =~ s/^Nickelodeon/Nickelod�on/i;
	$channel =~ s/^Nick Jr\.?/Nickelodeon junior/i;
	$channel =~ s/^Planete\+ CI/Plan�te\+ Crime investigation/i;
	$channel =~ s/^Planete/Plan�te/i;
	$channel =~ s/ low$//i;
	$channel =~ s/ ?hd$//i;
	$channel =~ s/ sd$//i;
	$channel =~ s/ sat$//i;
	$channel =~ s/^T�l�nantes //;
	$channel =~ s/ *$//;
	$channel = lc($channel);
	foreach (keys %corresp) {
		if (lc($_) eq $channel) {
			return  lc($corresp{$_});
		}
	}
	return lc($channel);
}

sub get_browser {
	# En fait l'agent telerama n'est plus utile, mais bon c'est pas
	# interdit non plus...
	my $useragt = 'Telerama/1.0 CFNetwork/445.6 Darwin/10.0.0d3';
	my $browser = LWP::UserAgent->new(keep_alive => 0,
		agent =>$useragt);
    $browser->timeout(20);
	$browser;
}

sub setup_image {
	# Renvoie un nom de fichier � partir du num�ro de chaine
	# (celui contenu dans liste_chaines renvoy� par t�l�rama).
	# normalement appel� par get_chan_pic
	my ($num,$rpic) = @_;
	my $url;
	# de l'int�rieur de chaines.pm on l'appelle en passant directement
	# l'url mais de l'ext�rieur c'est l'ancienne m�thode : par num�ro !
	if ($num =~ /[a-z]/) {
		$url = $num;
	} else {
		foreach (keys %chan) {
			if ($chan{$_}[0] == $num) {
				$url = $chan{$_}[1];
				last;
			}
		}
	}

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
		print STDERR "$url error: ",$response->status_line,"\n";
		return ($response->status_line,undef);
	}
	if ($response->header("x-died")) {
		print STDERR "x-died: ",$response->header("x-died"),"\n";
		return ($response->status_line,undef);
	}

	# Renvoie le type d'abord pour qu'en contexte scalar on obtienne la r�ponse
    return ($response->header("Content-type"),$response->content);
}

sub getListeChaines($) {
	my $net = shift;
	my $r;
	my $server = "https://api.telerama.fr";
	my $url = "/v1/application/initialisation";
	$url .= "?appareil=android_tablette";
	$url .= "&api_signature=".progs::telerama::myhash($url)."&api_cle=apitel-5304b49c90511";
	$r = http::myget("$server$url","liste_chaines",30);
	my $json;
	eval {
		$json = decode_json($r);
	};
	if ($@) {
		print "chaines: decode_json error $! � partir de $r\n";
		return undef;
	}
	my %ordre = ();
	my $num = 1;
	# alors bizarrement telerama fournit la liste des chaines tnt, mais pas
	# tout � fait dans l'ordre !!!
	# m6 & arte sont invers�es, tmc & france 4 aussi !
	# Du coup je recopie leur liste retouch�e ici, je suppose que les ids
	# des chaines ne changent jamais contrairement aux noms !
	my @tnt = (
               192,
               4,
               80,
               34,
               47,
               118,
               111,
               445,
               119,
               195,
               446,
               444,
               234,
               78,
               481,
               226,
               458,
               482,
               160,
               1404,
               1401,
               1403,
               1402,
               1400,
               1399,
               112,
               2111
		   );
	foreach (@tnt) {
		$ordre{$_} = $num++;
	}
	foreach (@{$json->{donnees}->{chaines}}) {
		$chan{lc($_->{nom})} = [$_->{id},$_->{logo},$_->{nom},$ordre{$_->{id}}];
	}
	$chan{"hbo (east)"} = [1500,"https://www.directhd.tv/wp-content/uploads/channels/200x200/logo_hbo_east_small.gif","HBO (East)"];
	$chan{"hbo (west)"} = [1501,"http://static.ontvtonight.com/static/2/Open/SourceLogos/Cleared%20Logos/HBO/HBO%20WEST.jpg","HBO (West)"];
	$chan{"hbo 2 (west)"} = [1502,"https://upload.wikimedia.org/wikipedia/commons/d/de/Hbo_2.png","HBO 2 (West)"];
	$chan{"hbo 2 (east)"} = [1503,"https://upload.wikimedia.org/wikipedia/commons/d/de/Hbo_2.png","HBO 2 (East)"];
	$chan{"hbo comedy (east)"} = [1504,"https://cdn.tvpassport.com/image/station/240x135/hbo-comedy.png","HBO Comedy (East)"];
	$chan{"hbo family (east)"} = [1505,"https://cdn.tvpassport.com/image/station/240x135/hbo-family.png","HBO Family (East)"];
	$chan{"hbo signature (east)"} = [1506,"https://cdn.tvpassport.com/image/station/240x135/hbo-signature.png","HBO Signature (East)"];
	$chan{"hbo zone (east)"} = [1507,"https://cdn.tvpassport.com/image/station/240x135/hbo-zone.png","HBO Zone (East)"];
	$chan{"hbo 1 ca"} = [1508,"https://cdn.tvpassport.com/image/station/240x135/hbo.png","HBO 1 Ca"];
	$chan{"hbo 2 (east) ca"} = [1509,"https://cdn.tvpassport.com/image/station/240x135/hbo2.png","HBO 2 (East) Ca"];
	return \%chan;
}

sub get_chan_pic {
	my ($name,$rpic) = @_;
#	if ($name =~ /^Nolife/) {
#		return setup_image(1500);
#	}
	if (!%chan) {
		getListeChaines(out::have_net());
	}
	$name = conv_channel($name);
	return setup_image($chan{$name}[1],$rpic);
}

1;
