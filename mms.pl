#!/usr/bin/perl

# Récupération des liens mms ou autres à partir d'une page web

use LWP 5.64;
use strict;

sub get_mms {
	my $url = shift;
	my $useragt = 'Telerama/1.0 CFNetwork/445.6 Darwin/10.0.0d3';
	my $browser = LWP::UserAgent->new(keep_alive => 0,
		agent =>$useragt);
	$browser->timeout(3);
	$browser->default_header(
		[ 'Accept-Language' => "fr-fr"
			#                          'Accept-Encoding' => "gzip,deflate",
			# 'Accept-Charset' => "ISO-8859-15,utf-8"
		]
	);

	$browser->max_size(65000);
	my $response = $browser->get($url);
	return undef if (!$response->is_success);
	my $page;
	if ($response->header("Content-type") =~ /audio/) {
		# audio/xxx est quand même prenable !
		print "url is not text : ",$response->header("Content-type"),"\n";
		$browser->max_size(5000);
		$page = $response->content;
		if ($page !~ /^\#EXTM3U/ && $page !~ /^\[playlist/ && $page !~ /"mms/) {
			# Evitez les crétins qui gèrent le m3u en audio !!!
			return $url;
		} else {
			print "crétin de m3u évité\n";
		}
	} else {
		$page = $response->content;
	}
	if (!$page) {
		print STDERR "could not get $url\n";
	} elsif ($page =~ /^\#EXTM3U/) {
		# m3u, on interprête d'après le contenu et pas l'extension
		while ($page =~ s/(.+?)[\n\r]//) {
			$_ = $1;
			next if (/^\#/);
			return $_ if (/^http/);
		}
		print "could not find url in m3u $page from $url\n";
		exit(1);
	} elsif ($page =~ /^\[playlist/) {
		while ($page =~ s/(.+?)[\n\r]//) {
			$_ = $1;
			return $1 if (/^File\d*\=(http.+)/);
		}
		print "pls impossible à traiter $page from $url\n";
		exit(1);
	} elsif ($page =~ /"(mms.+?)"/) {
		print "mms url : $1 from $url\n";
		return $1;
	} else {
		open(F,">dump");
		print F $page;
		close(F);
		while ($page =~ s/iframe src\="(.+?)"//m) {
			print "trying iframe $1\n";
			my $r = get_mms($1);
			return $r if ($r);
		}
		print "did not find mms from $url\n";
		return undef;
	}
	return $url;
}

1;

