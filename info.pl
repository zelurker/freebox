#!/usr/bin/perl -w
#

# Commandes support�es 
# prog "nom de la chaine"
# nextprog
# prevprog
# next/prev : fait d�filer le bandeau (transmission au serveur C).

use strict;
use warnings;
use LWP::Simple;
use LWP 5.64;
use POSIX qw(strftime);
use Time::Local;
# use Time::HiRes qw(gettimeofday tv_interval);
use IO::Handle;

require HTTP::Cookies;
require "output.pl";

#
# Constants
#

my @def_chan = ("France 2", "France 3", "France 4", "Arte", "TV5MONDE",
"RTL 9", "AB1", "Direct 8", "TMC", "NT1", "NRJ 12", "La Cha�ne Parlementaire",
"BFM TV", "France 5", "Direct Star", "NRJ Paris", "Vivolta", "NRJ Hits",
"Game One", "TF1", "M6", "W9", "Canal+", "Equidia", "AB Moteurs",
"France �",
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

sub get_time {
	my $time = shift;
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime($time);
	# sprintf("%d/%02d/%02d %02d:%02d:%02d $tz",$year+1900,$mon,$mday,$hour,$min,$sec);
	sprintf("%02d:%02d:%02d",$hour,$min,$sec);
}

#
# Parameters
#
my $input;

my $channels_text = getListeChaines();
my @chan = split(/\:\$\$\$\:/,$channels_text);
my $sel = "";
foreach (@def_chan) {
	my $found = 0;
	for (my $n=0; $n<=$#chan; $n++) {
		if ($chan[$n] =~ /$_/) {
			my ($num,$name) = split(/\$\$\$/,$chan[$n]);
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

# Get HTML page of TV program
open(G,">debug_info");
G->autoflush(1);
print G "lecture day0\n";
if (open(F,"<day0")) {
	while (<F>) {
		$program_text .= $_;
	}
	close(F);
	my @fields = split(/\:\$\$\$\:/,$program_text);
	my @sub = split(/\$\$\$/,$fields[0]);
	if ($date ne $sub[12]) {
		unlink("day-1");
		rename("day0","day-1");
		$program_text = undef;
	}
}
my $reread = 0;
read_prg: $program_text = getListeProgrammes(0) if (!$program_text);
my $nb_days = 1;
debut: $program_text =~ s/(:\$CH\$:|;\$\$\$;)//g; # on se fiche de ce sparateur !
my @fields = split(/\:\$\$\$\:/,$program_text);
my %chaines = ();

my $date_offset = 0;
foreach (@fields) {
	my @sub = split(/\$\$\$/);
	my $chan = lc($sub[1]);
	if (!$date_offset || $sub[12] ne $date) {
		$date = $sub[12];
		($mday,$mon,$year) = split(/\//,$sub[12]);
		$mon--;
		$year -= 1900;
		$date_offset = timelocal(0,0,0,$mday,$mon,$year);
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
		} else {
			push @$rtab,\@sub;
		}
	} else {
		$chaines{$chan} = [\@sub];
	}
}

my $last_hour = 0;

system("rm -f fifo_info && mkfifo fifo_info");
my $start_timer = 0;
read_fifo:
my ($channel,$long) = ();
# my $timer_start;
my $time;
my $cmd = "";
my ($last_prog, $last_chan,$last_long);

sub disp_prog {
	my ($sub,$long) = @_;
	my $start = $$sub[3];
	my $end = $$sub[4];
	$start = get_time($start);
	$end = get_time($end);
	if ($$sub[9]) {
		# Prsence d'une image...
		my @date = split('/', $$sub[12]);
		my @time = split(':', $start);
		my $img = $date[2]."-".$date[1]."-".$date[0]."_".$$sub[0]."_".$time[0].":".$time[1].".jpg";
		my $raw = get $site_img.$img || print STDERR "can't get image $img\n";
		if ($raw) {
			open(F,">picture.jpg") || die "can't create picture.jpg\n";
			print F $raw;
			close(F);
		} else {
			$$sub[9] = 0;
		}
	}
	# Check channel logo
	my $url = $icons{$$sub[0]};
	my $name = setup_image($browser,$url);

	my $out = setup_output("bmovl-src/bmovl",$$sub[9],$long);

	print $out "$name\n";
	print $out "picture.jpg" if ($$sub[9]);

	print $out "\n$$sub[1] : $start - $end\n$$sub[2]\n\n$$sub[6]\n$$sub[7]\n";
	close($out);
}

if (!$reread) {
	do {
		# Celui l� sert � v�rifier les d�clenchements externes (noair.pl)
		if (-f "info_coords" && ! -f "list_coords" && !$last_long) {
			$start_timer = 1 
		}
		eval {
			alarm(5);
			local $SIG{ALRM} = sub { die "alarm clock restart" };
			open(F,"<fifo_info") || die "can't read fifo\n";
			$cmd = <F> || die "pass channel name on fifo\n";
			$long = <F>; # 2me argument -> affichage long
			chomp $cmd;
			alarm(0);
			close(F);
		};
		if ($@) {
			if ($start_timer && -f "info_coords" && ! -f "list_coords") {
				alpha("info_coords",-40,-255,-5);
				unlink "info_coords";
				$start_timer = 0;
			}
		}
	} while (!$cmd);
	#$timer_start = [gettimeofday];
	$time = time();
	if ($cmd eq "clear") {
		clear("info_coords");
		goto read_fifo;
	} elsif ($cmd eq "nextprog" || $cmd eq "right") {
		my $rtab = $chaines{$last_chan};
		if ($rtab) {
			my $n = $last_prog+1;
			$n-- if ($n > $#$rtab);
			disp_prog($$rtab[$n],$last_long);
			$last_prog = $n;
		}
		goto read_fifo;
	} elsif ($cmd eq "prevprog" || $cmd eq "left") {
		my $rtab = $chaines{$last_chan};
		if ($rtab) {
			my $n = $last_prog-1;
			$n=0 if ($n < 0);
			disp_prog($$rtab[$n],$last_long);
			$last_prog = $n;
		}
		goto read_fifo;
	} elsif ($cmd =~ /^(next|prev)$/) {
	    # Ces commandes sont juste pass�es � bmovl sans rien changer
	    # mais en passant par ici �a permet de r�initialiser le timeout
	    # de fondu, plut�t pratique...
	    open(F,">fifo_bmovl") || die "can't open fifo bmovl\n";
	    print F "$cmd\n";
	    close(F);
	    goto read_fifo;
	} elsif ($cmd =~ s/^prog //) {
		$channel = lc($cmd);
		$start_timer = 1 if (!$long);
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
	print G "$date2 != $date -> reread\n";
	$reread = 1;
	$date = $date2;
	goto read_prg;
}
chomp $channel;
chomp $long if ($long);
$channel = conv_channel($channel);
# print "lecture from fifo channel $channel long ".($long ? $long : "")." fields $#fields\n";

# print "recherche channel $channel\n";
my $rtab = $chaines{$channel};
if (!$rtab) {
	# Pas trouv� la chaine
	my $out = setup_output("bmovl-src/bmovl","",0);

	print $out "\n\n";
	($sec,$min,$hour) = localtime($time);

	print $out "$cmd : ".sprintf("%02d:%02d:%02d",$hour,$min,$sec),"\nAucune info\n";
	close($out);
	$last_chan = $channel;
	goto read_fifo;
}

for (my $n=0; $n<=$#$rtab; $n++) {
	my $sub = $$rtab[$n];
	my $start = $$sub[3];
	my $end = $$sub[4];

	if ($start <= $time && $time <= $end) {
		disp_prog($sub,$long);
		$last_chan = $channel;
		$last_prog = $n;
		$last_long = $long;
#			  system("feh picture.jpg &") if ($$sub[9]);
		goto read_fifo;
	}
}
# print "au final found $found pour channel $channel\n";
if ($time < $$rtab[0][3]) {
	print "pas trouv� l'heure, mais on va r�cup�rer le jour d'avant...\n";
	my $before = "";
	if (open(F,"<day-1")) {
		while (<F>) {
			$before .= $_;
		}
		close(F);
		$program_text = $before.$program_text;
	} else {
		print "geting programs for day before...\n";
		$program_text = getListeProgrammes(-1).$program_text;
	}
	goto debut;
}
print "vraiment pas trouv� l'heure ! channel $channel\n";
# print G "temps d'execution ",tv_interval($timer_start,[gettimeofday])," found $found\n";
goto read_fifo;

#==============================================================================
# Functions
#

# Do http request for a program
sub getListeProgrammes {
  my $offset = shift;
  # date YYYY-MM-DD
  my $date = strftime("%Y-%m-%d", localtime(time()+(24*3600*$offset)) );
  my $url = $site_prefix.'LitProgrammes1JourneeDetail.php?date='.$date.'&chaines=';

  for (my $i =0 ; $i < @selected_channels ; $i++ ) {
    $url = $url.$selected_channels[$i];
    if ($i < (@selected_channels - 1)) {
      $url = $url.",";
    }
  }

  if (!$input) {
    my $response = $browser->get($url);

    die "$url error: ", $response->status_line
      unless $response->is_success;

	open(F,">day".($offset));
	print F $response->content;
	close(F);
    return $response->content;
  } else {
    $program_text = "";
    open (FILE, "$input") || die "file $input not found";
    while (<FILE>) {
      $program_text = $program_text . $_;
    }

    return $program_text;
  }
}

sub request {
    my $url = shift;
    if (!$input) {
	my $response = $browser->get($url);

	die "$url error: ", $response->status_line
	unless $response->is_success;

	return $response->content;
    } else {
	$program_text = "";
	open (FILE, "<$input") || die "file $input not found";
	while (<FILE>) {
	    $program_text = $program_text . $_;
	}

	return $program_text;
    }
}

sub getListeChaines {
	my $r;
	if (!-f "liste_chaines" || -M "liste_chaines" > 1) {
		print "geting liste_chaines from web...\n";
		open(F,">liste_chaines") || die "can't create liste_chaines\n";
		my $url = $site_prefix."ListeChaines.php";

		$r = request($url);
		print F $r;
		close(F);
	} else {
		print "using cache for liste_chaines\n";
		open(F,"<liste_chaines") || die "can't read liste_chaines\n";
		while (<F>) {
			$r .= $_;
		}
		close(F);
	}
	return $r;
}

