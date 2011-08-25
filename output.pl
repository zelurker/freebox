#!/usr/bin/perl

# ATTENTION : ce fichier doit rester en latin1, encodage utilisé par les
# programmes télé

use strict;
use Fcntl;
use Time::HiRes qw(usleep);

sub open_bmovl {
	my $tries = 0;
	my $ret;
	my $out = undef;
	while ($tries++ < 10 && 
		!($ret = sysopen($out,"fifo_bmovl",O_WRONLY|O_NONBLOCK))) {
		select(undef,undef,undef,0.1);
	}
	if (!$ret) {
		print "open_bmovl: open failed, using stderr\n";
		return *STDERR;
	}
	$out;
}

sub clear($) {
	my $name = shift;
	if (open(F,"<$name")) {
		my $coords = <F>;
		chomp $coords;
		close(F);
		my $f = open_bmovl();
		print $f "CLEAR $coords\n";
		close($f);
		unlink("$name");
	}
}

sub alpha {
	my ($name,$start,$stop,$step) = @_;
	if (open(F,"<info_coords")) {
		my $coords = <F>;
		chomp $coords;
		close(F);
		my $f = open_bmovl();
		for(my $i=$start; $i != $stop; $i+=$step) {
			print $f "ALPHA $coords $i\n";
		}
		close($f);
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
	);
	foreach (keys %corresp) {
		if (lc($_) eq $channel) {
			return  lc($corresp{$_});
		}
	}
	$channel =~ s/\(bas débit\)//;
	$channel =~ s/hd$//i;
	$channel =~ s/ *$//;
	return lc($channel);
}

sub setup_output {
	my ($prog,$pic,$long) = @_;
	my ($width,$height);
	my $out;
	if (-p "fifo") {
		my $tries = 0;
		open(F,"<id") || die "no id file\n";
		do {
			while (<F>) {
				chomp;
				if (/ID_VIDEO_WIDTH=(.+)/) {
					$width = $1;
				} elsif (/ID_VIDEO_HEIGHT=(.+)/) {
					$height = $1;
				} elsif (/(\d+) x (\d+)/ && $width < 300) {
					$width = $1; $height = $2; # fallback here if it fails
				} elsif (/(\d+)x(\d+) =/ && $width < 300) {
					$width = $1; $height = $2; # fallback here if it fails
				}
			}
			usleep(1000) if (!$width || $width < 300);
			seek(F,0,1);
		} while ((!$width || $width < 320) && ++$tries < 3000);
		# print "obtenu $width et $height au bout de $tries\n";
		close(F);
		if ($pic) { #  && $width < 720) {
			open(F,"identify picture.jpg|");
			while (<F>) {
				if (/ (\d+)x(\d+) /) {
					my ($w,$h) = ($1,$2);
					my $div = 0;
					if ($w/2 < $width/2) {
						$div = 2;
					} elsif ($w/3 < $width/2) {
						$div = 3;
					}
					$div = 2 if ($div == 0);
					if ($div > 0) {
						system("convert picture.jpg -geometry ".($w/$div)."x truc.jpg && mv -f truc.jpg picture.jpg");
					}
				}
			}
			close(F);
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
			print $out "$prog fifo $width $height $long\n"
		} else {
			print "*** width $width height $height, on annule bmovl\n";
			$out = *STDERR;
		}
	} else {
		print STDERR "no fifo, output on STDERR\n";
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

