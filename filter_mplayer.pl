#!/usr/bin/perl

use strict;
use Fcntl;

my $pid;
open(F,"<info.pid") || die "can't open info.pid !\n";
$pid = <F>;
chomp $pid;
close(F);
if (open(F,"<current")) {
	@_ = <F>;
	close(F);
}
my ($chan,$source,$serv,$flav) = @_;
chomp ($chan,$source,$serv,$flav);
unlink "stream_info";
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
	} elsif (/ICY Info/) {
		print "filter debug : $_\n";
		my $info = "";
		while (s/([a-z_]+)\=\'(.*?)\'\;//i) {
			my ($name,$val) = ($1,$2);
			if ($name eq "StreamTitle") {
				$info .= "$val ";
			} elsif ($val) {
				$info .= " + $name=\'$val\' ";
			}
		}
		$info =~ s/ *$//;
		if ($info && open(F,">>stream_info")) {
			print F "$info\n";
			close(F);
		}
		unlink "info_coords";
		system("./info &");
	}
	if ($width && $height && !$init) {
		open(F,">video_size") || die "can't write to video_size\n";
		print F "$width\n$height\n";
		close(F);
		kill "USR1",$pid;
		$init = 1;
		if (sysopen(F,"fifo_info",O_WRONLY|O_NONBLOCK)) {
			print F "prog $chan\n";
			close(F);
		}
	}
}
kill "USR2",$pid;
open(F,">id") || die "can't write to id\n";
print F "$exit\n";
close(F);
print "filter: exit message : $exit\n";
unlink("video_size","stream_info");

