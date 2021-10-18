#!/usr/bin/env perl

package images;

use Coro::LWP;
use WWW::Mechanize;
use Cpanel::JSON::XS qw(decode_json);
use common::sense;

our $debug = 0;

sub search {
	my ($self,$q) = @_;
	my $mech;
	my @tab = ();
	$mech = WWW::Mechanize->new();
	$mech->agent("Mozilla/5.0 (X11; Linux x86_64; rv:45.0) Gecko/20100101 Firefox/45.0");
	$mech->timeout(10);
	$mech->default_header('Accept-Encoding' => scalar HTTP::Message::decodable());

	$q =~ s/ /\+/g;
	$mech->get("https://duckduckgo.com/?t=ffsb&q=$q&ia=web");

	# avec duckduckgo, l'idée est de récupérer un champ généré pour
	# produire une requête json, ça a beaucoup d'avantages, ça devrait
	# survivre à tout changement de page quand les thèmes changent, et le
	# champ a l'air facile à récupérer, en haut d'une page de requête
	# simple...

	my $c = $mech->content;
	my ($vqd) = $c =~ /vqd='(.+?)'/;

	$mech->get("https://duckduckgo.com/i.js?l=fr-fr&o=json&q=$q&vqd=$vqd&f=,,,,,&p=1");
	$self->{mech} = $mech;

	# Décodage du js... !
	my $c = $mech->content;
	# $mech->save_content("page_images.html");
	$c =~ s/^.+results"\:/{"results":/;
	$c =~ s/,"vqd.+/}/;
	my $json = decode_json($c);
	my $rtab = $json->{results};
	foreach (@$rtab) {
		my %args;
		($args{imgurl},$args{w},$args{h},$args{tbnid}) = ($_->{image},$_->{width},$_->{height},$_->{title});
		$args{tbnid} =~ s/ /_/g; # utilisé en argument de la commande image, espaces interdits !

		push @tab,\%args; # on garde tout, pourquoi se priver ?!!!

	}
	$self->{tab} = \@tab;
}

sub new {
	my $self  = shift;
	my $class = ref($self) || $self;
	return bless {
	 tab => (),
	}, $class;
}

1;
