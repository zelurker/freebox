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
	# Bon on a un sérieux problème avec une variation du -
	# quand on est un utf8 il est encodé par e2 80 93
	# mais quand on est en latin, vu qu'il n'y a pas de code pour ce truc,
	# il est encodé par \x2013 !!!
	# Evidemment une chaine contenant ce code ne peut être convertie de
	# latin1 en utf8, tu m'étonnes
	# donc on va forcer le remplacement de cet e2 80 93 par -
	# et faire pareil pour le \x2013
	$$ref =~ s/\xe2\x80\x93/-/g;
	for (my $n=0; $n<length($$ref); $n++) {
		my $o = ord(substr($$ref,$n,1));
		if ($o == 0x2013) {
			$$ref = substr($$ref,0,$n)."-".substr($$ref,$n+1);
			next;
		}
		$max_ord = $o if ($o > $max_ord);
	}
	return if ($max_ord < 128);
	if (!$latin) {
		# test utf8 d'après la page wikipedia https://fr.wikipedia.org/wiki/UTF-8
		# problème : en latin1 e9 est le é, si il n'y a que ça, on ne peut
		# pas faire la différence ! Du coup on est obligé d'éliminer des
		# codes : c7 (Ç) c9 (É) ce (î) e2 (â) e7 (ç) e8 (è) e9 (é) ea (ê) eb (ë) ee (î) ef (ï)
		# Ce qui fait que ça reste boiteux, mais ça devrait suffire... !
		# (on retire les préfixes qui peuvent être suivis par n'importe
		# quoi et qui correspondent à des codes courants en latin1)
		# 1ère collision frontale, e2 en latin1 ça fait donc à
		# mais e2 80 9c en utf ça fait guillemet ouverte... !
		# Au passage c'est 6 " avec la touche de composition : “
		# et e2 82 ac c'est l'euro €
		return if ($$ref =~ /(\xe2\x80\x9c|\xe2\x82\xac)/);
		# je garde la boucle commentée pour d'autre débugage éventuel, ça
		# évite de tout retaper à chaque fois !
#		if ($$ref =~ /Best of Plastic/) {
#			for (my $n=0; $n<length($$ref); $n++) {
#				print substr($$ref,$n,1)," ",sprintf("%02x ",ord(substr($$ref,$n)));
#			}
#			print "\n";
#		}
		if ($$ref =~ /([\xc2-\xc6\xc8\xca-\xcd\xcf-\xdf\xe1\xe3-\xe6\xec-\xec\xf1-\xf3])|(\xe0[\xa0-\xbf])|(\xed[\x80-\x9f])|(\xf0[\x90-\xbf])|(\xf4[\x80-\x8f])/ || $max_ord > 255) {
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
