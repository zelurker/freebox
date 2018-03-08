#!/usr/bin/env perl

use strict;
use warnings;
use WWW::Mechanize;
require "radios.pl";
use Data::Dumper;
use v5.10;
use search;
use strict;

$| = 1;
my %icons = get_icons();
our %flux;

sub disp_stations {
	print "\n";
	say "flux:";
	foreach (sort { $a cmp $b } keys %flux) {
		print "  \"$_\" => \"$flux{$_}\",\n"
	}
	print "\n";

	say "icons:";
	foreach (sort { $a cmp $b } keys %icons) {
		print "  \"$_\" => \"$icons{$_}\",\n"
	}
}

sub init_mech {
	my $mech = WWW::Mechanize->new();
#$mech->agent_alias("Linux Mozilla");
	$mech->agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_5) AppleWebKit/537.71 (KHTML, like Gecko) Version/6.1 Safari/537.71");
	$mech->timeout(20);
	$mech->default_header('Accept-Encoding' => scalar HTTP::Message::decodable());
	$mech;
}

sub search_flux {
	my ($url,$visited,$mech) = @_;
	$visited = [] if (!defined($visited));
	push @$visited,$url;
	$mech = init_mech() if (!$mech);
	say "search_flux: entering with url ",$url;
	$mech->get($url);
	my $page = $mech->content;
	if ($page =~ /(file|mp3|m4a): ?["'](.+?)["']/ || $page =~ /(data-src|data-url-live)="(.+?)"/ || $page =~ /(url)&quot;:&quot;(http.+?)&quot;/ ||
		$page =~ /meta property="(og:audio)" content="(.+?)"/ || $page =~ /(source)":"(.+?)"/) {
		say "search_flux : found $1 info $2";
		return $2;
	}
	foreach ($mech->links) {
		my $link = $_->url;
		if ($_->text && $_->text =~ /coute/ && !grep { $_ eq $link } @$visited) {
			say "search_flux: selected ",$_->text," url ",$_->url;
			return search_flux($_->url,$visited,$mech);
		}
	}
	$mech->save_content("page.html");
	die "search_flux page saved";
}

my $mech = init_mech();

open(my $i,"<flux/stations") || die "can't read stations\n";
my $last = "";
while (<$i>) {
	chomp;
	next if (/^encoding/);
	my $url = <$i>;
	my $prog;
	($url,$prog) = split(/ /,$url);
	my $station = $_;
	next if ($last && $station ne $last);
	$last = undef;
	my $adr = $icons{$station};
	print "$_: vérif flux... ";
	eval {
		$mech->head($url);
	};
	if ($@ && $@ =~ /bad request/i) {
		print "can't head : $@ trying get... ";
		$mech->max_size(10000);
		$mech->get($url);
		$mech->max_size();
	}
	if (!$@) {
		say "ok";
	} else {
		say "pas ok : $!: $@";
		$mech = search_station("radio $station");
		foreach ($mech->links) {
			next if ($_->url =~ /(streama|ecouterradio|ecouter-en-direct.com|ecouter-la-radio.fr)/);
			if ($_->text && $_->text =~ /(coutez|player|direct)/i && $_->url !~ /radioguide/) {
				my $flux = search_flux($_->url);
				$flux{$station} = $flux.($prog ? " $prog" : "");
				last;
			}
		}
		if (!$flux{$station}) {
			say "pas trouvé de flux pour $station. Liens :\n";
			foreach ($mech->links) {
				say $_->text if ($_->text);
			}
			$mech->save_content("page.html");
			exit(0);
		}
	}
	if ($adr) {
		print "j'ai déjà $_, check... ";
		eval {
			$mech->head($adr);
		};
		if (!$@) {
			print "ok\n";
			delete $icons{$station};
			next;
		} else {
			print "$!: $@\n";
			delete $icons{$station};
		}
	}
	$mech = search_station("logo $station".(/radio/i ? "" : " radio"));
	foreach ($mech->links) {
		my $sub = $_->url;
		if ($sub && $sub =~ /(png|jpg|jpeg)$/i && $sub =~ /^http/) {
			say "trying link for logo : $sub";
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
		print "found $sub\n" if ($sub && $sub =~ /wiki/);
	}
	if (!$icons{$station}) {
		say "rien trouvé pour station $station";
		$mech->save_content("page.html");
		open(F,">links");
		foreach ($mech->links) {
			print F $_->url,"\n";
		}
		close(F);
	}
}

sub search_station {
	my ($texte) = @_;
	return search::search($texte);
}

END {
	disp_stations();
}

