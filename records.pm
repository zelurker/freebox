package records;
#
#===============================================================================
#
#         FILE: records.pm
#
#  DESCRIPTION:
#
#        FILES: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Emmanuel Anne (), emmanuel.anne@gmail.com
# ORGANIZATION:
#      VERSION: 1.0
#      CREATED: 05/02/2014 15:16:05
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use Fcntl;
use Socket;
use out;

our @records; # 1 seule instance, à priori + simple d'avoir ça en global

sub dateheure {
	# Affiche une date à partir d'un champ time()
	$_ = shift;
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime($_);
	sprintf("%d/%d/%d %d:%02d",$mday,$mon+1,$year+1900,$hour,$min);
}

sub handle {
	my ($p,$time) = @_;
	my $finished = 0;
	return if (!@records);
	for (my $n=0; $n<=$#records; $n++) {
		if ($time > $records[$n][1]) {
			print "enregistrement expiré (de ",dateheure($records[$n][0])," à ",dateheure($records[$n][1]),")\n";
			splice @records,$n,1;
			$p->save_recordings();
			last if ($n > $#records);
			redo;
		}
	}

	foreach (@records) {

		if ($time >= $$_[0] && !$$_[8]) {
			# Début d'un enregistrement
			my $audio2 = $$_[4];
			my $name = $$_[7];
			if ($audio2) {
				open(G,">$name.audio");
				print G $audio2;
				close(G);
			}
			my $service = $$_[2];
			my $flavour = $$_[3];
			my $tab = $_;
			print "début enregistrement ",dateheure($$tab[0])," à ",dateheure($$tab[1])," src $$tab[6]\n";
			$_ = $tab;
			if ($$_[6] =~ /(freebox|dvb)/) {
				my $pid = fork();
				if ($pid == 0) {
					# Ce crétin de mplayer a un port par défaut pour le rtsp et
					# ne vérifie rien.  Ou plutôt si, mais seulement une fois
					# que l' ouverture a foiré, du coup dumpstream ne marche
					# pas sans -rtsp-port quand on a une autre cxion rtsp
					# active. Donc faut trouver le 1er port libre,
					# on commence à 9000.
					if ($$_[6] =~ /freebox/) {
						my $proto = getprotobyname('tcp');
						socket(Server, PF_INET, SOCK_STREAM, $proto) || die "socket $!";
						setsockopt(Server, SOL_SOCKET, SO_REUSEADDR,pack("l", 1));
						my $port = 9000;
						while (!bind(Server, sockaddr_in($port, INADDR_ANY))) {
							print "port $port in use\n";
							$port++;
						}
						print "port $port libre\n";
						close(Server);
						print "enregistrement freebox: exec('mplayer', '-rtsp-port',$port,'-dumpfile',$name,'-really-quiet', '-dumpstream','rtsp://mafreebox.freebox.fr/fbxtv_pub/stream?namespace=1&service=$service&flavour=$flavour')\n";
						exec("mplayer", "-rtsp-port",$port,"-dumpfile",$name,"-really-quiet", "-dumpstream","rtsp://mafreebox.freebox.fr/fbxtv_pub/stream?namespace=1&service=$service&flavour=$flavour");
					} else {
						# if ($$_[6] eq "dvb") {
						print "Enregistrement dvb: exec('mplayer', '-dumpfile',$name,'-really-quiet', '-dumpstream','dvb://$service')\n";
						exec("mplayer", "-dumpfile",$name,"-really-quiet", "-dumpstream","dvb://$service");
					}
				} else {
					push @$_,$pid;
					$p->save_recordings();
					print "pid to kill $$_[8]\n";
				}
			}
		} elsif ($time >= $$_[1] && $$_[8]) {
			print "kill pid $$_[8]\n";
			kill 15,$$_[8];
			$$_[8] = $$_[0] = $$_[1] = 0;
			$finished = 1;
		}
	}
	if ($finished) {
		for (my $n=0; $n<=$#records; $n++) {
			if ($records[$n][0] == 0 && $records[$n][8] == 0) {
				splice @records,$n,1;
				last if ($n > $#records);
				redo;
			}
		}
		$p->save_recordings();
	}
}

sub save_recordings {
	my $p = shift;
	open(F,">recordings");
	foreach (@{$p->{tab}}) {
		print F join(",",@$_),"\n";
	}
	close(F);
}

sub new {
	my $self  = shift;
	@records = ();
	if (open(F,"<recordings")) {
		while (<F>) {
			chomp;
			push @records,[split(/\,/)];
		}
		close(F);
	}
	my $class = ref($self) || $self;
	return bless {
	 tab => \@records,
	}, $class;
}

sub get_delay {
	my ($p,$time,$delay) = @_;
	foreach (@records) {
		if ($$_[0] > $time && (!$delay || $$_[0] < $delay)) {
			$delay = $$_[0];
			# print "info: delay début enreg : ",get_time($delay),"\n";
		}
		if ($$_[1] > $time && (!$delay || $$_[1] < $delay)) {
			$delay = $$_[1];
			# print "info: delay fin enreg : ",get_time($delay),"\n";
		}
	}
	$delay;
}

sub add {
	my ($p,$lastprog) = @_;
	my $cmd = out::send_list("info ".lc($$lastprog[1]));
	my ($src,$num,$name,$service,$flavour,$audio,$video) = split(/\,/,$cmd);
	my $base;
	($src,$base) = split(/\//,$src);
	print "enreg: info returned $src,$num,$name,$service,$flavour,$audio,$video\n";
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime($$lastprog[3]);
	my $file = "records/".sprintf("%d%02d%02d %02d%02d%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec)." $$lastprog[1].ts";
	my $delay = `zenity --entry --entry-text=0 --text="Delai supplémentaire avant et après en minutes"`;
	chomp $delay;
	$delay = 0 if (!$delay);
	$delay *= 60;
	my $added = undef;
	foreach (@records) {
		if ($$_[1] >= $$lastprog[3]-$delay && $service eq $$_[2] &&
			$src eq $$_[6]) {
			# fusion
			$$_[1] = $$lastprog[4]+$delay;
			$added = 1;
			last;
		}
	}
	if (!$added) {
		my @cur = ($$lastprog[3]-$delay,$$lastprog[4]+$delay,$service,$flavour,$audio,$video,$src,$file);
		print "info pour enregistrement : ",dateheure($$lastprog[3])," ",dateheure($$lastprog[4])," ",$$lastprog[1]," serv $service flav $flavour audio $audio video $video src $src\n";
		push @records,\@cur;
		@records = sort { $$a[0] <=> $$b[0] } @records;
		open(F,">$file.info");
		print F ($$lastprog[9] ? "pic:$$lastprog[9] " : "");
		print F $$lastprog[2],"\n"; # title
		print F $$lastprog[1],"\n"; # channel name = subtitle
		print F $$lastprog[6],"\n"; # description
		print F $$lastprog[7],"\n"; # details
		close(F);
	}
	$p->save_recordings();
	mkdir "records" if (! -d "records");
}

1;
