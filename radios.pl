#!/usr/bin/env perl 
#===============================================================================
#
#         FILE: radios.pl
#
#        USAGE: ./radios.pl  
#
#  DESCRIPTION: 
#
#      OPTIONS: ---
# REQUIREMENTS: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Emmanuel Anne (), emmanuel.anne@gmail.com
# ORGANIZATION: 
#      VERSION: 1.0
#      CREATED: 06/03/2013 00:58:04
#     REVISION: ---
#===============================================================================

use strict;
use warnings;

my %icons = (
	"MFM" => "http://upload.wikimedia.org/wikipedia/fr/b/bb/Logo-mfm.png",
);

sub get_radio_pic {
	my $name = shift;
	my $url = $icons{$name};
	if ($url) {
		($name) = $url =~ /.+\/(.+)/;
#		print STDERR "channel name $name from $url\n";
		$name = "radios/$name";
		if (! -f $name) {
#			print STDERR "no channel logo, trying to get it from web\n";
			my $browser = get_browser();
			my $response = $browser->get($url);

			if ($response->is_success) {
				open(my $f,">$name") || die "can't create channel logo $name\n";
				print $f $response->content;
				close($f);
			} else {
#				print STDERR "could not get logo from $url\n";
				$name = "";
			}
		}
	} else {
		$name = "";
	}
	$name;
}

mkdir "radios" if (!-d "radios");
1;

