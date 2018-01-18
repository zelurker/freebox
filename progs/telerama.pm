package progs::telerama;

use strict;
use LWP;
use Data::Dumper;
use POSIX qw(strftime);
use Time::Local "timelocal_nocheck","timegm_nocheck";
use Cpanel::JSON::XS qw(decode_json);
use chaines;
require HTTP::Cookies;
use Encode;
use out;
use Digest::HMAC_SHA1 qw(hmac_sha1_hex);
use v5.10;

# my @def_chan = ("France 2", "France 3", "France 4", "Arte", "TV5MONDE",
# "Direct 8", "TMC", "NT1", "NRJ 12",
# "France 5", "NRJ Hits",
# "Game One", "Canal+",
# );
my @def_chan = ();
my $site_addr = "api.telerama.fr";
my $site_prefix = "https://$site_addr/verytv/procedures/";
my $site_img = "http://$site_addr/verytv/procedures/images/";

# init the Web agent
my $useragt = 'okhttp/3.2.0';
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

our (@selected_channels,$chan,$net);
our ($date);
our $debug = 0;
our (%chaines);

sub new {
	my ($class,$mynet) = @_;
	my $p = bless {
		chaines => (),
	},$class;
	if ($class =~ /telerama/) {
		# Init sp�cifique � t�l�rama, mais il y a des classes qui
		# surchargent donc faut faire attention !!!
		$chan = chaines::getListeChaines($net);
		$p->{chaines} = \%chaines;
		mkdir "cache/telerama";
		$net = $mynet;
		$p->getListeProgrammes(0);
	}
	$p;
}

sub init_date {
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime();
	$date = sprintf("%02d/%02d/%d",$mday,$mon+1,$year+1900);
}

