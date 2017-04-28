package progs::arte;

use strict;
use warnings;
use progs::telerama;
use Cpanel::JSON::XS qw(decode_json);
use HTML::Entities;
use v5.10;
# require "http.pl";

@progs::arte::ISA = ("progs::telerama");

our $debug = 0;
our @arg;
our $latin = ($ENV{LANG} !~ /UTF/i);

sub find_id {
	$_ = shift;
	my $id = shift;
	# Navigation dans le json, c'est l� qu'on perd le + de temps parce que
	# les structures changent en fonction des cat�gories choisies, donc
	# faut s'adapter...

	if (ref($_) eq "HASH") {
		my %hash = %$_;
        if ($hash{tvguide}) { # racine du nouveau hash 2017
			if ($hash{page}{zones}) {
				return find_id($hash{page}{zones},$id);
			} elsif ($hash{collection}{videos}) {
				return find_id($hash{collection}{videos},$id);
			}
		}
		return find_id($hash{teasers},$id) if ($hash{teasers});
		if ($hash{programId} && $hash{programId} eq $id) {
			return \%hash;
		}
	} elsif (ref($_) eq "ARRAY") {
		foreach (@$_) {
			my $truc = find_id($_,$id);
			return $truc if ($truc);
		}
	}
	undef;
}

sub read_json {
	my $f = shift;
	my $json;
	while (<$f>) {
		chomp;
		if (/__INITIAL_STATE__ = (.+);/) {
			$json = decode_entities($1);
			last;
		}
	}
	close($f);
	$json;
}

sub read_last_serv {
	my $serv;
	if (open(F,"<cache/arte/last_serv")) {
		$serv = <F>;
		chomp $serv;
		close(F);
	}
	$serv;
}

sub get {
	my ($p,$channel,$source,$base_flux,$serv) = @_;
	# print "arte: channel $channel,$source,$base_flux,$serv\n";
	return undef if ($source !~ /flux/ || $base_flux !~ /^arte/);
	@arg = split(/\//,$serv);
	if ($serv !~ /vid:(.+)/ && $#arg > 0) {
		$serv = read_last_serv();
	}
	$serv =~ s/vid:(.+),.+/vid:$1/;
 	return undef if ($serv !~ /vid:(.+)/);
 	my $code = $1;

	@arg = split(/\//,$serv);
	my ($f,$json);

	# �a se complique, on a 3 sources de json possibles, et les 3 ont des
	# formats diff�rents, bien s�r... !
	# voil� le 1er, l'index principal du site...
	return undef if (!open($f,"<cache/arte/j0"));
	$json = read_json($f);
	eval {
		$json = decode_json($json);
	};
	if ($@) {
		print "progs/arte: decode_json error $! � partir de $json\n";
		return undef;
	}
	my $hash = find_id($json,$code);
	if (!$hash) {

		# si �a marche pas, on passe � la 2�me source : si on est sur une
		# liste de vid�os genre concerts ou s�ries, dans ce cas l� faut
		# r�cup�rer le bon serv de flux/arte.pm dans last_serv...
		$serv = read_last_serv();
		my ($id) = $serv =~ /vid:(.+?),/;
		if ($id ne $code) {
			if (open($f,"<cache/arte/$id.html")) {
				$json = read_json($f);
				$json = decode_json($json);
			}
		}
		$hash = find_id($json,$code) if (!$hash);
	}
	my $date = $hash->{creationDate}; # pas s�r
	$date = $hash->{videoRightsBegin} if (!$date);
	if ($date) {
		my ($year,$mon,$day) = split(/\-/,$date);
		$date = "$day/$mon/$year";
	}
	my $sum = $hash->{teaser};

	# On v�rifie si on a le fichier d�taill�, sans le r�cup�rer, il n'y a
	# qu'un r�sum� + long utile dedans pour �a...
	my $title = $hash->{title};
	my $sub = $hash->{subtitle};
	my $img = $hash->{images};
	# les images sont un gros merdier dans la version 2017, c'est dingue
	# d'en garder autant !
	foreach (@$img) {
		if ($_->{format} eq "landscape") {
			my $min = 9999;
			my $url;
			foreach (@{$_->{alternateResolutions}}) {
				if ($_->{width} < $min) {
					$min = $_->{width};
					$url = $_->{url};
				}
			}
			$img = $url;
			last;
		}
	}
	if (!$img || ref($img) eq "ARRAY") {
		$img = $hash->{mainImage}{url};
	}
	if (open(my $f,"<cache/arte/$code")) {
		# Et voil� la 3�me, en lecture directe d'une vid�o on a un hash
		# pour le player d'un format totalement diff�rent.
		@_ = <$f>;
		close($f);
		my $truc = join("\n",@_);
		my $j = decode_json(decode_entities($truc));
		$title = $j->{videoJsonPlayer}{VTI} if (!$title);
		$sub = $j->{videoJsonPlayer}{V7T} if (!$sub);
		$sum .= " ".$j->{videoJsonPlayer}{VDE} if (!$sum);
		$img = $j->{videoJsonPlayer}{VTU}{IUR} if (!$img || ref($img) eq "ARRAY");
		# Note : apparemment il manque la date dans celui l�, on peut la
		# r�cup�rer si on va lire le fichier .player, mais bon la date
		# n'est pas vraiment super importante ici...
	} elsif (!$title) {
		return undef;
	}

	my @tab = (undef, # chan id
		"$source", $title,
		undef, # d�but
		undef, "", # fin
		$sub,
		$sum, # details
		"",
		$img,
		0,0,
		$date);
	return \@tab;
}

1;
