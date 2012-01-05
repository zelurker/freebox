#!/usr/bin/perl

# ATTENTION : ce fichier doit rester en latin1, encodage utilisé par les
# programmes télé

use strict;
use Fcntl;
use Socket;
use Image::Info qw(image_info dim);

sub open_bmovl {
	my $out;
	socket($out, PF_UNIX, SOCK_STREAM, 0)       || die "socket: $!";
	my $tries = 20;
	while (! -S "sock_bmovl" && $tries) {
		$tries--;
		sleep(1);
	}
	if (! -S "sock_bmovl") {
		print "open_bmovl: toujours pas de socket, on sort !\n";
		return undef;
	} elsif ($tries < 20) {
		print "trouvé la socket à $tries essais\n";
	}

	connect($out, sockaddr_un("sock_bmovl"))     || die "connect: $!";
	$out;
}

sub close_fifo {
	my $out = shift;
	close($out);
}

sub clear($) {
	my $name = shift;
	if (open(F,"<$name")) {
		my $coords = <F>;
		chomp $coords;
		close(F);
		my $f = open_bmovl();
		if ($f) {
			print $f "CLEAR $coords\n";
			close($f);
		}
		unlink("$name");
	}
}

sub alpha {
	my ($name,$start,$stop,$step) = @_;
	if (open(F,"<info_coords")) {
		my $coords = <F>;
		chomp $coords;
		close(F);
		for(my $i=$start; $i != $stop; $i+=$step) {
			print "alpha $coords $i\n";
			my $f = open_bmovl();
			if ($f) {
				print $f "ALPHA $coords $i\n";
				close($f);
			}
		}
		print "et final alpha $coords $stop\n";
		my $f = open_bmovl();
		if ($f) {
			print $f "ALPHA $coords $stop\n";
			close($f);
		}
	}
}

sub conv_channel {
	my $channel = shift;
	my %corresp =
	(
		"RTL9" => "RTL 9",
		"Luxe.TV" => "Luxe TV",
		"AB 1" => "AB1",
		"IDF 1" => "IDF1",
		"i>TELE" => "iTélé",
		"TV5 Monde" => "TV5MONDE",
		"France ô" => "France Ô",
		"france o" => "France Ô",
		"DirectStar" => "Direct Star",
		"Télénantes Nantes 7" => "Nantes 7",
		"NRJ12" => "NRJ 12",
		"LCP" => "La chaîne parlementaire",
		"Onzeo" => "Onzéo",
		"TEVA" => "Téva",
	);
	$channel =~ s/\(bas débit\)//;
	$channel =~ s/hd$//i;
	$channel =~ s/ *$//;
	foreach (keys %corresp) {
		if (lc($_) eq $channel) {
			return  lc($corresp{$_});
		}
	}
	return lc($channel);
}

sub setup_output {
	my ($prog,$pic,$long) = @_;
	@_ = ();
	if (open(F,"<current")) {
		@_ = <F>;
		close(F);
	}
	my ($chan,$source,$serv,$flav) = @_;
	chomp $source;
	my ($width,$height);
	my $out;
	if ($source eq "flux") {
		$width = 640; $height = 480;
		if (open(F,"<desktop")) {
			($width,$height) = <F>;
			chomp($width,$height);
			close(F);
		}
	} else {
		# On attend plus video_size
		if (open(F,"<video_size") || open(F,"<desktop")) {
			($width,$height) = <F>;
			chomp $width;
			chomp $height;
			close(F);
		}
	}
	if ($pic) { #  && $width < 720) {
        my $info = image_info("picture.jpg");
        my($w, $h) = dim($info);
		my $div = 0;
		if ($w/2 < $width/2) {
			$div = 2;
		} elsif ($w/3 < $width/2) {
			$div = 3;
		}
		$div = 2 if ($div == 0);
		if ($div > 0) {
			print "on lance convert picture.jpg -geometry ".($w/$div)."x truc.jpg && mv -f truc.jpg picture.jpg\n";
			system("convert picture.jpg -geometry ".($w/$div)."x truc.jpg && mv -f truc.jpg picture.jpg");
		}
	}

	# print STDERR "output on pipe width $width height $height\n";
	if (!$long) {
		$long = $height*2/3;
	} elsif ($long =~ /^[a-z]/i) {
		$long = "";
	} # else pass long as is...
	# print "calling $prog fifo $width $height $long\n";
	if ($width > 100 && $height > 100) {
		$out = open_bmovl();
		print $out "$prog fifo $width $height $long\n" if ($out);
	} else {
		print "*** width $width height $height, on annule bmovl\n";
		$out = *STDERR;
	}
	$out;
}

sub setup_image {
	my ($browser,$url) = @_;
	my $name = "";
	if ($url) {
		($name) = $url =~ /.+\/(.+)/;
#		print STDERR "channel name $name from $url\n";
		$name = "chaines/$name";
		if (! -f $name) {
#			print STDERR "no channel logo, trying to get it from web\n";
			my $response = $browser->get($url);

			if ($response->is_success) {
				open(F,">$name") || die "can't create channel logo $name\n";
				print F $response->content;
				close(F);
			} else {
#				print STDERR "could not get logo from $url\n";
				$name = "";
			}
		}
	}
	$name;
}

1;

