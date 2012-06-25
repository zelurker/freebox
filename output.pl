#!/usr/bin/perl

# ATTENTION : ce fichier doit rester en latin1, encodage utilisé par les
# programmes télé

use strict;
use Fcntl;
use Socket;
use POSIX qw(SIGALRM);

sub send_bmovl {
	my $cmd = shift;
	my $f = open_bmovl();
	if ($f) {
		print $f "$cmd\n";
		close($f);
	}
}

sub send_cmd_fifo($$) {
	my ($fifo,$cmd) = @_;
	my $tries = 1;
	my $error;
	do {
		if (sysopen(F,"$fifo",O_WRONLY|O_NONBLOCK)) {
			$error = 0;
			print F "$cmd\n";
			close(F);
		} else {
			print "filter: send_cmd $fifo $cmd impossible tries=$tries !\n" if ($tries >= 10);
			$error = 1;
			select undef,undef,undef,0.1;
		}

	} while ($error && $tries++ <= 20);
}

sub send_cmd_list($) {
	my $cmd = shift;
	send_cmd_fifo("fifo_list",$cmd);
}

sub send_cmd_info($) {
	my $cmd = shift;
	send_cmd_fifo("fifo_info",$cmd);
}

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
		my @coords = split(/ /,$coords);
		$coords = join(" ",@coords[0..3]);
		print "clear: clear $coords\n";
		send_bmovl("CLEAR $coords");
		unlink("$name");
		if (!-f "list_coords" && !-f "numero_coords" && !-f "info_coords") {
			send_bmovl("HIDE");
			send_bmovl("image");
		}
	}
}

sub alpha {
	my ($name,$start,$stop,$step) = @_;
	if (open(F,"<info_coords")) {
		my $coords = <F>;
		chomp $coords;
		close(F);
		for(my $i=$start; $i != $stop; $i+=$step) {
			send_bmovl("ALPHA $coords $i");
		}
		send_bmovl("ALPHA $coords $stop");
		# le clear est pour l'affichage direct quand pas de mplayer
		send_bmovl("CLEAR $coords");
	}
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
	# On attend plus video_size
	# En cas d'attente on bloquerait d'autant à chaque commande vers info
	# ou list c'est totalement insupportable. Normalement ce n'est plus
	# nécessaire
	if (open(F,"<video_size") || open(F,"<desktop")) {
		# Si on démarre sur une chaine dvb cryptée, mplayer sort et freebox
		# passe en boucle. Dans ce cas là on obtient jamais video_size, donc
		# on se rabat sur desktop, la taille de la fenêtre de fond, ça tombe
		# bien...
		($width,$height) = <F>;
		chomp $width;
		chomp $height;
		close(F);
	}
	if (!$long) {
		$long = $height*2/3;
	} elsif ($long =~ /^[a-z]/i) {
		$long = "";
	} # else pass long as is...

	# print STDERR "output on pipe width $width height $height\n";
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

1;

