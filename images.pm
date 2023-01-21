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

	for (my $n=0; $n<length($q); $n++) {
		if (ord(substr($q,$n,1)) < 64) {
			$q = substr($q,0,$n)."%".sprintf("%02x",ord(substr($q,$n,1))).substr($q,$n+1);
			$n += 2;
		}
	}
	say "images: q=$q";

	say "images: firefox...";
	my $c = http::myget("https://duckduckgo.com/?q=$q&t=h_");

	# avec duckduckgo, l'idée est de récupérer un champ généré pour
	# produire une requête json, ça a beaucoup d'avantages, ça devrait
	# survivre à tout changement de page quand les thèmes changent, et le
	# champ a l'air facile à récupérer, en haut d'une page de requête
	# simple...

	my ($vqd) = $c =~ /vqd='(.+?)'/;
	my ($backend) = $c =~ /BackendDeepUrl\("(.+?)"/;
	my ($nrj) = $c =~ /nrj\('(.+?)'/;
	# say "images: vqd = $vqd";
	# say "images: backend $backend";
	# say "images: nrj $nrj";
	# sleep(3);
#    $c = http::myget("https://links.duckduckgo.com$backend");
	# A priori le déclencheur doit être dans l'une de ces requêtes, il faut peut-être les 2, seul pb : le seul paramètre que je peux retrouver c'est q, la requête, certains autres sont très mystérieux !
	#http::myget("https://improving.duckduckgo.com/t/rq_0?8481373&r=1&tts=1&ac=0&rqv=1&q=$q&ttc=414299&ct=FR&d=d&kl=wt-wt&rl=us-en&kp=-1&serp_return=0&g=__&sm=wikipedia_fathead_deep:i:medium&blay=v1w2i1w26r1,e1w1&dsig=about:m&biaexp=b&deepsprts=b&eclsexp=b&msvrtexp=b");
	#http::myget("https://improving.duckduckgo.com/t/webvitals?3392533&FCP=1696&TTFB=263&FID=1&has_performance=1&is_cached=0&navigation_type=navigate&has_back_data=1&is_loaded_from_bfcache=0&is_bounce_back=0&g=__&sm=wikipedia_fathead_deep:i:medium&blay=v1w2i1w26r1,e1w1&dsig=about:m&biaexp=b&deepsprts=b&eclsexp=b&msvrtexp=b");
	#$c = http::myget("https://duckduckgo.com$nrj");
	#	open(F,">nrj");
	#	print F $c;
	#	close(F);
	#my ($load) = $c =~ /load_url":"(.+?)"/;
	#say "images: load $load";
	# $c = http::myget("$load");
	# Il y a visiblement un truc tordu autour de cette load url, la requête vue du naviageur vers y.js (même qu'ici) n'a pas du tout ces paramètres
	# donc je suppose qu'ils sont édités par la tonne de javascript qu'il y a autour... ! Ca renvoie des machins comme appid dans les paramètres et le truc
	# est tellement tordu que ça n'a même pas besoin d'être réutilisé ensuite, ça reste valable quelques secondes, donc si on commence par faire ce genre de requête sur
	# un navigateur et qu'on passe ici, ça marche, mais pas très longtemps... !
	#    la requête nrj renvoie exactement la même réponse que backend, donc totalement inutile.

	say "images: 1ere requête vqd=$vqd";
	$c = http::myget("https://duckduckgo.com/i.js?l=fr-fr&o=json&q=$q&vqd=$vqd&f=,,,,,&p=1");
	# la fameuse requête json qui renvoie tout, mais ça ne marche que si le machin a été validé par le fameux y.js ci-dessus (requête load), sinon ça renvoie un 403 (forbidden).
	# Pour l'instant seule méthode trouvée : faire la requête par un navigateur d'abord... ! Pas terrible ouais...

	if (!$c) {
		# Cas d'erruer on tente de boucler 1 fois...
		system("(midori \"https://duckduckgo.com/?q=$q&t=h_&iax=images&ia=images\" &); sleep 7; midori -e tab-close; killall midori; rm -f ~/.config/midori/tabby*");
		$c = http::myget("https://duckduckgo.com/?q=$q&t=h_");

		($vqd) = $c =~ /vqd='(.+?)'/;
		say "images: 2ème requête vqd=$vqd";
		$c = http::myget("https://duckduckgo.com/i.js?l=fr-fr&o=json&q=$q&vqd=$vqd&f=,,,,,&p=1");
	}

	if (!$c) {
		# Cas d'erruer on tente de boucler 1 fois...
		system("(midori \"https://duckduckgo.com/?q=$q&t=h_&iax=images&ia=images\" &); sleep 7; midori -e tab-close; killall midori; rm -f ~/.config/midori/tabby*");
		$c = http::myget("https://duckduckgo.com/?q=$q&t=h_");

		($vqd) = $c =~ /vqd='(.+?)'/;
		say "images: 3ème requête vqd=$vqd";
		$c = http::myget("https://duckduckgo.com/i.js?l=fr-fr&o=json&q=$q&vqd=$vqd&f=,,,,,&p=1");
	}
	# Décodage du js... !
	$c =~ s/^.+results"\:/{"results":/;
	$c =~ s/,"vqd.+/}/;
	my $json;
	eval {
		$json = decode_json($c);
	};
	if ($@) {
		say "images: $@ $!";
		open(F,">content");
		print F $c;
		close(F);
		say "images: content saved";
		return;
	}
	my $rtab = $json->{results};
	foreach (@$rtab) {
		my %args;
		($args{imgurl},$args{w},$args{h},$args{tbnid}) = ($_->{image},$_->{width},$_->{height},$_->{title});
		# tbnid est utilisé comme identifiant unique pour stocker dans le
		# cache, espaces interdits, et | aussi...
		$args{tbnid} =~ s/[ \'|\/]/_/g;

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