sub get_offset {
	# Convertit un champ date en offset par rapport � la date courante
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

sub parse_date {
	# convertit un champ date de t�l�rama en heure gmt
	my $d = shift;
	my ($an,$mois,$jour,$h,$m,$s) = $d =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/;
	$an -= 1900; $mois--;
	timelocal_nocheck($s,$m,$h,$jour,$mois,$an);
}

sub get_date {
	# ne renvoie que la partie date, pour la compatibilit� avec le vieux
	# champ "airdate" qu'il faudrait peut-�tre virer un de ces 4...
	my $d = shift;
	my ($an,$mois,$jour) = $d =~ /(\d+)-(\d+)-(\d+)/;
	"$jour/$mois/$an";
}

sub dump_details {
	my ($details,$lib,$cont) = @_;
	$details .= "\n" if ($details);
	$details .= $lib;
	$details .= "s" if ($cont =~ /,/);
	$details .= " : $cont.";
	$details;
}

sub parse_prg {
	# Interpr�te le r�sultat de la requ�te de programmes...
	# et met � jour chaines{}
	# Attention la valeur retourn�e est un tableau de chaines
	# pr�vu pour �tre renvoy� dans les fichiers day*. Il faut relire chaines{}
	# apr�s �a si on veut r�cup�rer le tableau � 2 dimensions des programmes
	my ($program_text,$num,$label) = @_;

	my $chan = lc($label);
	my $json;
	eval {
		$json = decode_json($program_text);
	};
	if ($@) {
		print "parse_prg: decode_json error $! � partir de $program_text\n";
		return undef;
	}
	foreach (@{$json->{donnees}}) {

		# Voil� en commentaire les champs r�cup�r�s
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
		my $details = $_->{resume};
		my ($lib,$cont);
		foreach (@{$_->{intervenants}}) {
			if ($lib eq $_->{libelle}) {
				$cont .= ", ";
			} else {
				if ($lib) {
					$details = dump_details($details,$lib,$cont);
				}
				$cont = "";
				$lib = $_->{libelle};
			}
			$cont .= "$_->{prenom} $_->{nom}";
			$cont .= " ($_->{role})" if ($_->{role});
		}
		$details = dump_details($details,$lib,$cont) if ($lib);
		if ($_->{notule}) {
			# leur notule a l'air d'�tre une pr�sentation de la s�rie pour
			# les s�ries, mais c'est aussi le contenu d'une rencontre
			# sportive... �a va faire long de l'ajouter � ce qu'il y a
			# d�j�, mais des fois c'est la seule info dispo. A essayer, on
			# verra bien...
			$details .= "\n" if ($details);
			$details .= $_->{notule};
			# en fait y a pas que de l'html, y a <+>texte<+> pour mettre
			# texte en "exposant", genre 8<+>e<+> pour 8e avec le e en
			# hauteur. On se contente de d�gager les balises...
			$details =~ s/<.+?>//g; # vire tous les tags html
		}
		if ($_->{annee_realisation}) {
			$details .= "\n" if ($details);
			$details .= "Ann�e de r�alisation : $_->{annee_realisation}";
		}

		my $rating = "";
		foreach (@{$_->{csa_full}}) {
			$rating .= ", " if ($rating);
			$rating .= $_->{nom_long};
		}
		my $sub = $_->{soustitre};
		$sub .= "\nSaison $_->{serie}->{saison} Episode $_->{serie}->{numero_episode}" if ($_->{serie});

		my $critique = $_->{critique};
		$critique =~ s/<.+?>//g; # vire tous les tags html
		my $title = $_->{titre};
		$title .= " (original : $_->{titre_original})" if ($_->{titre_original} && $_->{titre_original} ne $_->{titre});

		my @sub = ($num,$label,$title,
			parse_date($_->{horaire}->{debut}),parse_date($_->{horaire}->{fin}),
			$_->{genre_specifique},$sub,$details,
			$rating,
			# pour l'image, ils ont 4 tailles, �quivalentes 2 � 2, mais en
			# fait petite est tr�s petite (124x96), et grande est du 720p!
			# Id�alement pour des images ici il faudrait le double de
			# petite et �a serait quand m�me dans les 4 fois moins large
			# que grande !
			$_->{vignettes}->{grande},
			$_->{note_telerama}, # stars
			$critique,
			get_date($_->{horaire}->{debut}),$_->{showview});
		my $rtab = $chaines{$chan};
		if ($rtab) {
			push @$rtab,\@sub;
		} else {
			$chaines{$chan} = [\@sub];
		}
	}
	say "parse_prg: stockage dans $chan." if ($debug);
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
	# quand l'interpr�tation est bonne, on renvoie le texte original qui
	# est �ventuellement stock� dans un fichier
	return $program_text;
}

sub myhash {
	my $url = shift;
	my ($base,$args) = split(/\?/,$url);
	my @args = split /\&/,$args;
	my $l;
	# le truc de merde, ils font un hash, mais au lieu de le faire sur
	# l'url ce qui serait quand m�me + simple, ils le font sur les
	# arguments mais sans le =, et le tout avec quand m�me la base de l'url
	# coll�e, vraiment du d�lire... !
	foreach (sort @args) {
		s/\=//;
		$l .= $_;
	}
	$l = $base.$l;

	hmac_sha1_hex($l, 'Eufea9cuweuHeif');
}

sub req_prog {
	my ($offset,$u,$page) = @_;
	my $date = strftime("%Y-%m-%d", localtime(time()+(24*3600*$offset)) );
	my $server = "https://api.telerama.fr";
	$page = 1 if (!$page);
	my $url = "/v1/programmes/telechargement?dates=$date&nb_par_page=25&id_chaines=".$u;
	$url .= "&appareil=android_tablette";
	$url .= "&page=$page" if ($page);
	$url .= "&api_signature=".myhash($url)."&api_cle=apitel-5304b49c90511";
	print "req_prog: url $url\n" if ($debug);
	my $response = $browser->get($server.$url);
	if (! $response->is_success) {
	    print "$server$url error: ",$response->status_line,"\n";
	} elsif ($debug) {
		print "req_prog: is_success\n";
	}
	my $c = $response->content;
	if ($c =~ /nb_sur_page":25/) { # on arrive � saturation
		if (!$page) {
			$page = 2;
		} else {
			$page++;
		}
		print "telerama: req page $page\n";
		my $r = req_prog($offset,$u,$page);
		if ($r->is_success) {
			my $c2 = $r->content;
			my ($d) = $c2 =~ /donnees":\[(.+)\],"pagin/;
			$c =~ s/donnees":\[(.+)\],"pagin/donnees":\[$1,$d\],"pagin/;
			print "telerama: create new response...\n";
			$response = HTTP::Response->new(200,"",undef,$c);
		}
	}
	$response;
}

sub error {
	my ($p,$msg) = @_;
	$p->{err} = $msg;
}

sub getListeProgrammes {
	# Lecture des caches (fichiers day*)
	# Tr�s grosse diff�rence par rapport aux versions pr�c�dentes : les
	# fichiers ne sont lus qu'au lancement du programme. Il risque d'y
	# avoir un probl�me si le programme est lanc� avant minuit et met des
	# donn�es � jour apr�s minuit, ce n'est pas trait� pour l'instant...

	my ($p,$offset) = @_;
	# date YYYY-MM-DD
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime();
	print "utilisation date $mday/",$mon+1,"/",$year+1900,"\n" if ($debug);
	my $d0 = timegm_nocheck(0,0,0,$mday,$mon,$year);
	while (<cache/telerama/day*>) {
		my $name = $_;
		my ($num) = $name =~ /day.*-(\d+)/;
		my $text = "";
		next if (!open(my $f,"<$_"));
		print "lecture fichier $_\n" if ($debug);
		while (<$f>) {
			$text .= $_;
		}
		close($f);
		my ($a,$m,$j) = $text =~ /debut":"(\d+)-(\d+)-(\d+)/;
		my $d = timegm_nocheck(0,0,0,$j,$m-1,$a-1900);
		my $off = ($d-$d0)/(24*3600);
		print "$name -> $off\n" if ($debug);
		my $new = "cache/telerama/day$off-$num";
		if ($name ne $new) {
			if ($off < -1 || -f $new) {
				unlink $name;
				next;
			} else {
				rename $name,$new;
			}
		}
		my $lib;
		foreach (keys %$chan) {
			if ($chan->{$_}[0] == $num) {
				$lib = $chan->{$_}[2];
				last;
			}
		}
		parse_prg($text,$num,$lib) if ($lib);
	}
}

sub update {
	# G�n�ralement appel� par get
	# channel est d�j� converti en minuscules (appel � conv_channel de
	# chaines.pm)
	my ($p,$channel,$offset) = @_;
	say "update $channel offset $offset";
	$p->error();
	$offset = 0 if (!defined($offset));
	return undef if (!out::have_net());
	my $num = $chan->{$channel}[0];
	if (!$num) {
		say "update: pas trouv� de num�ro pour $channel";
		return undef;
	}

	my $response = req_prog($offset,$num);
	if (!$response->is_success) {
		$p->error($response->status_line);
		return;
	}
	my $res = $response->content;
	my $program_text = $p->{chaines}->{$channel};
	if ($res && index($program_text,$res) < 0) {
		my $res0 = parse_prg($res,$num,$chan->{$channel}[2]);
		if (!$res0) {
			print "could not parse req_prg: $res\n";
			return;
		} else {
			$res = $res0;
		}
		# Dans le format initial de t�l�rama, les donn�es �taient juste �
		# la suite, s�par�es par des :$$$:, donc on pouvait ajouter autant
		# de chaiens qu'on voulait sans probl�me dans le m�me fichier.
		# Maintenant c'est du json, �a serait pas impossible, mais quand
		# m�me nettement + compliqu�. Donc on va changer � la place, et on
		# va prendre comme format day<num�ro d'offset>-<num�ro de chaine>
		# pour les fichiers de cache
		if (open(F,">cache/telerama/day$offset-$num")) {
			print "fichier day$offset-$num mis � jour de update\n" if ($debug);
			print F $res;
			close(F);
		}
	} else {
		print "rien pu lire pour $channel $num\n" if ($debug);
		if ($res !~ $num) {
			print "renvoi r�sultat nul\n" if ($debug);
		} else {
			open(F,">debug");
			print F "$res\n";
			close(F);
			open(F,">debug2");
			print F "$program_text\n";
			close(F);
			print "fichier debug cr��, on quitte\n";
			exit(1);
		}
	}
	$res = $p->{chaines}->{$channel};
	print "update: returning $res\n" if ($debug);
	return $res;
}

sub get {
	my ($p,$channel,$source,$base_flux) = @_;
	$p->{name} = $channel;
	$channel = chaines::conv_channel($channel);
	my $rtab = $p->{chaines}->{$channel};
	$rtab = $p->update($channel) if (!$rtab);
	if (!$rtab && $channel =~ /^france 3 /) {
		# On a le cas particulier des chaines r�gionales fr3 & co...
		$channel = "france 3";
		$rtab = $p->update($channel);
	}
	if ($debug && !$rtab) {
		print "get: rien trouv� pour $channel\n";
	}
	return undef if (!$rtab || $#$rtab < 0);
	my $time = time();
	if ($time > $$rtab[$#$rtab][4]) {
		# Si le cache dans chaines{} est trop vieux, on met � jour
		print "update channel too old\n" if ($debug);
		$p->update($channel);
		$rtab = $p->{chaines}->{$channel};
	}
	my $min = 3600*24;
	my $min_n = $#$rtab;
	if ($$rtab[0][3] > $time) {
		# Heure de d�but du 1er prog dans le futur -> r�cup�rer l'offset d'avant
		print "update channel too recent\n" if ($debug);
		my $offset = get_offset($$rtab[0][12])-1;
		$p->update($channel,$offset);
	}

	for (my $n=0; $n<=$#$rtab; $n++) {
		my $sub = $$rtab[$n];
		my $start = $$sub[3];
		my $end = $$sub[4];

		if ($start <= $time && $time <= $end) {
			$p->{last_chan} = $channel;
			$p->{last_prog} = $n;
			print "get: on a trouv�, on renvoie $sub\n" if ($debug);
			return $sub;
		} elsif ($start >= $time && $start - $time < $min) {
			# Certains programmes ont une marge entre la fin d'un prog
			# et le d�but du suivant, donc si on ne trouve pas, on renvoie
			# le prochain � suivre
			$min = $start - $time;
			$min_n = $n;
		}
	}
	print "get: pas trouv� la bonne heure, test� avec $time\n";
	return undef;
}

sub next {
	my ($p,$channel) = @_;
	$channel = chaines::conv_channel($channel);
	return if (!$p->{last_chan} || $channel ne $p->{last_chan});
	my $rtab = $p->{chaines}->{$channel};
	return if (!$rtab);
	if ($p->{last_prog} < $#$rtab) {
		$p->{last_prog}++;
		return $$rtab[$p->{last_prog}];
	}
	# note : nouveau t�l�rama, on ne fait plus $offset+1 ici parce qu'on a
	# toujours un bout du jour suivant quand on demande les 100 programmes
	# d'une date donn�e, � priori ils ont l'air d'aller de 6h jour actuel �
	# 6h jour suivant (on se demande bien pourquoi ils n'ont pas pris 0h !)
	my $offset = get_offset($$rtab[$#$rtab][12]);
	my $old = $#$rtab;
	print "A r�cup�rer offset $offset de $$rtab[$#$rtab][12]\n" if ($debug);
	$p->update($channel,$offset);
	$rtab = $p->{chaines}->{$p->{last_chan}};
	if ($old == $#$rtab) {
		print "next: �a a foir�\n" if ($debug);
		return $$rtab[$p->{last_prog}];
	} elsif ($debug) {
		print "next: �a a du marcher old = $old new $#$rtab\n";
	}
	return $p->next($channel);
}

sub prev {
	my ($p,$channel) = @_;
	$channel = chaines::conv_channel($channel);
	return if (!$p->{last_chan} || $channel ne $p->{last_chan});
	my $rtab = $p->{chaines}->{$channel};
	if ($p->{last_prog} > 0) {
		$p->{last_prog}--;
		return $$rtab[$p->{last_prog}];
	}
	my $offset = get_offset($$rtab[0][12])-1;
	my $old = $#$rtab;
	print "A r�cup�rer offset $offset\n" if ($debug);
	$p->update($channel,$offset);
	$rtab = $p->{chaines}->{$p->{last_chan}};
	if ($old == $#$rtab) {
		print "prev: �a a foir�\n" if ($debug);
		return $$rtab[$p->{last_prog}];
	}
	$p->{last_prog} += $#$rtab - $old; # le tableau est tri�
	return $p->prev($channel);
}

1;

