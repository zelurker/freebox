#!/usr/bin/env perl

package images;

use Coro::LWP;
use Cpanel::JSON::XS qw(decode_json);
use common::sense;
use http;

our $debug = 0;

sub search {
	my ($self,$q) = @_;
	my @tab = ();

	$q =~ s/ /\+/g;
	say "images: $q";
	for (my $n=0; $n<length($q); $n++) {
		print sprintf("%02x ",ord(substr($q,$n,1)));
	}
	say "";
	my $c = http::myget("https://duckduckgo.com/?t=ffsb&q=$q&ia=web");

	# avec duckduckgo, l'idée est de récupérer un champ généré pour
	# produire une requête json, ça a beaucoup d'avantages, ça devrait
	# survivre à tout changement de page quand les thèmes changent, et le
	# champ a l'air facile à récupérer, en haut d'une page de requête
	# simple...

	my ($vqd) = $c =~ /vqd='(.+?)'/;

	$c = http::myget("https://duckduckgo.com/i.js?l=fr-fr&o=json&q=$q&vqd=$vqd&f=,,,,,&p=1");

	# Décodage du js... !
	$c =~ s/^.+results"\:/{"results":/;
	$c =~ s/,"vqd.+/}/;
	my $json = decode_json($c);
	my $rtab = $json->{results};
	foreach (@$rtab) {
		my %args;
		($args{imgurl},$args{w},$args{h},$args{tbnid}) = ($_->{image},$_->{width},$_->{height},$_->{title});
		# tbnid est utilisé comme identifiant unique pour stocker dans le
		# cache, espaces interdits, et | aussi...
		$args{tbnid} =~ s/[ |\/]/_/g;

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
