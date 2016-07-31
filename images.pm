#!/usr/bin/env perl

package images;

use WWW::Mechanize;
use Encode;
use MIME::Base64;
use strict;

our $debug = 0;

sub search {
	my ($self,$q) = @_;
	my $mech;
	my @tab = ();
	do {
		eval {
			$mech = WWW::Mechanize->new();
			# $mech->agent_alias("Linux Mozilla");
			# Qui l'eut cru ? Les pages sont générées à partir du user agent, je
			# croyais que plus personne ne faisait ça ou presque, et bin si, la preuve!
			# Si on envoie un agent récent, on obtient la version javascript de frime
			# avec toutes les infos dedans !!! :))))
			$mech->agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_5) AppleWebKit/537.71 (KHTML, like Gecko) Version/6.1 Safari/537.71");
			$mech->timeout(10);
			$mech->default_header('Accept-Encoding' => scalar HTTP::Message::decodable());

# $mech->get("https://www.google.fr/search?hl=fr&site=imghp&tbm=isch&source=hp&biw=1240&bih=502&q=chien");
# my $pwd = `pwd`;
# chomp $pwd;
# $mech->get("file://$pwd/final.html");
			$mech->get("https://www.google.fr/imghp");
		};
		if ($@) {
			print "*** images.pm: got error $@\n";
		}
	} while ($@);
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

	# Décodage du js... !
	my $c = $mech->content;
	# $mech->save_content("page.html");
	my @vignette = ();
	while ($c =~ s/a href="([^"]+?)"[^>]* class="?rg_l// ||
		$c =~ s/a class="?rg_l" href="([^"]+?)"//) {
		my $link = $1;
		my @args = split(/&amp;/,$link);
		$args[0] =~ s/^.+\?//; # Récupère le 1er argument
		# il doit probablement y avoir une fonction dans libwww pour faire ça
		# + directement, mais bon... !
		my %args;
		print "found link $link\n" if ($debug);
		foreach (@args) {
			my ($name,$val) = split(/=/);
			$args{$name} = $val;
		}
		push @tab,\%args; # on garde tout, pourquoi se priver ?!!!

		# Bonus : on recherche la vignette
		if (!$args{tbnid} || !$args{imgurl}) {
			print "pas de tbnid ou d'imgurl, j'ai :\n";
			foreach (keys %args) {
				print "$_: $args{$_}\n";
			}
			exit(1);
			next;
		}
		if ($c =~ s/e\.src='([^']+?)';}}\)\(document.getElementsByName\('$args{tbnid}//){
			my $b64 = $1;
			my $name;
			if ($b64 =~ /^data:image\/jpeg/) {
				$name = "cache/vn_$args{tbnid}.jpg";
				$name =~ s/://;
			} else {
				print "base64: file type not recognized : ",substr($b64,0,16),"\n";
				next;
			}
			if (!-f $name) {
				if (open(F,">$name")) {
					$b64 =~ s/^.+?base64,//;
					print F decode_base64($b64);
					close(F);
				}
			} else {
				utime(undef,undef,$name);
			}
			push @vignette,$name;
		}
	}
	$self->{tab} = \@tab;
	\@vignette;
}

sub new {
	my $self  = shift;
	my $class = ref($self) || $self;
	return bless {
	 tab => (),
	}, $class;
}

1;
