#!/usr/bin/perl

use strict;
use Fcntl;
require "output.pl";
eval {
	require WWW::Google::Images;
	WWW::Google::Images->import();
};
my $images = 0;
my @cur_images;
if (!$@) {
	# google images dispo si pas d'erreur
	$images = 1;
}
my $titre;
my $last_image;

sub handle_result($) {
	my $result = shift;
	my $image;
	if ($image = $result->next()) {
		open(F,"<desktop");
		my $w = <F>;
		my $h = <F>;
		close(F);
		chomp($w,$h);
		my ($x,$y) = (0,0);
		if (open(F,"<list_coords")) {
			my $coords = <F>;
			my ($aw,$ah,$ax,$ay) = split(/ /,$coords);
			$x = $ax+$aw;
			$y = $ay;
			$w -= $x;
			close(F);
		}
		if (open(F,"<info_coords")) {
			my $coords = <F>;
			my ($aw,$ah,$ax,$ay) = split(/ /,$coords);
			$h = $ay-$y;
			print "info: correction h = $ay - $y = $h\n";
		} else {
			print "info: pas de info_coords pour image\n";
		}

		my $pic = $image->save_content(base => 'image');
		if ($last_image && $pic ne $last_image) {
			unlink $last_image;
		}
		$last_image = $pic;
		print "handle_result : $pic\n";
		if (`file $pic` =~ /gzip/) {
			print "gzip detected\n";
			rename($pic,"$pic.gz");
			system("gunzip $pic.gz");
			print "gunzipped\n";
		}
		my $out = open_bmovl();
		print "info: sending image $x $y $w $h\n";
		print $out "image $pic $x $y $w $h\n";
		close($out);
	} else {
		print "handle_result: plus d'images !\n";
	}
}

sub handle_images($) {
	my $cur = shift;
	if (!@cur_images || $cur_images[0] ne $cur) {
		# Reset de la recherche précédente si pas finie !
		if ($cur_images[1]) {
			print "handle_image: reset vieille recherche\n";
			my $result = $cur_images[1];
			while ($result->next()) {}
		}

		@cur_images = ($cur);
		my $agent = WWW::Google::Images->new(
			server => 'images.google.com',
		);

		print "images: recherche sur $cur\n";
		my $result = $agent->search($cur, limit => 10);
		handle_result($result);
		push @cur_images,$result;
	} else {
		my $result = $cur_images[1];
		handle_result($result);
	}
	alarm(25);
}

$SIG{ALRM} = sub { handle_images($titre); };

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
				$titre = $val;
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
		handle_images($titre);
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

