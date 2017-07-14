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
			# Qui l'eut cru ? Les pages sont g�n�r�es � partir du user agent, je
			# croyais que plus personne ne faisait �a ou presque, et bin si, la preuve!
			# Si on envoie un agent r�cent, on obtient la version javascript de frime
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
	# Alors le nouveau google images semble mettre � jour ses pages par une
	# url li�e au scrolling et j'ai pas trouv� encore comment il la g�n�re.
	# Donc le + simple c'est de demander des donn�es sur une hauteur
	# ridiculement grande (ici 7220 !), comme �a on fait le plein en 1
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

	# D�codage du js... !
	my $c = $mech->content;
	$mech->save_content("page_images.html");
	my @vignette = ();
	my $saved = undef;
	# Nouveau google images 2017 : plut�t bizarre, les tags de l'image sont
	# contenus en json dans l'html puis apparemment convertis en html apr�s
	# chargement. Vu qu'on execute pas de javascript ici, on doit se taper
	# le json � la main, �a reste tr�s simple, en esp�rant que �a change
	# pas trop dans l'avenir quoi... !
	my %corresp = ( # correspondances nouveaux tags -> anciens
		ow => "w",
		oh => "h",
		ou => "imgurl",
		id => "tbnid"
	);
	while ($c =~ s/<div class="rg_meta.+?">\{(.+?)\}//) {
		my $tags = $1;
		my @tags = split(/,/,$tags);
		my %args;
		foreach (@tags) {
			my ($var,$val) = /(.+?):(.+)/;
			$var =~ s/"//g;
			$val =~ s/"//g;
			$val =~ s/:$// if ($var eq "id");
			$var = $corresp{$var} if ($corresp{$var});
			$args{$var} = $val;
		}

		push @tab,\%args; # on garde tout, pourquoi se priver ?!!!

#		# Pour l'instant j'ai pas les vignettes, y a l'id dans le code,
#		mais bizarrement je vois pas o� est la correspondance !
#		Je garde quand m�me le code parce que c'�tait assez h�ro�que de
#		faire le d�codage dans l'html, �a peut �ventuellement re-servir un
#		de ces jours...
#		if ($c =~ s/e\.src='([^']+?)';}}\)\(document.getElementsByName\('$args{tbnid}//){
#			my $b64 = $1;
#			my $name;
#			if ($b64 =~ /^data:image\/jpeg/) {
#				$name = "cache/vn_$args{tbnid}.jpg";
#				$name =~ s/://;
#			} else {
#				print "base64: file type not recognized : ",substr($b64,0,16),"\n";
#				next;
#			}
#			if (!-f $name) {
#				if (open(F,">$name")) {
#					$b64 =~ s/^.+?base64,//;
#					print F decode_base64($b64);
#					close(F);
#				}
#			} else {
#				utime(undef,undef,$name);
#			}
#			push @vignette,$name;
#		}
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
