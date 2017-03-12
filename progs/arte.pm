package progs::arte;

use strict;
use warnings;
use progs::telerama;
use Cpanel::JSON::XS qw(decode_json);
use HTML::Entities;
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
		if ($hash{id} && $hash{id} eq $id) {
			return \%hash;
		} elsif ($hash{day}) { # vidéos les + vues
			if ($arg[2] eq $hash{day}) {
				return find_id($hash{videos},$id);
			}
		} elsif ($hash{category}) { # catégories de vidéos
			if ($hash{category}{code} eq $arg[2]) {
				return find_id($hash{videos},$id);
			}
		} elsif ($hash{videos}) { # probablement videoSet, juste des videos...
			return find_id($hash{videos},$id);
		}
	} elsif (ref($_) eq "ARRAY") {
		foreach (@$_) {
			my $truc = find_id($_,$id);
			return $truc if ($truc);
		}
	}
	undef;
}

sub to_utf {
	while (my $ref = shift @_) {
		next if (!$$ref);
		$$ref =~ s/\x{2019}/'/g;
		$$ref =~ s/\x{0153}/oe/g;
		if (!$latin) {
			if ($$ref =~ /[\xc3\xc5]/) {
				print "to_utf: reçu un truc en utf: $$ref\n";
				next;
			}
			eval {
				Encode::from_to($$ref,"iso-8859-1","utf8");
			};
			if ($@) {
				print "to_utf: error encoding $$ref: $!, $@\n";
			}
		} elsif ($$ref =~ /[\xc3\xc5]/) {
			eval {
				Encode::from_to($$ref,"utf8","iso-8859-1");
			};
			if ($@) {
				print "to_utf: error encoding $$ref: $!, $@\n";
			}
		}
	}
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
 	return undef if ($serv !~ /vid:(.+)/);
 	my $code = $1;

	@arg = split(/\//,$serv);
	my ($f,$json);
	return undef if (!open($f,"<cache/arte/j$arg[0]"));
	while (<$f>) {
		chomp;
		if (/$arg[1]="(.+)"/) {
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
	my $hash = find_id($json,$code);
	my $date = $hash->{scheduled_on};
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
	to_utf(\$title,\$sub,\$sum);

	my @tab = (undef, # chan id
		"$source", $title,
		undef, # début
		undef, "", # fin
		$sub,
		$sum, # details
		"",
		$hash->{thumbnail_url}, # img
		0,0,
		$date);
	return \@tab;
}

1;
