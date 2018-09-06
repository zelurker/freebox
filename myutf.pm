package myutf;

# un mydecode universel qui décode en fonction de la locale
# détecte ce qu'on lui passe et ré-encode selon la locale quoi
# attention référence en paramètre

use Encode;
use strict;

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
		if ($$ref =~ /[\xc3\xc5]/ || $max_ord > 255) {
			# print "to_utf: reçu un truc en utf: $$ref\n";
			return;
		}
		eval {
			Encode::from_to($$ref,"iso-8859-1","utf8");
		};
		if ($@) {
			print "to_utf: error encoding $$ref: $!, $@\n";
		}
	} elsif ($$ref =~ /[\xc3\xc5]/ || $max_ord > 255) {
		utf8::encode($$ref) if ($max_ord > 255);
		eval {
			Encode::from_to($$ref,"utf8","iso-8859-1");
		};
		if ($@) {
			print "to_utf: error encoding $$ref: $!, $@\n";
		}
	}
}

1;
