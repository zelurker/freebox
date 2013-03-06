#!/usr/bin/env perl 
#===============================================================================
#
#         FILE: search_radios.pl
#
#        USAGE: ./search_radios.pl  
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
#      CREATED: 06/03/2013 18:22:30
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use WWW::Google::Images;

my $agent = WWW::Google::Images->new(
	server => 'images.google.com',
);

open(my $f,"<flux/stations") || die "lecture stations\n";
while (<$f>) {
	chomp;
	my $station = $_;

	my $result = $agent->search("logo $_".(/radio/i ? "" : " radio"),
	   	limit => 3);

	my $count = 0;
	while (my $image = $result->next()) {
		$count++;
		# print $image->content_url();
		# print $image->context_url();
		my $file = $image->save_content(base => 'image' . $count);
		system("feh $file &");
		print STDERR "$station ? (o/n)\n";
		my $reply = <>;
		chomp $reply;
		next if ($reply ne "o");
		print "\"$station\" => \"",$image->content_url(),"\",\n";
		last;
	}
	<$f>;
}
close($f);



