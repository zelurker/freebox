package myutf;

# un mydecode universel qui décode en fonction de la locale
# détecte ce qu'on lui passe et ré-encode selon la locale quoi
# attention référence en paramètre

use Encode;
use strict;
use v5.10;

our $latin = ($ENV{LANG} !~ /UTF/i);

sub F { 0 }  # character never appears in text */
sub T { 1 }  # character appears in plain ASCII text */
sub I { 2 }  # character appears in ISO-8859 text */
sub X { 3 }  # character appears in non-ISO extended ASCII (Mac, IBM PC) */

my @text_chars = (
	#                   BEL BS HT LF VT FF CR    */
	F, F, F, F, F, F, F, T, T, T, T, T, T, T, F, F,  #  0x0X */
	#                               ESC          */
	F, F, F, F, F, F, F, F, F, F, F, T, F, F, F, F,  #  0x1X */
	T, T, T, T, T, T, T, T, T, T, T, T, T, T, T, T,  #  0x2X */
	T, T, T, T, T, T, T, T, T, T, T, T, T, T, T, T,  #  0x3X */
	T, T, T, T, T, T, T, T, T, T, T, T, T, T, T, T,  #  0x4X */
	T, T, T, T, T, T, T, T, T, T, T, T, T, T, T, T,  #  0x5X */
	T, T, T, T, T, T, T, T, T, T, T, T, T, T, T, T,  #  0x6X */
	T, T, T, T, T, T, T, T, T, T, T, T, T, T, T, F,  #  0x7X */
	#             NEL                            */
	X, X, X, X, X, T, X, X, X, X, X, X, X, X, X, X,  #  0x8X */
	X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X,  #  0x9X */
	I, I, I, I, I, I, I, I, I, I, I, I, I, I, I, I,  #  0xaX */
	I, I, I, I, I, I, I, I, I, I, I, I, I, I, I, I,  #  0xbX */
	I, I, I, I, I, I, I, I, I, I, I, I, I, I, I, I,  #  0xcX */
	I, I, I, I, I, I, I, I, I, I, I, I, I, I, I, I,  #  0xdX */
	I, I, I, I, I, I, I, I, I, I, I, I, I, I, I, I,  #  0xeX */
	I, I, I, I, I, I, I, I, I, I, I, I, I, I, I, I   #  0xfX */
);

#sub looks_ascii {
#    my $text = shift;
#    for (my $i = 0; $i < length($text); $i++) {
#	my $t = $text_chars[ord(substr($text,$i,1))];
#
#	return 0 if ($t != T)
#    }
#}

sub looks_utf8 {
	# seems to return likelyhood of utf8 :
	# 0 certainly not
	# 1 maybe but not sure, like a string ending before checking what came after the last char...
	# 2 certain it's utf8
	# so in most cases should probably always test for looks_utf8 == 2 !
    my $text = shift;
    my $ctrl = 0;

    my $gotone = 0;
    for (my $i = 0; $i < length($text); $i++) {
	my $c = ord(substr($text,$i,1));
	if (($c & 0x80) == 0) {	   #  0xxxxxxx is plain ASCII */
	    # Even if the whole file is valid UTF-8 sequences,
	    # still reject it if it uses weird control characters.

	    $ctrl = 1 if ($text_chars[$c] != T);

	} elsif (($c & 0x40) == 0) { #  10xxxxxx never 1st byte */
	    return 0;
	} else {			   #  11xxxxxx begins UTF-8 */
	    my $following;

	    if (($c & 0x20) == 0) {		#  110xxxxx */
		$c &= 0x1f;
		$following = 1;
	    } elsif (($c & 0x10) == 0) {	#  1110xxxx */
		$c &= 0x0f;
		$following = 2;
	    } elsif (($c & 0x08) == 0) {	#  11110xxx */
		$c &= 0x07;
		$following = 3;
	    } elsif (($c & 0x04) == 0) {	#  111110xx */
		$c &= 0x03;
		$following = 4;
	    } elsif (($c & 0x02) == 0) {	#  1111110x */
		$c &= 0x01;
		$following = 5;
	    } else {
		return 0;
	    }

	    for (my $n = 0; $n < $following; $n++) {
		$i++;
		if ($i >= length($text)) {
		    goto done;
		}

		my $b = ord(substr($text,$i,1));
		if (($b & 0x80) == 0 || ($b & 0x40)) {
		    return 0;
		}

		$c = ($c << 6) + ($b & 0x3f);
	    }

	    $gotone = 1;
	}
    }
    done:
    return $ctrl ? 0 : ($gotone ? 2 : 1);
}

my @above;
sub restore_above($) {
	if (@above) {
		my $ref = shift;
		my $x = 0;
		for (my $n=0; $n<length($$ref); $n++) {
			if (ord(substr($$ref,$n)) == 1) {
				Encode::_utf8_off($above[$x]);
				substr($$ref,$n,1) = $above[$x++];
			}
		}
	}
}

sub mydecode {
	my $ref = shift;
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
	# pareil pour 201c ("), e2 80 9c
	my $orig = $$ref;
	@above = ();
	for (my $n=0; $n<length($$ref); $n++) {
		my $o = ord(substr($$ref,$n,1));
		if ($o > 255) {
			push @above,substr($$ref,$n,1);
			substr($$ref,$n,1) = "\x01";
			next;
		}
		$max_ord = $o if ($o > $max_ord);
	}
	if ($max_ord < 128) {
		restore_above($ref);
		return;
	}
	if (!$latin) {
#		if ($$ref =~ /Faux.fuyants/) {
#			for (my $n=0; $n<length($$ref); $n++) {
#				print substr($$ref,$n,1)," ",sprintf("%02x ",ord(substr($$ref,$n)));
#			}
#			print "\n";
#		}
		my $l = looks_utf8($$ref);
		if ($l == 2) {
			restore_above($ref);
			return;
		}

		eval {
			Encode::from_to($$ref,"iso-8859-15","utf8");
		};
		if ($@) {
			print "to_utf: error encoding $$ref: $!, $@\n";
		}
		restore_above($ref);
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
