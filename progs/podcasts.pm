package progs::podcasts;

# basé sur labas.pm

use strict;
use progs::telerama;
use XML::Simple;
use HTML::Entities;
use Date::Parse;

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
	print STDERR "progs/podcats/get chan $channel source $source\n"; # if ($debug);
	if (!$debug) {
		return undef if ($source ne "flux" || $base_flux !~ /^podcasts.*\/(.+)/);
		my $choice = $1;
		return undef if ($choice =~ /^(result|Abonnements)/ || !-f "pod");
		return \@tab if ($last_chan && $last_chan eq $channel);
	}
	$last_chan = $channel;

	my $ref;
	eval {
		if (open(F,"<pod")) {
			@_ = <F>;
			close(F);
			$_ = join("",@_);
		} else {
			die "pas de fichier pod ???\n";
		}
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
		# qui ont des 404 sur les images des épisodes qui sont souvent les mêmes
		# en + !
		my $img = $ref->{"channel"}->{image}->{url};
		# my $img = $_->{"media:thumbnail"}->{url};
		my $title = $_->{title};
		my $date = $_->{pubDate};
		$date = str2time($date) if ($date !~ /^\d+$/);
		$title .= " le ".get_date($date) if ($date);
		if ($title eq $channel) {
			my $desc = mydecode($_->{"description"});
			$date = get_date($date);
			$date =~ s/,.+//;
			@tab = (undef, "podcasts", $title,
				undef, # début
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
