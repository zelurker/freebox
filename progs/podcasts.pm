package progs::podcasts;

# bas� sur labas.pm

use strict;
use progs::telerama;
use XML::Simple;
use HTML::Entities;
use Date::Parse;
use myutf;
use v5.10;

@progs::podcasts::ISA = ("progs::telerama");

sub mydecode {
	my $desc = shift;
	$desc =~ s/<.+?>//g; # vire tous les tags html
	$desc = decode_entities($desc);
	$desc;
}

our $debug = 0;
our @tab;
our $last_chan;

sub get {
	my ($p,$channel,$source,$base_flux) = @_;
	print STDERR "progs/podcats/get chan $channel source $source base_flux $base_flux\n"; # if ($debug);
	# M�me chose en entr�e, $channel est en latin1 parfois !
	myutf::mydecode(\$channel);
	if (!$debug) {
		return undef if ($source ne "flux" || $base_flux !~ /^podcasts.*\/(.+)/);
		my $choice = $1;
		return undef if ($choice =~ /^(result|Abonnements)/ || !-f "pod");
		return \@tab if ($last_chan && $last_chan eq $channel);
	}
	$last_chan = $channel;

	my $ref;
	eval {
#		if ($latin) {
#			open(F,"<:encoding(iso-8859-1)","pod") || die "peut pas lire pod\n";
#		} else {
#			open(F,"<:encoding(utf8)","pod") || die "peut pas lire pod\n";
#		}
		open(F,"<pod") || die "peut pas lire pod";
		@_ = <F>;
		close(F);
		$_ = join("",@_);
		# tsss, y a encore un pb d'encodage, on t�che de d�tecter si on a
		# r�cup�r� du latin en cherchant directement un code ascii de � ou
		# de �, extr�me mais on est un peu forc� l�. Ca arrive sur le
		# podcast de "le temps d'un bivouac"
		Encode::from_to($_, "iso-8859-1","utf-8") if (/[\xe9\xea]/);
		$ref	= XMLin($_);
	};
	if ($@) {
		print "progs::podcasts: erreur parsing xml, parser de merde... :$@\n";
		return;
	}

	my $item = $ref->{channel}->{item};
	# Vu que certains podcasts n'arrivent pas dans l'ordre, trie par date
	foreach (@$item) {
		# Vaut mieux utiliser l'image titre du podcast ici, y a des podcasts
		# qui ont des 404 sur les images des �pisodes qui sont souvent les m�mes
		# en + !
		my $img = $ref->{"channel"}->{image}->{url};
		# my $img = $_->{"media:thumbnail"}->{url};
		my $title = $_->{title};
		my $date = $_->{pubDate};
		$date = str2time($date) if ($date !~ /^\d+$/);
		$title .= " le ".get_date($date) if ($date);
		# tr�s bizarrement title est parfois en latin1 ici avec une locale
		# utf alors qu'on lit un xml utf ! �a change en fonction du sens du
		# vent d'une version de perl � l'autre... Normalement
		# myutf::mydecode devrait pouvoir corriger le truc dans tous les
		# cas, c'est justement fait pour �a !
		myutf::mydecode(\$title);
		say "progs/podcasts: $title cmp $channel" if ($debug);
		if ($title eq $channel) {
			my $desc = mydecode($_->{"description"});
			$date = get_date($date);
			$date =~ s/,.+//;
			@tab = (undef, "podcasts", $title,
				undef, # d�but
				undef, "", # fin
				$desc, # desc
				"","",
				$img, # img
				0,0,
				$date);
			return \@tab;
		}
	}
	print STDERR "pas trouve le prog, cherchait channel $channel\n" if ($debug);
	return undef;
}

sub next {
	my ($p,$channel) = @_;
	return \@tab if ($channel eq $last_chan);
}

sub prev {
	my ($p,$channel) = @_;
	return \@tab if ($channel eq $last_chan);
}

sub get_date {
	my $time = shift;
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime($time);
	sprintf("%d/%02d/%02d, %02d:%02d",$mday,$mon+1,$year+1900,$hour,$min);
}

1;
