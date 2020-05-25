#!/usr/bin/env perl

package images;

use Coro::LWP;
use WWW::Mechanize;
use Encode;
use MIME::Base64;
use strict;

our $debug = 0;

sub search {
	my ($self,$q) = @_;
	my $mech;
	my @tab = ();
	do {
		eval {
			$mech = WWW::Mechanize->new();
			# $mech->agent_alias("Linux Mozilla");
			# Qui l'eut cru ? Les pages sont générées à partir du user agent, je
			# croyais que plus personne ne faisait ça ou presque, et bin si, la preuve!
			# Si on envoie un agent récent, on obtient la version javascript de frime
			# avec toutes les infos dedans !!! :))))
			$mech->agent("Mozilla/5.0 (X11; Linux x86_64; rv:45.0) Gecko/20100101 Firefox/45.0");
			$mech->timeout(10);
			$mech->default_header('Accept-Encoding' => scalar HTTP::Message::decodable());

# $mech->get("https://www.google.fr/search?hl=fr&site=imghp&tbm=isch&source=hp&biw=1240&bih=502&q=chien");
# my $pwd = `pwd`;
# chomp $pwd;
# $mech->get("file://$pwd/final.html");
			$mech->get("https://www.google.fr/imghp");
		};
		if ($@) {
			print "*** images.pm: got error $@\n";
		}
	} while ($@);
	# Alors le nouveau google images semble mettre à jour ses pages par une
	# url liée au scrolling et j'ai pas trouvé encore comment il la génère.
	# Donc le + simple c'est de demander des données sur une hauteur
	# ridiculement grande (ici 7220 !), comme ça on fait le plein en 1
	# seule fois !
	eval {
		$mech->submit_form(
			form_number => 1,
			fields      => {
				site => "imghp",
				q => $q,
				biw => 1337,
				bih => 7220,
			}
		);
	};
	if ($@) {
		print "*** images.pm: got error submit_form $@\n";
		return undef;
	}

	$self->{mech} = $mech;

	# Décodage du js... !
	my $c = $mech->content;
	$mech->save_content("page_images.html");
	my @vignette = ();
	my $saved = undef;
	# ok, c le nouveau remake de google images, 2019 ou 2020, il m'a fallu
	# un sacré bout de temps pour réagir, donc à priori, chaque image
	# commence par [1,[0, puis l'id, puis un tableau qui a l'air de contenir des infos
	# pour la version réduite, puis ce qui nous intéresse : [url, width,
	# height]. J'ai pas compris ce que veulent dire tous les champs, mais
	# j'ai les principaux... !
	while ($c =~ s/\[1,\[0,"(.+?)",\[.+?\]\n?,\[(.+?)\]//) {
		my %args;
		$args{tbnid} = $1;
		($args{imgurl},$args{w},$args{h}) = split(/,/,$2);
		$args{imgurl} =~ s/"//g;

		push @tab,\%args; # on garde tout, pourquoi se priver ?!!!

	}
	$self->{tab} = \@tab;
	\@vignette;
}

sub new {
	my $self  = shift;
	my $class = ref($self) || $self;
	return bless {
	 tab => (),
	}, $class;
}

1;
