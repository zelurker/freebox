#!/usr/bin/perl

# ATTENTION : ce fichier doit rester en latin1, encodage utilis� par les
# programmes t�l�

use strict;
use Fcntl;
use Socket;
use POSIX qw(SIGALRM);

sub send_command {
	my $cmd = shift;
	if (sysopen(F,"fifo_cmd",O_WRONLY|O_NONBLOCK)) {
		print "send_command : $cmd\n";
		print F $cmd;
		close(F);
	}
}

sub have_net {
	my $net = 1;
	eval {
		POSIX::sigaction(SIGALRM,
			POSIX::SigAction->new(sub { die "alarm" }))
			or die "Error setting SIGALRM handler: $!\n";
		alarm(3);
		my @addresses = gethostbyname("www.google.fr")   or die "Can't resolve : $!\n";
	};
	alarm(0);
	$net = 0 if ($@);
	$net;
}

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
		print "trouv� la socket � $tries essais\n";
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
			my $f = open_bmovl();
			if ($f) {
				print $f "ALPHA $coords $i\n";
				close($f);
			}
		}
		my $f = open_bmovl();
		if ($f) {
			print $f "ALPHA $coords $stop\n";
			close($f);
		}
		my $f = open_bmovl();
		# le clear est pour l'affichage direct quand pas de mplayer
		if ($f) {
			print $f "CLEAR $coords\n";
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
		"i>TELE" => "iT�l�",
		"i> TELE" => "iT�l�",
		"TV5 Monde" => "TV5MONDE",
		"France �" => "France �",
		"france o" => "France �",
		"DirectStar" => "Direct Star",
		"T�l�nantes Nantes 7" => "Nantes 7",
		"NRJ12" => "NRJ 12",
		"LCP" => "La cha�ne parlementaire",
		"Onzeo" => "Onz�o",
		"TEVA" => "T�va",
		"Equidia live" => "Equidia",
		"Luxe.TV" => "Luxe TV",
	);
	$channel =~ s/ \(bas d�bit\)//;
	$channel =~ s/ hd$//i;
	$channel =~ s/ sat$//i;
	$channel =~ s/^T�l�nantes //;
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
	$source =~ s/\/.+//;
	my ($width,$height);
	my $out;
	if ($source eq "flux") {
		my $tries = 3;
		my $error;
		$width = 0;
		do {
			# Pur�e c'est vraiment la course quand on lance tout, on arrive �
			# se retrouver ici avant que la fenetre graphique ne soit cr��e,
			# top rapide, vraiment !!!
			if (open(F,"<desktop")) {
				($width,$height) = <F>;
				chomp($width,$height);
				close(F);
				$error = 0;
			} else {
				select(undef,undef,undef,0.5);
				$error = 1;
			}
		} while ($error && $tries--);
	} else {
		# On attend plus video_size
		if (open(F,"<video_size") || open(F,"<desktop")) {
			($width,$height) = <F>;
			chomp $width;
			chomp $height;
			close(F);
		}
	}
	print "info: re�u long $long\n";
	if (!$long) {
		$long = $height*2/3;
	} elsif ($long =~ /^[a-z]/i) {
		$long = "";
	} # else pass long as is...

	# print STDERR "output on pipe width $width height $height\n";
	print "calling $prog fifo $width $height $long\n";
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

