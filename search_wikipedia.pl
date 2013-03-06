#!/usr/bin/env perl 
#===============================================================================
#
#         FILE: search_wikipedia.pl
#
#        USAGE: ./search_wikipedia.pl  
#
#  DESCRIPTION: Recherche les icones des radios sur wikipedia !
#
#      OPTIONS: ---
# REQUIREMENTS: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Emmanuel Anne (), emmanuel.anne@gmail.com
# ORGANIZATION: 
#      VERSION: 1.0
#      CREATED: 06/03/2013 15:43:24
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use LWP;

sub check_error {
	my $response = shift;
	if (!$response->is_success) {
		print STDERR "got error ",$response->code," msg ",$response->message,"\n";
		exit(0);
	}
}
my $useragt = 'Telerama/1.0 CFNetwork/445.6 Darwin/10.0.0d3';
my $site_addr = "guidetv-iphone.telerama.fr";
my $browser = LWP::UserAgent->new(keep_alive => 0,
                                  agent =>$useragt);
$browser->timeout(10);
$browser->default_header(
	[ 'Accept-Language' => "fr-fr"
		#                          'Accept-Encoding' => "gzip,deflate",
		# 'Accept-Charset' => "ISO-8859-15,utf-8"
	]
);

open(my $i,"<flux/stations") || die "can't read stations\n";
while (<$i>) {
	chomp;
	my $station = $_;
	s/ /\+/g;
	my $response = $browser->get("http://www.wikipedia.fr/Resultats.php?q=logo+$_");
	check_error($response);
	my $t = $response->content;
	my $link;
	my $n = 0;
	while ($t =~ s/<a href="(.+?)" target="_blank//) {
		$link = $1;
		$n++;
		last if ($link !~ /"/ && $link =~ /$station/i);
		last if ($n>=20);
# 		if ($link !~ /"/) {
# 			print STDERR "rejected $link station $station\n";
# 		}
	}
	if ($n >= 20) {
		print STDERR "no good link for $station\n";
		<$i>;
		next;
	}
	$link =~ s/ /_/g;
	$link =~ s/\&\#233;/é/g;
	print STDERR "found link $link\n";
	$response = $browser->get($link) || die "couldn't get $link !\n";
	check_error($response);
	my $p = $response->content;
	$p =~ s/class="thumbinner".+?href="(.+?)"//;
	if (!$1) {
		<$i>;
		next;
	}
	$link = $1;
	$link = "http://fr.wikipedia.org$link" if ($link !~ /^http/);
	$response = $browser->get($link) || die "couldn't get $link !\n";
	check_error($response);
	$p = $response->content;
	$p =~ s/href="(\/\/upload\..+?)"//;
	if (!$1) {
		<$i>;
		next;
	}
	$link = $1;
	$link = "http:$link";
	print STDERR "image finale $link pour $station\n";
	print "\"$station\" => \"$link\",\n";
	<$i>;
}
close($i);

