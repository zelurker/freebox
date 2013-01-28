#!/usr/bin/env perl 
#===============================================================================
#
#         FILE: http.pl
#
#        USAGE: ./http.pl  
#
#  DESCRIPTION: Module http pour les plugins
#
#===============================================================================

use strict;
use warnings;
use LWP::UserAgent;
use HTTP::Cookies;

# Un get qui stocke les cookies et tient compte de l'utf dans le content-type
sub myget {
	my $url = shift;
	my $cookie_jar = HTTP::Cookies->new(
           file => "$ENV{'HOME'}/lwp_cookies.dat",
           autosave => 1,
         ); 
	my $ua = LWP::UserAgent->new;
	$ua->timeout(10);
	$ua->cookie_jar($cookie_jar);
	my $r = $ua->get($url);
	my $type = $r->header("Content-type");
	print STDERR "myget: got type $type\n";
	if ($type =~ /charset=(.+)/) {
		print "encoding: $1\n";
	}
	return $r->content;
}

1;

