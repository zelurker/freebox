#!/usr/bin/env perl

use strict;
use warnings;

our %bookmarks;
dbmopen %bookmarks,"bookmarks.db",0666;
my $last;
foreach (keys %bookmarks) {
	if (!$bookmarks{$_} || !(-f $_) || /^http/ || /^get,/) {
		print "deleting $_\n";
		delete $bookmarks{$_}
	} else {
		print "$_: $bookmarks{$_} ok\n";
		$last = $_;
	}
}
my %back = %bookmarks;
dbmclose %bookmarks;

print "last : $back{$last}\n";
my @list = <bookmarks.db*>;
unlink @list;

dbmopen %bookmarks,"bookmarks.db",0666;
%bookmarks = %back;
dbmclose %bookmarks;
