package progs::telerama;
#
#===============================================================================
#
#         FILE: telerama.pm
#
#  DESCRIPTION: 
#
#        FILES: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Emmanuel Anne (), emmanuel.anne@gmail.com
# ORGANIZATION: 
#      VERSION: 1.0
#      CREATED: 05/03/2013 12:52:52
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use LWP;
use Data::Dumper;
use POSIX qw(strftime);
use Time::Local "timelocal_nocheck","timegm_nocheck";
use chaines;
require HTTP::Cookies;
our $VERSION = '0.1';
 
# my @def_chan = ("France 2", "France 3", "France 4", "Arte", "TV5MONDE",
# "Direct 8", "TMC", "NT1", "NRJ 12", 
# "France 5", "NRJ Hits",
# "Game One", "Canal+", 
# );
my @def_chan = ();
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

our (@selected_channels,@chan,$net);
our ($date);
our $debug = 0;
our (%chaines);

sub new {
	my ($class,$mynet) = @_;
	my $p = bless {
		chaines => \%chaines,
	},$class;
	$p->init_selected_channels($mynet);
	$net = $mynet;
	getListeProgrammes(0);
	$p;
}

sub init_selected_channels($) {
	my ($p,$net) = @_;
	my $channels_text = chaines::getListeChaines($net);
	@chan = split(/\:\$\$\$\:/,$channels_text);
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
			$channels_text = undef;
		}
	}
	$sel =~ s/^\,//;

	@selected_channels = split(/,/,$sel);
}

sub init_date {
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime();
	$date = sprintf("%02d/%02d/%d",$mday,$mon+1,$year+1900);
}

