#!/usr/bin/perl
package chaines;

use strict;
require "http.pl";
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
		"AB 1" => "AB1",
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
	);
	$channel =~ s/ \(.+\)//;
	$channel =~ s/ ?hd$//i;
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
	$r = myget("$server$url","liste_chaines",30);
	my $json;
	eval {
		$json = decode_json($r);
	};
	if ($@) {
		print "chaines: decode_json error $! � partir de $r\n";
		return undef;
	}
	foreach (@{$json->{donnees}->{chaines}}) {
		# say $_->{id}," ",$_->{nom};
		$chan{lc($_->{nom})} = [$_->{id},$_->{logo},$_->{nom}];
	}
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
