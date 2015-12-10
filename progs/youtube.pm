package progs::youtube;

use strict;
use warnings;
use progs::telerama;
use HTML::Entities;

@progs::youtube::ISA = ("progs::telerama");

our $debug = 0;

sub mydecode {
	my $desc = shift;
	$desc =~ s/<.+?>//g; # vire tous les tags html
	$desc = decode_entities($desc);
	$desc;
}

# Un plugin minimum pour le bandeau d'info youtube : g�n�ralement y a pas
# grand chose d'int�ressant mais �a peut arriver (accident !), par exemple
# pour le clip "toute la vie" des enfoir�s, et y a en tous cas la date de
# mise en ligne ce qui peut �tre int�ressant des fois.

sub get {
	my ($p,$channel,$source,$base_flux) = @_;
	return undef if ($source ne "flux" || $base_flux !~ /^youtube/);

	# Le $channel contient $title $q $type donc...
	my ($title) = $channel =~ /(.+) .+? .+?$/;
	if (open(F,"<cache/yt/$title")) {
		my ($suffix,$upload,$info) = <F>;
		close(F);
		print "prog_youtube: got suffix $suffix.\n";
		chomp $suffix;
		$upload = mydecode($upload);
		$info = mydecode($info);
		my @tab = (undef, # chan id
			"$source", "$title",
			undef, # d�but
			undef, "", # fin
			$info, # desc
			$upload, # details
			"",
			"http://i.ytimg.com/vi/$suffix/mqdefault.jpg",
			0,0,
			undef);
		return \@tab;
	}
	print STDERR "prog_youtube: fichier cache/yt/$title: pas trouv�\n";
	return undef;
}

1;
