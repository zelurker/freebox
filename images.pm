#!/usr/bin/env perl

package images;

use WWW::Mechanize;
use Encode;

our $debug = 0;
our $latin = ($ENV{LANG} !~ /UTF/i);

sub find_around($$$) {
	# Essaye de trouver l'image après la chaine f dans le contenu s
	# C'est très très expérimental
	my ($s,$f,$url) = @_;
	my ($base) = $s =~ /base href="(.+?)"/;
	$base = $url if (!$base);
	$base =~ s/^(.+\/).+/$1/;
	if ($s =~ /charset=UTF-8/i) {
		$s =~ s/\xe2\x80\x99/'/g; # l'apostrophe à la con de windoze
		my $i;
		do {
			$i = index($s,chr(8217));
			if ($i>0) {
				substr($s,$i,1) = "'";
			}
		} while ($i > 0);
		Encode::_utf8_off($s);
		Encode::from_to($s, "utf-8", "iso-8859-15");
		$s =~ s/\xa0/ /g; # Supprime les espaces insécables !!!
		$s =~ s/\&\#8217\;/'/g; # et enfin la version html de l'apostrophe !!!
		open(F,">decoded");
		print F $s;
		close(F);
	}
	print "base $base\n" if ($debug);
	my $pos = 0;
	while ($pos >= 0) {
		$pos = index($s,$f,$pos+1);
		if ($pos > 0) {
			while(1) {
				my $tag = index($s,"<",$pos+1);
				last if ($tag < 0);
				$tag++;
				if (substr($s,$tag,1) eq "/") {
					$pos = $tag;
					redo;
				}
				my $name = "";
				while (1) {
					my $l = substr($s,$tag,1);
					if ($l !~ /[ >]/) {
						$name .= $l;
						$tag++;
					} else {
						last;
					}
				}
				print "found tag $name\n" if ($debug);
				if ($name =~ /^(a|b|em|\!\-\-|table|tr|td|br|div|span|p|h\d)$/i) {
					$pos = $tag;
					redo;
				}
				if ($name =~ /img/i) {
					my ($src) = substr($s,$tag) =~ /src="(.+?)"/;
					$src = $base.$src if ($src !~ /^http/);
					return $src;
				}
				last;
			}
		}
	}
	# La même chose, mais en cherchant l'img avant la chaine
	print "find_around: 2nd loop\n" if ($debug);
	$pos = 0;
	while ($pos >= 0) {
		$pos = index($s,$f,$pos+1);
		if ($pos > 0) {
			my $tpos = $pos;
			while(1) {
				my $tag = rindex($s,"<",$tpos);
				last if ($tag < 0);
				$tag++;
				if (substr($s,$tag,1) eq "/") {
					$tpos = $tag-2;
					redo;
				}
				my $name = "";
				while (1) {
					my $l = substr($s,$tag,1);
					if ($l !~ /[ >]/) {
						$name .= $l;
						$tag++;
					} else {
						last;
					}
				}
				print "found tag $name\n" if ($debug);
				if ($name =~ /^(a|b|em|\!\-\-|table|tr|td|br|span|div|p|h\d)$/i) {
					$tpos = $tag-length($name)-2;
					redo;
				}
				if ($name =~ /img/i) {
					my ($src) = substr($s,$tag) =~ /src="(.+?)"/;
					$src = $base.$src if ($src !~ /^http/);
					return $src;
				}
				last;
			}
		}
	}
}

sub save($$) {
	my ($self,$mech,$url) = @_;
	push @{$self->{tab}},$url;
	print "saving $url\n" if ($debug);

#	$mech->get( $url);
#	$mech->save_content(sprintf("img%02d.jpg",$nb++));
#	$mech->back();
}

sub search {
	my ($self,$q) = @_;
	my $mech = WWW::Mechanize->new();
	@tab = ();
	$mech->agent_alias("Linux Mozilla");
	$mech->timeout(10);
	$mech->default_header('Accept-Encoding' => scalar HTTP::Message::decodable());

# $mech->get("https://www.google.fr/search?hl=fr&site=imghp&tbm=isch&source=hp&biw=1240&bih=502&q=chien");
# my $pwd = `pwd`;
# chomp $pwd;
# $mech->get("file://$pwd/final.html");
	$mech->get("https://www.google.fr/imghp");
	$mech->submit_form(
		form_number => 1,
		fields      => {
			site => "imghp",
			q => $q,
			biw => 1337,
			bih => 722,
		}
	);
	$self->{mech} = $mech;
	$mech->images;
}

sub save_vignettes {
	# A appeler après un appel à search pour sauver les vignettes trouvées
	my $self = shift;
	my $mech = $self->{mech};
	foreach (@{$mech->{images}}) {
		my $url = $_->url_abs;
		if ($url =~ /tbn\:(.+)/) {
			my $name = "cache/$1.jpg";
			if (-f $name) {
				print "already in cache $name\n";
				utime(undef,undef,$name);
				next;
			}
			print "saving $name\n";
			$mech->get($url);
			$mech->save_content($name);
		}
	}
}

sub big_pictures {
	my $self = shift;
	my $mech = $self->{mech};
	my $c = $mech->content;
	while ($c =~ s/<td style="width.+?>(.+?)<\/td//) {
		# Franchement google nous complique incroyablement la vie en supprimant
		# presque toute info sur l'image de l'interface sans javascript on a
		# même pas le nom du fichier !
		# Donc l'idée c'est de récupérer le bout de texte sur la 2ème ligne,
		# de le retrouver sur la page, et de trouver l'image la + proche.
		# Si on est chanceux ce texte est dans le alt de l'image, mais c'est
		# très rare. Autrement c'est une description avant ou après.
		# Evidemment selon la page la recherche n'est pas fiable à 100%, on
		# peut ramener un bouton par erreur !
		my $l = $1;
		my @br = split("<br>",$l);
		my ($url) = $br[0] =~ /q=(.+?)\&amp/;
		$url =~ s/%(..)/chr(hex($1))/ge;
		my $alt = $br[2];
		$alt =~ s/<\/?b>//g;
		$alt =~ s/\&\#(..)\;/chr($1)/ge;
		eval {
			$mech->get($url);
		};
		next if ($@); # timeout
		my $l;
		eval {
			$l = $mech->find_image(alt_regex => qr/$alt/);
		};
		print "alt $alt\n" if ($debug);
		if ($@) {
			$l = $mech->find_image(alt => $alt);
		}
		if (!$l) {
			my $src = find_around($mech->content,$alt,$url);
			if ($src) {
				$self->save($mech,$src);
				print "\n" if ($debug);
				next;
			}
		}
		if ($l) {
			$self->save($mech,$l->url_abs);
		} else {
			$mech->save_content("content.html") if ($debug);
			# my $l = $mech->images();
# 		for (my $n=0; $n<=$#$l; $n++) {
# 			print "link $n: url ",$$l[$n]->url," name ",$$l[$n]->name," alt ",$$l[$n]->alt," base ",$$l[$n]->base,"\n";
# 		}
			print "pas got l $l\n" if ($debug);
			# exit(0) if (debug);
		}
	}
	$self->{tab};
}

sub new {
	my $self  = shift;
	my $class = ref($self) || $self;
	return bless {
	 tab => (),
	}, $class;
}

1;
