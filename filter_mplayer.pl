#!/usr/bin/perl

use strict;

my $pid;
open(F,"<info.pid") || die "can't open info.pid !\n";
$pid = <F>;
chomp $pid;
close(F);
my ($width,$height) = ();
my $exit = "";
my $init;
while (<>) {
	chomp;
	if (/ID_VIDEO_WIDTH=(.+)/) {
		$width = $1;
	} elsif (/ID_VIDEO_HEIGHT=(.+)/) {
		$height = $1;
	} elsif (/(\d+) x (\d+)/ && $width < 300) {
		$width = $1; $height = $2; # fallback here if it fails
	} elsif (/(\d+)x(\d+) =/ && $width < 300) {
		$width = $1; $height = $2; # fallback here if it fails
	} elsif (/ID_(EXIT|SIGNAL)/) {
		$exit .= $_;
	} elsif (/End of file/i) {
		$exit .= $_;
	}

	if ($width && $height && !$init) {
		open(F,">video_size") || die "can't write to video_size\n";
		print F "$width\n$height\n";
		close(F);
		kill "USR1",$pid;
		$init = 1;
	}
}
kill "USR2",$pid;
open(F,">id") || die "can't write to id\n";
print F "$exit\n";
close(F);
print "filter: exit message : $exit\n";
unlink "video_size";

