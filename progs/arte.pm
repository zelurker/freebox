package progs::arte;

use strict;
use warnings;
use progs::telerama;
use Cpanel::JSON::XS qw(decode_json);
use HTML::Entities;
use Time::Local "timelocal_nocheck","timegm_nocheck";
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
		$json = $_; # decode_entities($1);
		last;
	}
	close($f);
	eval {
		$json = decode_json($json);
	};
	if ($@) {
		print "progs/arte: decode_json error $! à partir de $json\n";
		return undef;
	}
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

sub parse_time {
	my $t = shift;
	return undef if (!$t);
	my ($d,$h) = split(/T/,$t);
	my ($a,$m,$j) = split(/\-/,$d);
	$a -= 1900;
	$m--;
	my ($hr,$min,$sec) = split(/:/,$h);
	return timegm_nocheck($sec,$min,$hr,$j,$m,$a);
}

sub get {
	my ($p,$channel,$source,$base_flux,$serv) = @_;
	# print "arte: channel $channel,$source,$base_flux,$serv\n";
	return undef if ($source !~ /flux/ || $base_flux !~ /^arte/);
	@arg = split(/\//,$serv);
	if ($serv !~ /vid:(.+)/ && $#arg > 0) {
		$serv = read_last_serv();
	}
	say STDERR "progs/arte: serv $serv";
	@arg = split(/\//,$serv);
 	return undef if ($arg[$#arg] !~ /vid:(.+)/);
 	my $code = $1;
	$code =~ s/,.+//;
	say "progs/arte: code $code";

	my ($f,$json);

	# ça se complique, on a 3 sources de json possibles, et les 3 ont des
	# formats différents, bien sûr... !
	# voilà le 1er, l'index principal du site...
	# ou un sous-index à retrouver !
	for (my $idx=$#arg-1; $idx >= 0; $idx--) {
		if ($arg[$idx] =~ /^vid:(.+?),/) {
			say "progs/arte: on teste cache/arte/$1...";
			return undef if (!open($f,"<cache/arte/$1"));
			say STDERR "progs/arte: lecture $1";
			last;
		}
	}
	if (!$f) {
		open($f,"<cache/arte/$code");
		say "progs/arte: lecture cache/arte/$code" if ($f);
	}

	if (!$f) {
		return undef if (!open($f,"<cache/arte/j0"));
		say "progs/arte: lecture j0";
	}
	$json = read_json($f);
	return undef if (!$json);
	my $date = $json->{data}{attributes}{rights}{end}; # pas sûr
	my $fin = parse_time($date);

	# On vérifie si on a le fichier détaillé, sans le récupérer, il n'y a
	# qu'un résumé + long utile dedans pour ça...
	my $title = $json->{data}{attributes}{metadata}{title};
	my $sub = $json->{data}{attributes}{metadata}{subtitle};
	my $sum = $json->{data}{attributes}{metadata}{description};
	my $img = $json->{data}{attributes}{metadata}{images}[0]{url};

	my @tab = (undef, # chan id
		"$source", $title,
		undef, # $debut,
		$fin, "", # fin
		$sub,
		$sum, # details
		"",
		$img,
		0,0,
		$date);
	return \@tab;
}

1;
