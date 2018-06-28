#!/usr/bin/perl
package out;

# ATTENTION : ce fichier doit rester en latin1, encodage utilisé par les
# programmes télé

use strict;
use Fcntl;
use Socket;
use POSIX qw(SIGALRM);
use Net::Ping;
use File::Path qw(make_path);
use AnyEvent::Socket;
use Coro::Handle;
use Coro;
use Cwd;
use Encode;
use v5.10;

our $cwd = getcwd();
our $latin = ($ENV{LANG} !~ /UTF/i);

sub send_bmovl {
	my $cmd = shift;
	my $f = open_bmovl();
	if ($f) {
		print $f "$cmd\n";
		close($f);
	}
}

sub send_cmd_fifo {
	my ($fifo,$cmd,$rep) = @_;
	my $tries = 1;
	my $error;
	# Apparemment il ne faut plus forcer l'encode sur les handles Coro... !
	# $cmd = encode(($ENV{LANG} =~ /UTF/ ? "utf-8" : "iso-8859-1") =>"$cmd\012");
	$cmd .= "\012";
	$cmd =~ s/\x{2019}/'/g;
	$cmd =~ s/\x{0153}/oe/g; # bizarre c'est sensé être supporté par perl5...
	if ($fifo =~ /^sock_/ || $fifo =~ /^mpvsocket/) {
		if (!-S "$cwd/$fifo") {
			print "pas de socket $cwd/$fifo, on attend 1s...\n";
			my $tries = 0;
			while ($tries < 20 && !-S "$cwd/$fifo") {
				select undef,undef,undef,0.1;
				$tries++;
			}
			if (!-S "$cwd/$fifo") {
				print "toujours pas\n";
			} else {
				print "ok après ",$tries*0.1,"s\n";
			}
		}
       tcp_connect "unix/", "$cwd/$fifo", sub {
          my ($fh) = @_;
		  binmode $fh,":utf8" if ($fh && !$latin);
		  async {
			  $fh = unblock $fh;
			  if (!$fh) {
				  print "couldn't get unblock from fifo $fifo\n";
			  } else {
				  $fh->print( $cmd);
				  if (defined($rep)) {
					  my $reply = $fh->readline();
					  $rep->put($reply);
				  }
			  }
		  }
       };
	   return;
   } elsif ($fifo =~ s/^direct_//) {
	   print "envoi direct $fifo: $cmd\n";
	   socket(SOCK, PF_UNIX, SOCK_STREAM, 0)     || die "socket: $!";
	   connect(SOCK, sockaddr_un($fifo))   || die "connect: $!";
	   print SOCK $cmd;
	   if (defined($rep)) {
		   my $reply = <SOCK>;
		   $rep->put($reply);
	   }
	   close(SOCK);
	   return;
   }
}

sub send_cmd_list($) {
	my $cmd = shift;
	my $reply = new Coro::Channel;
	send_cmd_fifo("sock_list",$cmd,$reply);
	return $reply->get();
}

sub send_cmd_info($) {
	my $cmd = shift;
	send_cmd_fifo("sock_info",$cmd);
}

sub send_list {
	# envoie une commande à fifo_list et récupère la réponse
	my $cmd = shift;
	my $repl = out::send_cmd_list($cmd);
	print "send_list: sent $cmd, reply $repl\n";
	$repl;
}

sub send_command {
	my $cmd = shift;
	my $fifo = "fifo_cmd";
	if (-e "mpvsocket") {
		$cmd = "cycle $cmd" if ($cmd =~ /^pause/);
		return send_cmd_fifo("mpvsocket",$cmd);
	}
	if (sysopen(F,$fifo,O_WRONLY|O_NONBLOCK)) {
		print "send_command : $cmd\n";
		$cmd .= "\n" if ($cmd !~ /\n/);
		print F $cmd;
		close(F);
	} else {
		print "send_command $cmd failed on open\n";
	}
}