sub get_offset {
	# Convertit un champ date en offset par rapport à la date courante
	my $date = shift;
	my ($j,$m,$a) = split(/\//,$date);
	$a -= 1900;
	$m--;
	my $d = timelocal_nocheck(0,0,0,$j,$m,$a);
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime();
	my $d2 = timelocal_nocheck(0,0,0,$mday,$mon,$year);
	$d = int(($d-$d2)/(3600*24));
	$d;
}

sub parse_prg($) {
	# Interprête le résultat de la requête de programmes...
	# et met à jour chaines{}
	# Attention la valeur retournée est un tableau de chaines
	# prévu pour être renvoyé dans les fichiers day*. Il faut relire chaines{}
	# après ça si on veut récupérer le tableau à 2 dimensions des programmes
	my ($program_text) = @_;	
	$program_text =~ s/(:\$CH\$:|;\$\$\$;)//g; # on se fiche de ce sparateur !
	my @fields = split(/\:\$\$\$\:/,$program_text);
	if (!@fields) {
		print "gros problème requête programmes, aucun champ obtenu, on ignore le réseau\n";
		$net = 0;
	}
	shift @fields if (!$fields[0]);

	my $date_offset = 0;
	# Les collisions : je laisse ce code qui fait des stats sur leur nombre et
	# le temps que ça prend à traiter. En fait on obtient de l'ordre de 1200
	# collisions pour une seule journée, mais ça prend moins de 2s à récupérer,
	# et moins d'1s à convertir dans un format utilisable en interne. Résultat
	# ça serait probablement + long de faire 1 requète par chaine pour éviter
	# les collisions. Tant pis pour eux, peut-être qu'un jour ils corrigeront
	# leur code qui fait toutes ces collisions !
	my $nb_collision = 0;
	my @fields2 = ();
	init_date() if (!$date);
	my $date0 = $date;

	# Voilà en commentaire les champs récupérés
	# chanid => 0,
	# chan_name => 1,
	# title => 2,
	# start => 3,
	# stop => 4,
	# category => 5,
	# desc => 6,
	# details => 7,
	# rating => 8,
	# image => 9,
	# stars => 10,
	# crit => 11,
	# airdate => 12,
	# showview => 13
	foreach (@fields) {
		my $old = $_;
		my @sub = split(/\$\$\$/);
		my $chan = lc($sub[1]);
		if (!$date_offset || $sub[12] ne $date) {
			$date = $sub[12];
			if (!$date) {
				print "*** format de fichier programmes incorrect, on va essayer de corriger\n";
				$program_text = "";
				return undef;
			}
			my ($mday,$mon,$year) = split(/\//,$sub[12]);
			$mon--;
			$year -= 1900;
			$date_offset = timelocal_nocheck(0,0,0,$mday,$mon,$year);
		}
		my ($hour,$min,$sec) = split(/\:/,$sub[3]);
		my $start = $date_offset + $sec + 60*$min + 3600*$hour;
		if ($sub[9]) {
			my @date = split(/\//,$sub[12]);
			my $img = "$date[2]-$date[1]-$date[0]_$sub[0]_$hour:$min.jpg";
			$sub[9] = $site_img.$img;
		}
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
				push @fields2,$old;
			}
		} else {
			$chaines{$chan} = [\@sub];
			push @fields2,$old;
		}
	}
	foreach (keys %chaines) {
		eval {
			my @tab = sort { $$a[3] <=> $$b[3] } @{$chaines{$_}};
			$chaines{$_} = \@tab;
		};
		if ($@) {
			print "info: *** erreur $! chaine $_\n";
			Dumper($chaines{$_});
		}
	}


	print scalar localtime," fin traitement fichier, $nb_collision collisions\n" if ($debug);
	if ($date0 ne $date) {
		init_date();
	}
	\@fields2;
}

sub req_prog($$) {
	my ($offset,$url) = @_;
	my $date = strftime("%Y-%m-%d", localtime(time()+(24*3600*$offset)) );
	$url = $site_prefix.'LitProgrammes1JourneeDetail.php?date='.$date.'&chaines='.$url;
	print "req_prog: url $url\n" if ($debug);
	my $response = $browser->get($url);
	if (! $response->is_success) {
	    print "$url error: $response->status_line\n";
	} elsif ($debug) {
		print "req_prog: is_success\n";
	}
	$response;
}

sub getListeProgrammes {
	# Lecture des caches (fichiers day*), et éventuellement mise à jour
	# si selected_channels contient quelque chose

	my $offset = shift;
	# date YYYY-MM-DD
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime();
	print "utilisation date $mday/",$mon+1,"/",$year+1900,"\n" if ($debug);
	my $d0 = timegm_nocheck(0,0,0,$mday,$mon,$year);
	my $found = undef;
	while (<day*>) {
		my $name = $_;
		my $text = "";
		next if (!open(my $f,"<$_"));
		print "lecture fichier $_\n" if ($debug);
		while (<$f>) {
			$text .= $_;
		}
		close($f);
		my @fields = split(/\:\$\$\$\:/,$text);
		my @sub = split(/\$\$\$/,$fields[0]);
		my ($j,$m,$a) = split(/\//,$sub[12]);
		$a -= 1900;
		$m--;
		print "comparaison à $sub[12] $mday et $j $mon et $m $year et $a\n" if ($debug);
		my $d = timegm_nocheck(0,0,0,$j,$m,$a);
		my $off = ($d-$d0)/(24*3600);
		print "$name -> $off\n" if ($debug);
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
	return parse_prg($found) if ($found);
	return undef if (!$net || !@selected_channels);

	my $url = "";
	for (my $i =0 ; $i < @selected_channels ; $i++ ) {
		$url = $url.$selected_channels[$i];
		if ($i < (@selected_channels - 1)) {
			$url = $url.",";
		}
	}
	if ($debug) {
		print scalar localtime," récupération $url\n"; 

		print "*** req_prog from getlisteprogrammes ***\n";
	}
	my $response = req_prog($offset,$url);
	return undef if (!$response->is_success);

	my $program_text = $response->content;

	my $prg = parse_prg($program_text);
	$program_text = join(':$$$:',@$prg);

	open(F,">day".($offset));
	print "fichier day$offset créé à partir de getlisteprogrammes\n" if ($debug);
	print F $program_text;
	close(F);
	print scalar localtime," fichier écrit\n" if ($debug);
	$program_text;
}

sub update {
	my ($p,$channel,$offset) = @_;
	$offset = 0 if (!defined($offset));
	for (my $n=0; $n<=$#chan; $n++) {
		my ($num,$name) = split(/\$\$\$/,$chan[$n]);
		if ($channel eq $name && $num != 254) {
			print "*** req_prog loop request ***\n" if ($debug);
			my $response = req_prog($offset,$num);
			last if (!$response->is_success);
			my $res = $response->content;
			my $program_text = ($chaines{$channel} ? join('$$$',$chaines{$channel}) : "");
			if ($res && index($program_text,$res) < 0 && $res =~ /$num/) {
				$res = parse_prg($res);
				if (open(F,">>day$offset")) {
					print "fichier day$offset mis à jour de update\n" if ($debug);
					seek(F,0,2); # A la fin
					print F ':$$$:' if (-s "day$offset");
					print F join(':$$$:',@$res);
					close(F);
				}
				print "programme lu à la volée $name ",length($program_text),"\n" if ($debug);
			} else {
				print "rien pu lire pour $channel $num\n" if ($debug);
				if ($res !~ $num) {
					print "renvoi résultat nul\n" if ($debug);
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
			$res = $chaines{$channel};
			print "update: returning $res\n" if ($debug);
			return $res;
		}
	}
}

sub get {
	my ($p,$channel,$source,$base_flux) = @_;
	$channel = chaines::conv_channel($channel);
	my $rtab = $chaines{$channel};
	$rtab = $p->update($channel,$source,$base_flux) if (!$rtab);
	if (!$rtab && $channel =~ /^france 3 /) {
		# On a le cas particulier des chaines régionales fr3 & co...
		$channel = "france 3";
		$rtab = $p->update($channel,$source,$base_flux);
	}
	if ($debug && !$rtab) {
		print "get: rien trouvé pour $channel\n";
	}
	return undef if (!$rtab);
	my $time = time();
	if ($time > $$rtab[$#$rtab][4]) {
		# Si le cache dans chaines{} est trop vieux, on met à jour
		print "update channel too old\n" if ($debug);
		$p->update($channel,$source,$base_flux);
		$rtab = $chaines{$channel};
	}
	for (my $n=0; $n<=$#$rtab; $n++) {
		my $sub = $$rtab[$n];
		my $start = $$sub[3];
		my $end = $$sub[4];

		if ($start <= $time && $time <= $end) {
			$p->{last_chan} = $channel;
			$p->{last_prog} = $n;
			print "get: on a trouvé, on renvoie $sub\n" if ($debug);
			return $sub;
		}
	}
	print "get: pas trouvé la bonne heure, testé avec $time\n";
	return $$rtab[$#$rtab];
}

sub next {
	my ($p,$channel) = @_;
	$channel = chaines::conv_channel($channel);
	return if ($channel ne $p->{last_chan});
	my $rtab = $chaines{$channel};
	if ($p->{last_prog} < $#$rtab) {
		$p->{last_prog}++;
		return $$rtab[$p->{last_prog}];
	}
	my $offset = get_offset($$rtab[$#$rtab][12])+1;
	my $old = $#$rtab;
	print "A récupérer offset $offset\n" if ($debug);
	$p->update($channel,$offset);
	$rtab = $chaines{$p->{last_chan}};
	if ($old == $#$rtab) {
		print "next: ça a foiré\n" if ($debug);
		return $$rtab[$p->{last_prog}];
	} elsif ($debug) {
		print "next: ça a du marcher old = $old new $#$rtab\n";
	}
	return $p->next($channel);
}

sub prev {
	my ($p,$channel) = @_;
	$channel = chaines::conv_channel($channel);
	return if ($channel ne $p->{last_chan});
	my $rtab = $chaines{$channel};
	if ($p->{last_prog} > 0) {
		$p->{last_prog}--;
		return $$rtab[$p->{last_prog}];
	}
	my $offset = get_offset($$rtab[0][12])-1;
	my $old = $#$rtab;
	print "A récupérer offset $offset\n" if ($debug);
	$p->update($channel,$offset);
	$rtab = $chaines{$p->{last_chan}};
	if ($old == $#$rtab) {
		print "prev: ça a foiré\n" if ($debug);
		return $$rtab[$p->{last_prog}];
	}
	$p->{last_prog} += $#$rtab - $old; # le tableau est trié
	return $p->prev($channel);
}

1;

