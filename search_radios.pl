#!/usr/bin/env perl

use strict;
use warnings;
use WWW::Mechanize;
require "radios.pl";
use Data::Dumper;
use strict;

$| = 1;
my %icons = get_icons();
sub disp_stations {
	print "\n";
	foreach (sort { $a cmp $b } keys %icons) {
		print "  \"$_\" => \"$icons{$_}\",\n"
	}
}
my $site_addr = "guidetv-iphone.telerama.fr";
my $mech = WWW::Mechanize->new();
#$mech->agent_alias("Linux Mozilla");
$mech->agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_5) AppleWebKit/537.71 (KHTML, like Gecko) Version/6.1 Safari/537.71");
$mech->timeout(10);
$mech->default_header('Accept-Encoding' => scalar HTTP::Message::decodable());

open(my $i,"<flux/stations") || die "can't read stations\n";
while (<$i>) {
	chomp;
	my $url = <$i>;
	my $station = $_;
	next if ($station ne "MFM Lady");
	my $adr = $icons{$station};
	if ($adr) {
		print "j'ai déjà $_, check... ";
		eval {
			$mech->head($adr);
		};
		if (!$@) {
			print "ok\n";
			next;
		} else {
			print "$!: $@\n";
			delete $icons{$station};
		}
	}
	print "on étudie $station... ";
	my $q = "logo $station".(/radio/i ? "" : " radio");
	my $r;
	do {
		eval {
			$mech->get("https://www.google.fr/");
			$r = $mech->submit_form(
				form_number => 1,
				fields      => {
					q => $q,
				}
			);
		};
		if ($@) {
			print "Erreur $!: $@\n";
			my @forms = $mech->forms;
			for (my $n=0; $n<=$#forms; $n++) {
				print "$n: ",Dumper($forms[$n]),"\n";
			}
			print "sleeping 3s... ";
			sleep 3;
			print "\n";
			undef $mech;
			$mech = WWW::Mechanize->new();
#$mech->agent_alias("Linux Mozilla");
			$mech->agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_5) AppleWebKit/537.71 (KHTML, like Gecko) Version/6.1 Safari/537.71");
			$mech->timeout(10);
			$mech->default_header('Accept-Encoding' => scalar HTTP::Message::decodable());
		}
	} while ($@);
	foreach ($mech->links) {
		my ($sub) = $_->url =~ /q=(.+?)\&/;
		($sub) = $_->url =~ /url=(.+?)\&/ if (!$sub);
		if ($sub && $sub =~ /(png|jpg|jpeg)$/i) {
			eval {
				$mech->head($sub);
			};
			if (!$@) {
				if ($icons{$station}) {
					$icons{$station} .= "\n$sub";
				} else {
					$icons{$station} = $sub;
				}
			}
			print "ok:$sub\n";
		}
		print "found ",$sub,"\n" if ($sub && $sub =~ /wiki/);
	}
	if (!$icons{$station}) {
		print "rien trouvé ?\n";
		$mech->save_content("page.html");
		open(F,">links");
		foreach ($mech->links) {
			print F $_->url,"\n";
		}
		close(F);
	}
}

disp_stations();