sub have_net {
	my $net = 1;
	eval {
		local $SIG{ALRM} = sub { die "alarm exception" };
		alarm(3);
		my $p = new Net::Ping("tcp",2); # icmp demande root
		# et pour le syn faut attendre explicitement la réponse
		$p->port_number(53); # faut le port en tcp, 53 pour dns
		# On passe l'ip pour éviter une résolution, ils doivent pas changer
		# souvent de toutes façons
		die "plus d'oleane\n" if (!$p->ping("8.8.8.8"));
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

	do {
		eval {
			connect($out, sockaddr_un("sock_bmovl"))     || die "connect: $!";
		};
		if ($@) {
			print "open_bmovl: $@\n";
		}
	} while ($@);
	$out;
}

sub close_fifo {
	my $out = shift;
	close($out);
}

sub clear {
	while (my $name = shift) {
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
}

sub alpha {
	my ($name,$start,$stop,$step) = @_;
	if (open(F,"<info_coords")) {
		my $coords = <F>;
		chomp $coords;
		close(F);
		for(my $i=$start; $i != $stop; $i+=$step) {
			send_bmovl("ALPHA $coords $i");
			cede;
		}
		send_bmovl("ALPHA $coords $stop");
		# le clear est pour l'affichage direct quand pas de mplayer
		send_bmovl("CLEAR $coords");
		unlink("info_coords");
	}
}

sub get_current {
	my $f;
	if (open($f,"<current")) {
		@_ = <$f>;
		close($f);
	}
	foreach (@_) {
		chomp;
		$_ = 0 if (!$_);
		if (/\xc3/ && !$latin) {
			utf8::decode($_);
		}
	}
	@_;
}

sub setup_output {
	my ($prog,$pic,$long) = @_;
	my ($chan,$source,$serv,$flav) = get_current();
	$source =~ s/\/.+//;
	my ($width,$height);
	my $out;
	# On attend plus video_size
	# En cas d'attente on bloquerait d'autant à chaque commande vers info
	# ou list c'est totalement insupportable. Normalement ce n'est plus
	# nécessaire
	while (1) {
		# Par contre on attend au moins l'1 des 2 parce qu'avec coro on
		# arrive souvent là avant que bmovl ne soit prêt !
		if (open(F,"<video_size") || open(F,"<desktop")) {
			# Si on démarre sur une chaine dvb cryptée, mplayer sort et freebox
			# passe en boucle. Dans ce cas là on obtient jamais video_size, donc
			# on se rabat sur desktop, la taille de la fenêtre de fond, ça tombe
			# bien...
			($width,$height) = <F>;
			chomp $width;
			chomp $height;
			close(F);
			last;
		}
		sleep 1;
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

sub have_freebox {
	# Les crétins de chez free ont fait une ip sur le net au lieu de faire
	# une ip locale, et cette ip bloque tout traffic y compris le ping de tout
	# ce qui ne fait pas partie de leur réseau. Ils sont gentils hein ?
	# Le + simple pour tester cette saloperie c'est juste de faire un connect
	# sur le port http.
	# On pourrait utiliser Net::Ping, mais c'est à peine + simple, et si jamais
	# un jour ça change on est mal, c mieux comme ça.
	my $net = 1;
	eval {
		POSIX::sigaction(SIGALRM,
			POSIX::SigAction->new(sub { die "alarm" }))
			or die "Error setting SIGALRM handler: $!\n";
		alarm(2);
		my $remote = "mafreebox.freebox.fr";
		my $port = 80;
		my $iaddr   = inet_aton($remote)       || die "no host: $remote";
		my $paddr   = sockaddr_in($port, $iaddr);
		my $proto   = getprotobyname("tcp");
		socket(SOCK, PF_INET, SOCK_STREAM, $proto)  || die "socket: $!";
		connect(SOCK, $paddr)               || die "connect: $!";
		close(SOCK);
		print "Accès freebox ok !\n";
	};
	alarm(0);
	$net = 0 if ($@);
	$net;
}

sub get_cache($) {
	my $pic = shift;
	my $file;
	if ($pic =~ /^https?\:\/\/(.+\/)(.+)/) {
		# on cache dans nom_du_serveur/path/file c'est le mieux
		my $base = $1;
		$file = $2;
		$base = "cache/$base";
		make_path($base);
		$file = $base.$file;
		print STDERR "cache $file\n";
	} elsif (-f $pic) { # un nom de fichier direct ?
		return $pic;
	} elsif ($pic =~ /.+\/(.+)/) {
		# Par défaut : nom directement dans cache
		$file = "cache/$1";
		print "default pic: $file\n";
	}
	$file;
}

sub setup_server {
	my ($path,$cb) = @_;
	my $server = AnyEvent::Socket::tcp_server("unix/", $path, sub {
			my ($fh) = @_;
			async {
				$fh = unblock $fh;

				my $cmd = $fh->readline ("\012");
				if (defined($cmd)) {
					# Pas de boucle à priori, 1 seule commande avec éventuellement
					# 1 réponse
					chomp $cmd;
					&$cb($fh,$cmd);
					cede;
				}
			};
		}) or Carp::croak "Coro::Debug::new_unix_server($path): $!";
}

1;

