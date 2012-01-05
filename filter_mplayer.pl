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
our ($chan,$source,$serv,$flav) = @_;
chomp ($chan,$source,$serv,$flav);
unlink "stream_info";
my ($width,$height) = ();
my $exit = "";
my ($codec,$bitrate);

sub send_cmd_prog {
	my $tries = 1;
	my $error;
	do {

		if (sysopen(F,"fifo_info",O_WRONLY|O_NONBLOCK)) {
			$error = 0;
			print F "prog $chan\n";
			close(F);
			print "filter: commande prog envoyée\n";
		} else {
			print "filter: envoi commande prog from filter impossible tries=$tries !\n";
			$error = 1;
			sleep(1);
		}

	} while ($error && $tries++ < 3);
}

sub update_codec_info() {
	if ($codec && $bitrate) {
		my $info = "";
		if (open(F,"<stream_info")) {
			while (<F>) {
				$info .= $_;
			}
		}
		close(F);
		if (open(F,">stream_info")) {
			print F "$codec $bitrate\n";
			print F $info if ($info);
			close(F);
		} else {
			print "impossible de créer stream_info !\n";
		}
		send_cmd_prog();
	}
}

while (<>) {
	chomp;
	if (/ID_VIDEO_WIDTH=(.+)/) {
		$width = $1;
	} elsif (/ID_VIDEO_HEIGHT=(.+)/) {
		$height = $1;
	} elsif (/ID_AUDIO_CODEC=(.+)/) {
		$codec = $1;
		$codec =~ s/mpg123/mp3/;
		update_codec_info();
	} elsif (/ID_AUDIO_BITRATE=(.+)/ || /^Bitrate\: (.+)/) {
		if ($1) {
			$bitrate = $1;
			$bitrate =~ s/000$/k/;
			update_codec_info();
		}
	} elsif (/(\d+) x (\d+)/ && $width < 300) {
		$width = $1; $height = $2; # fallback here if it fails
	} elsif (/(\d+)x(\d+) =/ && $width < 300) {
		$width = $1; $height = $2; # fallback here if it fails
	} elsif (/ID_(EXIT|SIGNAL)/) {
		$exit .= $_;
	} elsif (/End of file/i) {
		$exit .= $_;
	} elsif (/ICY Info/) {
		my $info = "";
		while (s/([a-z_]+)\=\'(.*?)\'\;//i) {
			my ($name,$val) = ($1,$2);
			if ($name eq "StreamTitle") {
				$info .= "$val ";
			} elsif ($val && $name ne "StreamUrl") {
				$info .= " + $name=\'$val\' ";
			}
		}
		$info =~ s/ *$//;
		if ($info && open(F,">>stream_info")) {
			print F "$info\n";
			close(F);
		}
		system("./info 1 &");
	} elsif (/Starting playback/) {
	    if ($width && $height) {
			open(F,">video_size") || die "can't write to video_size\n";
			print F "$width\n$height\n";
			close(F);
			kill "USR1",$pid;
		}
		send_cmd_prog();
	}
}
kill "USR2",$pid;
open(F,">id") || die "can't write to id\n";
print F "$exit\n";
close(F);
print "filter: exit message : $exit\n";
unlink("video_size","stream_info");

