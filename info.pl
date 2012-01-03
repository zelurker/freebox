#!/usr/bin/perl 

# Commandes supportées 
# prog "nom de la chaine"
# nextprog
# prevprog
# next/prev : fait défiler le bandeau (transmission au serveur C).
# up/down : montre les info pour la chaine suivante/précédente
# zap1 : transmet à list.pl pour zapper

use strict;
use warnings;
use LWP::Simple;
use LWP 5.64;
use POSIX qw(strftime :sys_wait_h);
use Time::Local "timelocal_nocheck","timegm_nocheck";
# use Time::HiRes qw(gettimeofday tv_interval);
use IO::Handle;
use Encode;
use Fcntl;
use Socket;

require HTTP::Cookies;
require "output.pl";

our @cache_pic;
our ($last_prog, $last_chan,$last_long);
our %chaines = ();

mkdir "cache" if (! -d "cache");
mkdir "chaines" if (! -d "chaines");

sub REAPER {
	my $child;
	# loathe SysV: it makes us not only reinstate
	# the handler, but place it after the wait
	$SIG{CHLD} = \&REAPER;
	while (($child = waitpid(-1,WNOHANG)) > 0) {
		print "info: child $child terminated\n";
# 		if (! -f "info_coords") {
# 			print "plus d'info_coords, bye\n";
# 			return;
# 		}
		print "cache_pic : $#cache_pic\n";
		for (my $n=0; $n<=$#cache_pic; $n++) {
			while (!$cache_pic[$n][0]) {
				print "pas encore de pid pour cache_pic $n\n";
				sleep(1);
			}
			if ($child == $cache_pic[$n][0] && $last_chan eq $cache_pic[$n][1]
				&& $last_prog == $cache_pic[$n][2] &&
			   	(!$last_long || $last_long eq $cache_pic[$n][3]) &&
			   	-f "cache/$cache_pic[$n][4]") {
				# L'image est arrivée, réaffiche le bandeau d'info alors
				print "repaer found prog $n / $#cache_pic\n";
				disp_prog($chaines{$last_chan}[$last_prog],$last_long);
				splice @cache_pic,$n,1;
				last if ($n > $#cache_pic);
				redo;
			} else {
				print "n=$n cache_pic $#cache_pic $child == $cache_pic[$n][0] && $last_chan eq $cache_pic[$n][1]
				&& $last_prog == $cache_pic[$n][2] &&
				$last_long eq $cache_pic[$n][3] &&
				-f cache/$cache_pic[$n][4]\n";
			}
		}
	}
}
$SIG{CHLD} = \&REAPER;
$SIG{TERM} = sub { unlink "info_pl.pid";  exit(0); };

#
# Constants
#

my $read_before = undef;
my @records = ();
if (open(F,"<recordings")) {
	while (<F>) {
		chomp;
		push @records,[split(/\,/)];
	}
	close(F);
}

my @def_chan = ("France 2", "France 3", "France 4", "Arte", "TV5MONDE",
"RTL 9", "AB1", "Direct 8", "TMC", "NT1", "NRJ 12", "La Chaîne Parlementaire",
"BFM TV", "France 5", "Direct Star", "NRJ Paris", "Vivolta", "NRJ Hits",
"Game One", "TF1", "M6", "W9", "Canal+", "Equidia", "AB Moteurs",
"France Ô", "Onzéo", "Liberty tv", "Gulli",
);

open(F,">info_pl.pid");
print F "$$\n";
close(F);

my ($sec,$min,$hour,$mday,$mon,$year) = localtime();
my $date = sprintf("%02d/%02d/%d",$mday,$mon+1,$year+1900);
my $site_addr = "guidetv-iphone.telerama.fr";
my $site_prefix = "http://$site_addr/verytv/procedures/";
my $site_img = "http://$site_addr/verytv/procedures/images/";

# init the Web agent
my $useragt = 'Telerama/1.0 CFNetwork/445.6 Darwin/10.0.0d3';
my $browser = LWP::UserAgent->new(keep_alive => 0,
	agent =>$useragt);
$browser->cookie_jar(HTTP::Cookies->new(file => "$ENV{HOME}/.$site_addr.cookie"));
$browser->timeout(10);
$browser->default_header(
	[ 'Accept-Language' => "fr-fr"
		#                          'Accept-Encoding' => "gzip,deflate",
		# 'Accept-Charset' => "ISO-8859-15,utf-8"
	]
);
# channel icons
# just look for "icones de chaines de television" on google, wikipedia is
# very good at it. Here are some, there are more...
my %icons = (
	1 => "http://upload.wikimedia.org/wikipedia/fr/thumb/8/85/TF1.svg/277px-TF1.svg.png",
	2 => "http://upload.wikimedia.org/wikipedia/fr/thumb/9/97/France2.svg/71px-France2.svg.png",
	3 => "http://upload.wikimedia.org/wikipedia/fr/thumb/d/d7/France3.svg/70px-France3.svg.png",
	4 => "http://upload.wikimedia.org/wikipedia/commons/thumb/1/1a/Canal%2B.svg/500px-Canal%2B.svg.png",
	5 => "http://upload.wikimedia.org/wikipedia/fr/thumb/a/a2/France5.svg/71px-France5.svg.png",
	6 => "http://upload.wikimedia.org/wikipedia/fr/thumb/2/26/Logo-M6.svg/120px-Logo-M6.svg.png",
	7 => "http://upload.wikimedia.org/wikipedia/fr/thumb/7/7e/ARTE_logo_1989.png/120px-ARTE_logo_1989.png",
	8 => "http://upload.wikimedia.org/wikipedia/fr/thumb/b/b8/Direct8-2010.svg/800px-Direct8-2010.svg.png",
	9 => "http://upload.wikimedia.org/wikipedia/fr/8/86/W9_2010.png",
	10 => "http://upload.wikimedia.org/wikipedia/fr/thumb/2/2e/TMC_new.svg/218px-TMC_new.svg.png",
	11 => "http://upload.wikimedia.org/wikipedia/fr/b/bc/NT1_logo2008.png",
	12 => "http://upload.wikimedia.org/wikipedia/fr/e/ea/NRJ12.png",
	13 => "http://upload.wikimedia.org/wikipedia/fr/thumb/0/0c/Logo_France_4.svg/346px-Logo_France_4.svg.png",
	14 => "http://upload.wikimedia.org/wikipedia/en/thumb/a/a8/LCP-Public_Senat.png/200px-LCP-Public_Senat.png",
	15 => "http://upload.wikimedia.org/wikipedia/fr/thumb/d/d4/BFM_TV_2004.jpg/120px-BFM_TV_2004.jpg",
	16 => "http://upload.wikimedia.org/wikipedia/fr/thumb/6/6e/I-tele_2008_logo.svg/78px-I-tele_2008_logo.svg.png",
	17 => "http://upload.wikimedia.org/wikipedia/fr/a/a6/Direct_Star_logo.png",
	18 => "http://upload.wikimedia.org/wikipedia/en/thumb/a/a1/Gulli_Logo.png/200px-Gulli_Logo.png",
	20 => "http://upload.wikimedia.org/wikipedia/fr/8/86/13rue.gif",
	23 => "http://upload.wikimedia.org/wikipedia/commons/8/8f/Logo_AB1_2011.gif",
	26 => "http://upload.wikimedia.org/wikipedia/fr/7/7e/ACTION_1996.gif",
	27 => "http://upload.wikimedia.org/wikipedia/fr/thumb/3/39/AB_Moteurs_logo.svg/545px-AB_Moteurs_logo.svg.png",
	29 => "http://upload.wikimedia.org/wikipedia/fr/5/59/ANIMAUX_1998_BIG.gif",
	70 => "http://upload.wikimedia.org/wikipedia/fr/thumb/5/52/Demain_TV.jpg/120px-Demain_TV.jpg",
	83 => "http://upload.wikimedia.org/wikipedia/fr/thumb/3/33/%C3%89quidia_Logo.svg/513px-%C3%89quidia_Logo.svg.png",
	84 => "http://upload.wikimedia.org/wikipedia/fr/thumb/c/c2/ESCALES_2003.jpg/120px-ESCALES_2003.jpg",
	87 => "http://upload.wikimedia.org/wikipedia/fr/thumb/9/9e/EuroNews.png/150px-EuroNews.png",
	89 => "http://upload.wikimedia.org/wikipedia/fr/thumb/4/49/Eurosport_logo.svg/180px-Eurosport_logo.svg.png",
	119 => "http://upload.wikimedia.org/wikipedia/fr/thumb/8/8a/France_%C3%94_logo_2008.svg/347px-France_%C3%94_logo_2008.svg.png",
	120 => "http://upload.wikimedia.org/wikipedia/fr/6/6e/Funtv.gif",
	121 => "http://upload.wikimedia.org/wikipedia/fr/thumb/4/41/Logo_Game_One_2006.svg/735px-Logo_Game_One_2006.svg.png",
	135 => "http://upload.wikimedia.org/wikipedia/fr/thumb/8/8b/LIBERTY_TV_2005.jpg/120px-LIBERTY_TV_2005.jpg",
	142 => "http://upload.wikimedia.org/wikipedia/fr/4/46/Mangas_Logo.png",
	166 => "http://upload.wikimedia.org/wikipedia/fr/8/84/Nantes7.gif",
	173 => "http://upload.wikimedia.org/wikipedia/fr/0/0c/Logo_NRJ_Hits.jpg",
	174 => "http://upload.wikimedia.org/wikipedia/fr/a/ac/Logo_NRJ_Paris.gif",
	186 => "http://upload.wikimedia.org/wikipedia/fr/thumb/0/0b/Paris_premi%C3%A8re_1997_logo.svg/150px-Paris_premi%C3%A8re_1997_logo.svg.png",
	199 => "http://upload.wikimedia.org/wikipedia/fr/thumb/9/9a/RTL9logo.png/120px-RTL9logo.png",
	206 => "http://upload.wikimedia.org/wikipedia/fr/thumb/d/dc/Tcm.jpg/150px-Tcm.jpg",
	230 => "http://upload.wikimedia.org/wikipedia/en/thumb/1/1d/PokerChannelEuropeLogo.gif/150px-PokerChannelEuropeLogo.gif",
	237 => "http://upload.wikimedia.org/wikipedia/fr/3/3d/TV5Monde_Logo.svg",
	245 => "http://upload.wikimedia.org/wikipedia/fr/c/c1/Logo_TV_Tours.gif",
	259 => "http://upload.wikimedia.org/wikipedia/en/thumb/9/95/Luxe_TV.png/200px-Luxe_TV.png",
	268 => "http://upload.wikimedia.org/wikipedia/fr/thumb/2/21/Fashiontv.gif/250px-Fashiontv.gif",
	288 => "http://upload.wikimedia.org/wikipedia/fr/thumb/c/ce/FRANCE24.svg/100px-FRANCE24.svg.png",
	294 => "http://upload.wikimedia.org/wikipedia/fr/thumb/6/67/IDF1.png/100px-IDF1.png",
	1500 => "http://upload.wikimedia.org/wikipedia/fr/thumb/3/3f/Logo_nolife.svg/208px-Logo_nolife.svg.png",
);

sub myget {
	# un get avec cache
	my $url = shift;
	my $name = $url;
	my $raw = undef;
	$name =~ s/^.+\///;
	if (-f "cache/$name") {
		my $size = -s "cache/$name";
		utime(undef,undef,"cache/$name");
		open(F,"<cache/$name");
		sysread F,$raw,$size;
		close(F);
	} else {
		print "cache: geting $url\n";
		my $pid = fork();
		if ($pid) {
			push @cache_pic,[$pid,$last_chan,$last_prog,$last_long,$name];
		} else {
			$raw = get $url || print STDERR "can't get image $name\n";
			if ($raw) {
				if (open(F,">cache/$name")) {
					syswrite(F,$raw,length($raw));
					close(F);
				}
			}
			exit(0);
		}
	}
	$raw;
}

sub dateheure {
	my $_ = shift;
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime($_);
	sprintf("%d/%d/%d %d:%02d",$mday,$mon+1,$year+1900,$hour,$min);
}

sub debug {
	my $msg = shift;
	while ($_ = shift) {
		$msg .= " ".dateheure($_);
	}
	print "$msg\n";
}

sub get_time {
	my $time = shift;
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime($time);
	# sprintf("%d/%02d/%02d %02d:%02d:%02d $tz",$year+1900,$mon,$mday,$hour,$min,$sec);
	sprintf("%02d:%02d:%02d",$hour,$min,$sec);
}

sub update_noair {
	print STDERR "updating noair...\n";
	my $xml = get "http://www.nolife-tv.com/noair/noair.xml";
	rename "air.xml", "air0.xml";
	open(F,">air.xml");
	print F $xml;
	close(F);
}

sub get_nolife {
	sub conv_date {
		my $date = shift;
		my ($a,$mois,$j,$h,$m,$s) = $date =~ /^(....).(..).(..) (..).(..).(..)/;
		$a -= 1900;
		$mois--;
		timegm_nocheck($s,$m,$h,$j,$mois,$a);
	}

	sub get_date {
		my $time = shift;
		my ($sec,$min,$hour,$mday,$mon,$year) = localtime($time);
		sprintf("%d%02d%02d",$year+1900,$mon,$mday);
	}

	sub get_field {
		my ($line,$field) = @_;
		$line =~ /$field\=\"(.*?)\"/;
		$1;
	}

	my $rtab = shift;

	if (!open(F,"<air.xml")) {
		update_noair();
		die "can't get noair listing\n" if (!open(F,"<air.xml"));
	}

	my $xml = "";
	while (<F>) {
		$xml .= $_;
	}
	close(F);
	Encode::from_to($xml, "utf-8", "iso-8859-15");
	$xml =~ s/½/oe/g;
	$xml =~ s/\&quot\;/\"/g;
	$xml =~ s/\&amp\;/\&/g;

	my ($title,$start,$old_title,$sub,$desc,$old_sub,$old_shot,$shot,
	$old_cat,$cat);
	my $date;
	my $cut_date = undef;
	$cut_date = $$rtab[0][3] if ($rtab);
	foreach (split /\n/,$xml) {
		next if (!/\<slot/);

		$date = conv_date(get_field($_,"dateUTC"));
		# print get_time($date)," ",$_->{title},"\n";
		$start = $date if (!$start);
		if ($cut_date) {
			if ($start > $cut_date) {
				# Des fois nolife corrige ses programmes, le nouveau qui arrive a
				# priorité dans ce cas là
				my $n;
				for ($n=0; $n<=$#$rtab; $n++) {
					last if ($$rtab[$n][3] >= $start);
				}
				splice @$rtab,$n if ($n < $#$rtab);
			}
			$cut_date = undef;
		}

		$old_title = $title;
		$old_sub = $sub;
		$old_shot = $shot;
		$old_cat = $cat;
		$title = get_field($_,"title");
		$sub = get_field($_,"sub-title");
		$title = $sub if (!$title);
		$shot = get_field($_,"screenshot");
		if ($title eq $old_title && !$shot) {
			$shot = $old_shot; # On garde l'image si le titre ne change pas
		}
		$cat = get_field($_,"type");
		if ($start && $old_title && $old_title ne $title) {
			my @tab = (1500, "Nolife", $old_title, $start, $date, $old_cat,
				$desc,"","",$old_shot,0,0,get_date($start));
			push @$rtab,\@tab;
			$start = $date;
			$desc = "";
		}
		my $d = get_field($_,"description");
		if ($d ne $title) {
			$desc .= "\n" if ($desc);
			$desc .= "$d";
			my $d = get_field($_,"detail");
			$desc .= " $d" if ($d);
		}
	}
	# Test le dernier programme !
	my @tab = (1500, "Nolife", $old_title, $start, $date, $old_cat,
		$desc,"","",$old_shot,0,0,get_date($start));
	push @$rtab,\@tab;
	$rtab;
}

#
# Parameters
#

my $channels_text = getListeChaines();
my @chan = split(/\:\$\$\$\:/,$channels_text);
my $sel = "";
foreach (@def_chan) {
	s/\+/\\+/g;
	my $found = 0;
	for (my $n=0; $n<=$#chan; $n++) {
		my ($num,$name) = split(/\$\$\$/,$chan[$n]);
		if ($name =~ /^$_$/i) {
			$sel .= ",$num";
			$found = 1;
			last;
		}
	}
	if (!$found) {
		print "didn't find default channel $_ in list $channels_text\n";
		exit(0);
	}
}
$sel =~ s/^\,//;

my @selected_channels = split(/,/,$sel);

#
# Get channels/programs
#
my $program_text = "";

my %selected_channel;
foreach (@selected_channels) {
	$selected_channel{$_} = 1;
}

my $reread = 0;
my $old_nolife = undef;
my ($channel,$long);
read_prg: $program_text = getListeProgrammes(0) if (!$program_text);
my $nb_days = 1;
my $cmd;
debut: $program_text =~ s/(:\$CH\$:|;\$\$\$;)//g; # on se fiche de ce sparateur !
my @fields = split(/\:\$\$\$\:/,$program_text);

my $date_offset = 0;
# Les collisions : je laisse ce code qui fait des stats sur leur nombre et
# le temps que ça prend à traiter. En fait on obtient de l'ordre de 1200
# collisions pour une seule journée, mais ça prend moins de 2s à récupérer, et
# moins d'1s à convertir dans un format utilisable en interne. Résultat ça
# serait probablement + long de faire 1 requète par chaine pour éviter les
# collisions. Tant pis pour eux, peut-être qu'un jour ils corrigeront leur
# code qui fait toutes ces collisions !
my $nb_collision = 0;
foreach (@fields) {
	my @sub = split(/\$\$\$/);
	my $chan = lc($sub[1]);
	if (!$date_offset || $sub[12] ne $date) {
		$date = $sub[12];
		($mday,$mon,$year) = split(/\//,$sub[12]);
		$mon--;
		$year -= 1900;
		$date_offset = timelocal_nocheck(0,0,0,$mday,$mon,$year);
	}
	($hour,$min,$sec) = split(/\:/,$sub[3]);
	my $start = $date_offset + $sec + 60*$min + 3600*$hour;
	($hour,$min,$sec) = split(/\:/,$sub[4]);
	my $end = $date_offset + $sec + 60*$min + 3600*$hour;
	$end += 3600*24 if ($end < $start); # stupid
	$sub[3] = $start; $sub[4] = $end;
	my $rtab = $chaines{$chan};
	if ($rtab) {
		my $colision = undef;
		foreach (@$rtab) {
			if ($$_[3] == $start && $$_[4] == $end) {
				$colision = $_;
				last;
			}
		}
		if ($colision) {
			# Le nombre de colisions est hallucinant !
			# un vrai gaspillage de bande passante leur truc !
			# print "colision chaine $$colision[1] titre $$colision[2]\n";
			$nb_collision++;
		} else {
			push @$rtab,\@sub;
		}
	} else {
		$chaines{$chan} = [\@sub];
	}
}
print scalar localtime," fin traitement fichier, $nb_collision collisions\n";
$chaines{"nolife"} = get_nolife($chaines{"nolife"});
print scalar localtime," fin traitement nolife\n";

my $last_hour = 0;

system("rm -f fifo_info && mkfifo fifo_info");
my $start_timer = 0;
read_fifo:
($channel,$long) = () if (!$reread);
# my $timer_start;
my $time;

sub disp_prog {
	my ($sub,$long) = @_;
	my $start = $$sub[3];
	my $end = $$sub[4];
	$start = get_time($start);
	$end = get_time($end);
	my $raw = 0;
	if ($$sub[9]) {
		# Prsence d'une image...
		if ($$sub[9] !~ /^http/) {
			my @date = split('/', $$sub[12]);
			my @time = split(':', $start);
			my $img = $date[2]."-".$date[1]."-".$date[0]."_".$$sub[0]."_".$time[0].":".$time[1].".jpg";
			$raw = myget $site_img.$img;
		} else {
			my $name = $$sub[9];
			$name =~ s/^.+\///;

			$raw = myget $$sub[9]; 
		}
		if ($raw) {
			open(F,">picture.jpg") || die "can't create picture.jpg\n";
			print F $raw;
			close(F);
			$raw = 1;
		}
	}
	# Check channel logo
	my $url = $icons{$$sub[0]};
	my $name = setup_image($browser,$url);

	my $out = setup_output("bmovl-src/bmovl",$raw,$long);

	print $out "$name\n";
	print $out "picture.jpg" if ($raw);

	print $out "\n$$sub[1] : $start - $end\n$$sub[2]\n\n$$sub[6]\n$$sub[7]\n";
	print $out "$$sub[11]\n" if ($$sub[11]); # Critique
	print $out "*"x$$sub[10] if ($$sub[10]); # Etoiles
	close_fifo($out);
}

sub send_list {
	# envoie une commande à fifo_list et récupère la réponse
	my $cmd = shift;
	open(F,">fifo_list");
	print F $cmd;
	close(F);
	$cmd = undef;
	open(F,"<fifo_list") || die "can't read from fifo_list\n";
	while (<F>) {
		chomp;
		$cmd = $_;
	}
	close(F);
	$cmd;
}

sub save_recordings {
	open(F,">recordings");
	foreach (@records) {
		print F join(",",@$_),"\n";
	}
	close(F);
}

sub handle_records {
	my $time = shift;
	my $finished = 0;
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
			print "début enregistrement ",dateheure($$_[0])," à ",dateheure($$_[1])," src $$_[6]\n";
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
					save_recordings();
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
		save_recordings();
	}
}

sub req_prog($$) {
	my ($offset,$url) = @_;
	my $date = strftime("%Y-%m-%d", localtime(time()+(24*3600*$offset)) );
	$url = $site_prefix.'LitProgrammes1JourneeDetail.php?date='.$date.'&chaines='.$url;
	print "req_prog: url $url\n";
	my $response = $browser->get($url);
	die "$url error: ", $response->status_line
	unless $response->is_success;
	$response;
}

if (!$reread || !$channel) {
	if (!$reread) {
		$cmd = "";
		do {
			# Celui là sert à vérifier les déclenchements externes (noair.pl)
			$time = time;
			if (sysopen(F,"fifo_info",O_RDONLY|O_NONBLOCK)) {
				my $delay = undef;
				if ($last_chan && defined($last_prog) && $chaines{$last_chan}) {
					$delay = $chaines{$last_chan}[$last_prog][4];
					$delay = 0 if ($delay == $time);
					print "delay nextprog : ",get_time($delay),"\n";
					if ($delay < $time) {
						# on obtient un delay négatif ici quand nolife n'a pas
						# encore les programmes actuels
						$delay = undef;
					}
				}
				if ($start_timer && $start_timer <= $time) {
					# start_timer peut se retrouver en anomalie comme ici
					# si l'un des cadres change de status avant qu'il soit à 0
					# dans ce cas on le remet à 0 ici.
					$start_timer = 0;
				}

				if ($start_timer && # $start_timer > $time && 
					(!$delay || $start_timer < $delay)) {
					$delay = $start_timer;
					print "delay start_timer : ",get_time($delay),"\n";
				}
				if (-f "list_coords") {
					$delay = $time+3;
				}
				foreach (@records) {
					if ($$_[0] > $time && (!$delay || $$_[0] < $delay)) {
						$delay = $$_[0];
						print "delay début enreg : ",get_time($delay),"\n";
					}
					if ($$_[1] > $time && (!$delay || $$_[1] < $delay)) {
						$delay = $$_[1];
						print "delay fin enreg : ",get_time($delay),"\n";
					}
				}
				$delay -= $time if ($delay);

				my $rin = "";
				vec($rin,fileno(F),1) = 1;
				my ($nfound) = select($rin, undef, undef, $delay);
				$time = time;
				if ($last_chan && defined($last_prog) && $chaines{$last_chan} && $time >= $chaines{$last_chan}[$last_prog][4] && $time < $chaines{$last_chan}[$last_prog+1][4]) {
					if (-f "info_coords" && $time - $chaines{$last_chan}[$last_prog+1][3] < 5) {
						print "programme suivant affiché last $last_prog < ",$#{$chaines{$last_chan}},"\n";
						$last_prog++;
						disp_prog($chaines{$last_chan}[$last_prog],$last_long);
					}
				}
				handle_records($time);
				if (-f "list_coords") {
					open(G,">fifo_list") || die "can't talk to fifo_list\n";
					print G "refresh\n";
					close(G);
				}

				if ($nfound > 0) {
					($cmd) = <F>;
					if ($cmd) {
						chomp ($cmd);
						my @tab = split(/ /,$cmd);
						($tab[0],$long) = split(/\:/,$tab[0]);
						$cmd = join(" ",@tab);
					}
				}
				close(F);
			}
			if ($start_timer && $time - $start_timer >= 0 && -f "info_coords" &&
				! -f "list_coords") {
				print "alpha sur start_timer\n";
				alpha("info_coords",-40,-255,-5);
				unlink "info_coords";
				$start_timer = 0;
			}
		} while (!$cmd);
	} else {
		$reread = 0;
	}
	#$timer_start = [gettimeofday];
	$time = time();
	print "info: reçu cmd $cmd\n";
	if ($cmd eq "clear") {
		clear("info_coords");
		goto read_fifo;
	} elsif ($cmd eq "nextprog" || $cmd eq "right") {
		my $rtab = $chaines{$last_chan};
		if ($rtab) {
			my $n = $last_prog+1;
			if ($n > $#$rtab) {
				if ($last_chan eq "nolife") {
					print "info: tentative update nolife (right) ",$chaines{"nolife"},"\n";
					my $start = $$rtab[$last_prog][3];
					my $end = $$rtab[$last_prog][4];
					update_noair();
					$rtab = $chaines{"nolife"} = get_nolife($chaines{"nolife"});
					# Les programmes de nolife changent vraiment beaucoup
					# d'un jour à l'autre surtout sur la fin de journée
					# il faut tout réindicer du coup !
					print "recherche ",dateheure($start)," ou ",dateheure($end),"\n";
					for ($n=0; $n<=$#$rtab; $n++) {
						last if ($$rtab[$n][3] >= $start || $$rtab[$n][4] >= $end);
					}
				} else {
					my $date = $$rtab[$#$rtab][12];
					my ($j,$m,$a) = split(/\//,$date);
					$a -= 1900;
					$m--;
					$date = timegm_nocheck(0,0,0,$j,$m,$a)+24*3600;
					my ($sec,$min,$hour,$mday,$mon,$year) = localtime();
					my $d2 = timegm_nocheck(0,0,0,$mday,$mon,$year);
					my $offset = ($date-$d2)/(24*3600);
					print "A récupérer offset $offset\n";
					$program_text .= getListeProgrammes($offset);
					$old_nolife = $chaines{"nolife"};
					$reread = 1; # On récupère l'ancienne commande...
					goto debut;
				}
				$n-- if ($n > $#$rtab);
			}
			$last_prog = $n;
			disp_prog($$rtab[$n],$last_long);
		} else {
			print "nextprog: did not find last_chan $last_chan\n";
		}
		$start_timer = 0;
		goto read_fifo;
	} elsif ($cmd eq "prevprog" || $cmd eq "left") {
		my $rtab = $chaines{$last_chan};
		if ($rtab) {
			my $n = $last_prog-1;
			$n=0 if ($n < 0);
			disp_prog($$rtab[$n],$last_long);
			$last_prog = $n;
		}
		$start_timer = 0;
		goto read_fifo;
	} elsif ($cmd =~ /^(next|prev)$/) {
	    # Ces commandes sont juste passées à bmovl sans rien changer
	    # mais en passant par ici ça permet de réinitialiser le timeout
	    # de fondu, plutôt pratique...
	    my $f = open_bmovl();
	    print $f "$cmd\n";
	    close($f);
		$start_timer = 0;
	    goto read_fifo;
	} elsif ($cmd =~ /^(up|down)$/) {
		$cmd = send_list(($cmd eq "up" ? "next" : "prev")." $last_chan\n");
		$channel = lc($cmd);
		print "got channel :$channel.\n";
		$long = $last_long;
		$start_timer = time+5 if (!$long);
	} elsif ($cmd eq "zap1") {
		open(F,">fifo_list") || die "can't talk to fifo_list\n";
		print F "zap2 $last_chan\n";
		close(F);
		goto read_fifo;
	} elsif ($cmd =~ s/^prog //) {
		# Note : $long est passé collé à la commande par un :
		# mais il est séparé avant même l'interprêtation, dès la lecture
		$channel = lc($cmd);
		$start_timer = time+5 if (!$long);
	} elsif ($cmd eq "record") {
		my $rtab = $chaines{$last_chan}[$last_prog];
		$cmd = send_list("info ".lc($$rtab[1])."\n");
		my ($src,$num,$name,$service,$flavour,$audio,$video) = split(/\,/,$cmd);
		print "enreg: info returned $src,$num,$name,$service,$flavour,$audio,$video\n";
		my ($sec,$min,$hour,$mday,$mon,$year) = localtime($$rtab[3]);
		my $file = "records/".sprintf("%d%02d%02d %02d%02d%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec)." $$rtab[1].ts";
		my @cur = ($$rtab[3],$$rtab[4],$service,$flavour,$audio,$video,$src,$file);
		print "info pour enregistrement : ",dateheure($$rtab[3])," ",dateheure($$rtab[4])," ",$$rtab[1]," serv $service flav $flavour audio $audio video $video src $src\n";
		push @records,\@cur;
		@records = sort { $$a[0] <=> $$b[0] } @records;
		save_recordings();
		mkdir "records" if (! -d "records");
		goto read_fifo;
	} else {
		print "info: commande inconnue $cmd\n";
		goto read_fifo;
	}

} else {
	$reread = 0;
}  
($sec,$min,$hour,$mday,$mon,$year) = localtime($time);
my $date2 = sprintf("%02d/%02d/%d",$mday,$mon+1,$year+1900);
if ($date2 ne $date) { # changement de date
	print "$date2 != $date -> reread\n";
	$program_text = undef;
	$reread = 1;
	$date = $date2;
	unlink "day-1";
	rename "day0","day-1";
	goto read_prg;
}
chomp $channel;
chomp $long if ($long);
$channel = conv_channel($channel);
# print "lecture from fifo channel $channel long ".($long ? $long : "")." fields $#fields\n";

# print "recherche channel $channel\n";
my $rtab = $chaines{$channel};
if (!$rtab && $channel =~ /^france 3 /) {
	# On a le cas particulier des chaines régionales fr3 & co...
	$rtab = $chaines{"france 3"};
}
if (!$rtab) {
	if (open(F,"<current")) {
		my $name = <F>;
		chomp $name;
		close(F);
		$name = lc($name);
		if ($name eq $channel) {
			if (-f "stream_info") {
				# Là il peut y avoir un problème si une autre source a le même nom
				# de chaine, genre une radio et une chaine de télé qui ont le même
				# nom... Pour l'instant pas d'idée sur comment éviter ça...
				my ($last,$cur);
				if (open(F,"<stream_info")) {
					while (<F>) {
						chomp;
						$last = $cur;
						$cur = $_;
					}
					close(F);
					my $out = setup_output("bmovl-src/bmovl","",0);
					if ($out) {
						print $out "\n\n";
						($sec,$min,$hour) = localtime($time);

						print $out "$cmd : ".sprintf("%02d:%02d:%02d",$hour,$min,$sec),"\n$cur\n";
						print $out "Dernier morceau : $last\n" if ($last);
						close_fifo($out);
					}
					$last_chan = $channel;
					goto read_fifo;
				}
			} else {
				print "stream_info not valid $name et $channel.\n";
			}
		} # $name eq $channel
	} # lecture current
}
if (!$rtab) {
	for (my $n=0; $n<=$#chan; $n++) {
		my ($num,$name) = split(/\$\$\$/,$chan[$n]);
		if ($channel eq $name && $num != 254) {
			my $response = req_prog(0,$num);
			my $res = $response->content;
			if ($res && index($program_text,$res) < 0 && $res =~ /$num/) {
				$program_text .= $res;
				$reread = 1; # On récupère l'ancienne commande...
				print "programme lu à la volée $name ",length($program_text),"\n";
				goto debut;
			} else {
				print "rien pu lire pour $channel $num\n";
				if ($res !~ $num) {
					print "renvoi résultat nul\n";
				} else {
					open(F,">debug");
					print F "$res\n";
					close(F);
					open(F,">debug2");
					print F "$program_text\n";
					close(F);
					print "fichier debug créé, on quitte\n";
					exit(1);
				}
			}
		}
	}
}
if (!$rtab) {
	# Pas trouvé la chaine
	my $out = setup_output("bmovl-src/bmovl","",0);

	print $out "\n\n";
	($sec,$min,$hour) = localtime($time);

	print $out "$cmd : ".sprintf("%02d:%02d:%02d",$hour,$min,$sec),"\nAucune info\n";
	close_fifo($out);
	$last_chan = $channel;
	goto read_fifo;
}

reprise_nolife:
for (my $n=0; $n<=$#$rtab; $n++) {
	my $sub = $$rtab[$n];
	my $start = $$sub[3];
	my $end = $$sub[4];

	if ($start <= $time && $time <= $end) {
		$last_chan = $channel;
		$last_prog = $n;
		$last_long = $long;
		disp_prog($sub,$long);
#			  system("feh picture.jpg &") if ($$sub[9]);
		goto read_fifo;
	}
}
# print "time ",dateheure($time)," start ",dateheure($$rtab[0][3]),"\n";
if ($time < $$rtab[0][3] && !$read_before) {
	print "pas trouvé l'heure ",dateheure($time)," cmp ",dateheure($$rtab[0][3]),", mais on va récupérer le jour d'avant...\n";
	$program_text = getListeProgrammes(-1).$program_text;
	$old_nolife = $chaines{"nolife"};
	$reread = 1; # On récupère l'ancienne commande...
	$read_before = 1;
	goto debut;
}
if ($channel eq "nolife") {
	update_noair();
	$rtab = $chaines{"nolife"} = get_nolife($chaines{"nolife"});
	if ($$rtab[$#$rtab][3] >= $time) {
		print "update noair parfaite\n";
		goto reprise_nolife;
	}
}
my $out = setup_output("bmovl-src/bmovl","",0);

print $out "\n\n";
($sec,$min,$hour) = localtime($time);

print $out "$cmd : ".sprintf("%02d:%02d:%02d",$hour,$min,$sec),"\nPas encore l'info à cette heure\n";
close_fifo($out);
$last_chan = $channel;
goto read_fifo;

#==============================================================================
# Functions
#

# Do http request for a program
sub getListeProgrammes {
  my $offset = shift;
  # date YYYY-MM-DD
  print "utilisation date $mday/",$mon+1,"/",$year+1900,"\n";
  my $d0 = timegm_nocheck(0,0,0,$mday,$mon,$year);
  my $found = undef;
  while (<day*>) {
	  my $name = $_;
	  my $text = "";
	  next if (!open(F,"<$_"));
	  while (<F>) {
		  $text .= $_;
	  }
	  close(F);
	  my @fields = split(/\:\$\$\$\:/,$text);
	  my @sub = split(/\$\$\$/,$fields[0]);
	  my ($j,$m,$a) = split(/\//,$sub[12]);
	  $a -= 1900;
	  $m--;
	  print "comparaison à $sub[12] $mday et $j $mon et $m $year et $a\n";
	  my $d = timegm_nocheck(0,0,0,$j,$m,$a);
	  my $off = ($d-$d0)/(24*3600);
	  print "$name -> $off\n";
	  my $new = "day$off";
	  if ($name ne $new) {
		  if ($off < -1 || -f $new) {
			  unlink $name;
		  } else {
			  rename $name,$new;
		  }
	  }
	  if ($off == $offset) {
		  $found = $text;
	  }
  }
  return $found if ($found);

  my $url = "";
  for (my $i =0 ; $i < @selected_channels ; $i++ ) {
    $url = $url.$selected_channels[$i];
    if ($i < (@selected_channels - 1)) {
      $url = $url.",";
    }
  }
  print scalar localtime," récupération $url\n";

  my $response = req_prog($offset,$url);

  open(F,">day".($offset));
  print F $response->content;
  close(F);
  print scalar localtime," fichier écrit\n";
  return $response->content;
}

sub request {
    my $url = shift;
	my $response = $browser->get($url);

	die "$url error: ", $response->status_line
	unless $response->is_success;

	return $response->content;
}

sub getListeChaines {
	my $r;
	if (!-f "liste_chaines" || -M "liste_chaines" > 30 || -s "liste_chaines" < 512) {
		print "geting liste_chaines from web...\n";
		my $url = $site_prefix."ListeChaines.php";

		$r = request($url);
		if ($r) {
			open(F,">liste_chaines") || die "can't create liste_chaines\n";
			print F $r;
			close(F);
		}
	} else {
		print "using cache for liste_chaines\n";
		open(F,"<liste_chaines") || die "can't read liste_chaines\n";
		while (<F>) {
			$r .= $_;
		}
		close(F);
	}
	return lc($r);
}

