package progs::arte;

use strict;
use warnings;
use progs::telerama;
use Cpanel::JSON::XS qw(decode_json);
use HTML::Entities;
use v5.10;
use Data::Dumper;
# require "http.pl";

@progs::arte::ISA = ("progs::telerama");

our $debug = 0;
our @arg;
our $latin = ($ENV{LANG} !~ /UTF/i);

sub find_id {
	$_ = shift;
	my $id = shift;
	# Navigation dans le json, c'est là qu'on perd le + de temps parce que
	# les structures changent en fonction des catégories choisies, donc
	# faut s'adapter...

	if (ref($_) eq "HASH") {
		my %hash = %$_;
        if ($hash{tvguide}) { # racine du nouveau hash 2017
            return find_id($hash{page}{zones},$id);
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

sub get {
	my ($p,$channel,$source,$base_flux,$serv) = @_;
	# print "arte: channel $channel,$source,$base_flux,$serv\n";
	return undef if ($source !~ /flux/ || $base_flux !~ /^arte/);
	if ($serv !~ /vid:(.+)/ && open(F,"<cache/arte/last_serv")) {
		$serv = <F>;
		chomp $serv;
		close(F);
	}
	$serv =~ s/vid:(.+),.+/vid:$1/;
	say "arte: serv $serv";
 	return undef if ($serv !~ /vid:(.+)/);
 	my $code = $1;

	@arg = split(/\//,$serv);
	my ($f,$json);
	say "arte arg0 $arg[0]";
	return undef if (!open($f,"<cache/arte/j0"));
	while (<$f>) {
		chomp;
		if (/__INITIAL_STATE__ = (.+);/) {
			$json = decode_entities($1);
			last;
		}
	}
	close($f);
	eval {
		$json = decode_json($json);
	};
	if ($@) {
		print "progs/arte: decode_json error $! à partir de $json\n";
		return undef;
	}
	say "arte: find_id json ",ref($json)," code $code";
	my $hash = find_id($json,$code);
	say "arte: hash $hash";
	my $date = $hash->{creationDate}; # pas sûr
	my ($year,$mon,$day) = split(/\-/,$date);
	$date = "$day/$mon/$year";
	my $sum = $hash->{teaser};

	# On vérifie si on a le fichier détaillé, sans le récupérer, il n'y a
	# qu'un résumé + long utile dedans pour ça...
	my $title = $hash->{title};
	my $sub = $hash->{subtitle};
	if (open(my $f,"<cache/arte/$code")) {
		@_ = <$f>;
		close($f);
		my $truc = join("\n",@_);
		my $j = decode_json($truc);
		$sum .= " ".$j->{videoJsonPlayer}{VDE};
	}

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
	my @tab = (undef, # chan id
		"$source", $title,
		undef, # début
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
