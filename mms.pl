#!/usr/bin/perl

# Récupération des liens mms ou autres à partir d'une page web

use LWP 5.64;
use strict;

sub get_mms {
	my $url = shift;
	my $useragt = 'Telerama/1.0 CFNetwork/445.6 Darwin/10.0.0d3';
	my $browser = LWP::UserAgent->new(keep_alive => 0,
		agent =>$useragt);
	$browser->timeout(10);
	$browser->default_header(
		[ 'Accept-Language' => "fr-fr"
			#                          'Accept-Encoding' => "gzip,deflate",
			# 'Accept-Charset' => "ISO-8859-15,utf-8"
		]
	);

	$browser->max_size(65000);
	my $response = $browser->get($url);
	return $url if (!$response->is_success);
	return $url if ($response->header("Content-type") !~ /text/);
	my $page = $response->content;
	if (!$page) {
		print STDERR "could not get $url\n";
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

