package myutf;

# un mydecode universel qui décode en fonction de la locale
# détecte ce qu'on lui passe et ré-encode selon la locale quoi
# attention référence en paramètre

use Encode;
use strict;
use v5.10;

our $latin = ($ENV{LANG} !~ /UTF/i);

sub mydecode {
	my $ref = shift;
	$$ref =~ s/\x{2019}/'/g;
	$$ref =~ s/\x{0153}/oe/g;
	# Ok, on va chercher l'encodage de la chaine puisqu'on ne peut
	# faire confiance à is_utf8. L'idée c'est de se fier aux codes
	# ascii, on cherche le maxi dans la chaine.
	# Si il est < 128 alors c'est de l'ascii standard, pas besoin
	# d'encodage
	# Si c'est < 256 alors c'est du latin1
	# Si c'est > 256 alors c'est de l'utf8 (j'espère !)
	my $max_ord = 0;
	for (my $n=0; $n<length($$ref); $n++) {
		$max_ord = ord(substr($$ref,$n,1)) if (ord(substr($$ref,$n,1)) > $max_ord);
	}
	return if ($max_ord < 128);
	if (!$latin) {
		# test utf8 d'après la page wikipedia https://fr.wikipedia.org/wiki/UTF-8
		# problème : en latin1 e9 est le é, si il n'y a que ça, on ne peut
		# pas faire la différence ! Du coup on est obligé d'éliminer des
		# codes : e7 (ç) e8 (è) e9 (é) ea (ê) ef (ï) ee (î) e2 (â)
		# Ce qui fait que ça reste boiteux, mais ça devrait suffire... !
		# (on retire les préfixes qui peuvent être suivis par n'importe
		# quoi et qui correspondent à des codes courants en latin1)
		# 1ère collision frontale, e2 en latin1 ça fait donc à
		# mais e2 80 9c en utf ça fait guillemet ouverte... !
		# Au passage c'est 6 " avec la touche de composition : “
		return if ($$ref =~ /\xe2\x80\x9c/);
		if ($$ref =~ /([\xc2-\xdf\xe1\xe3-\xe6\xeb-\xec\xf1-\xf3])|(\xe0[\xa0-\xbf])|(\xed[\x80-\x9f])|(\xf0[\x90-\xbf])|(\xf4[\x80-\x8f])/ || $max_ord > 255) {
			# print "to_utf: reçu un truc en utf: $$ref max_ord $max_ord\n";
			return;
		}
		eval {
			Encode::from_to($$ref,"iso-8859-15","utf8");
		};
		if ($@) {
			print "to_utf: error encoding $$ref: $!, $@\n";
		}
	} elsif ($$ref =~ /[\xc3\xc5]/ || $max_ord > 255) {
		utf8::encode($$ref) if ($max_ord > 255);
		eval {
			Encode::from_to($$ref,"utf8","iso-8859-15");
		};
		if ($@) {
			print "to_utf: error encoding $$ref: $!, $@\n";
		}
	}
}

1;
