package progs::html::finter;

use HTML::Entities;
use Time::Local qw(timelocal_nocheck timegm_nocheck);
use Cpanel::JSON::XS qw(decode_json);
use common::sense;
use Data::Dumper;
use myutf;

sub get_tag {
	my ($s,$t) = @_;
	if ($s =~ /$t"?="(.+?)"/) { # la version normale, avec des "
		return $1;
	}
	if ($s =~ /$t"?="?(.+?)"?([ >]|$)/) { # sinon on essaye de deviner !
		return $1;
	}
	undef;
}

sub find_closing_tag {
	my ($body,$pos,$tag) = @_;
	my $level = 1;
	while ($level && ($pos = index($body,$tag,$pos+1))>=0) {
		if (substr($body,$pos-2,2) eq "</") {
			$level--;
		} elsif (substr($body,$pos-1,1) eq "<") {
			$level++;
		}
	}
	$pos;
}

sub disp_date {
	my $start = shift;
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime($start);
	return sprintf("%d/%d/%d %02d:%02d",$mday,$mon+1,$year+1900,$hour,$min);
}

sub check_start {
	my ($ref, $prev_start) = @_;
	# les programmes de la nuit de finter sont pétés en avril 22, les
	# heures indiquent l'heure de la 1ère diffusion pour les redifs !
	if ($$ref < $prev_start-3600) {
		# on teste avec prev_start-3600 parce qu'ils collent leur playlist
		# de la nuit comme bouche trou si il reste de la place, mais vu
		# qu'on est obligé de mettre 1h pour chaque programme, y a des
		# jours où il en reste pas, elle doit être plutôt courte cette
		# playlist... !
		my ($sec,$min,$hour,$mday,$mon,$year) = localtime($prev_start+3600);
		if ($hour == 0 && $min == 0) { # journal de 23h, c'est encore pire !
			($sec,$min,$hour,$mday,$mon,$year) = localtime($prev_start+15*60); # on dit 23h15 pour le suivant ? C'est variable, mais si c'est pas indiqué... !
			$$ref = timelocal_nocheck(0,$min,$hour,$mday,$mon,$year);
			return;
		}
		$$ref = timelocal_nocheck(0,5,$hour,$mday,$mon,$year);
	}
}

sub decode_html {
	my ($p,$l,$name,$date) = @_;
	my $rtab = [];
	my $pos = 0;
	my $prev_start;
	my $keep_date = undef;
	my $rtab2 = $p->{chaines}->{lc($name)};
	if ($rtab2) {
		$prev_start = $$rtab2[$#$rtab2][3];
		say "prev_start init ".disp_date($prev_start);
	}
	# ── Extraction des émissions ─────────────────────────────────────────────────
	my @programs;
	my @blocks = split /(?=<div\s+__typename="Expression")/, $l;

	my ($sec,$min,$hour,$mday,$mon,$year) = localtime($date);
	my $zero = timelocal_nocheck(0,0,0,$mday,$mon,$year);
	my $imgsize    = 400;
	for my $block (@blocks) {
		my ($conceptid)     = $block =~ /conceptid="([^"]+)"/;
		my ($label)         = $block =~ /label="([^"]+)"/;
		my ($starttimeunix) = $block =~ /starttimeunix="([^"]+)"/;
		my ($islive)        = $block =~ /islive="([^"]+)"/;
		my ($playerid)      = $block =~ /playerid="([^"]+)"/;

		next unless defined $label && defined $starttimeunix;

		# Titre : texte du premier <a href>
		my ($href, $link_html) = $block =~ /<a\s+href="([^"]+)"[^>]*>(.*?)<\/a>/s;
		next unless defined $href;

		myutf::mydecode(\$link_html);
		my $title = _clean_html($link_html);

		# Sous-titre : <p class="... subtext ...">
		my ($subtext_html) = $block =~ /class="[^"]*subtext[^"]*"[^>]*>(.*?)<\/p>/s;
		myutf::mydecode(\$subtext_html);
		my $subtitle = defined $subtext_html ? _clean_html($subtext_html) : '';

		# Image : <img src="..."> — URL de base pikapi, on injecte la taille voulue
		my ($img_src) = $block =~ /<img[^>]+src="([^"]+)"/;
		my $img_url = '';
		if (defined $img_src) {
			# L'URL pikapi se termine par une taille (ex: /2048) — on la remplace
			($img_url = $img_src) =~ s|/\d+$|/$imgsize|;
		}

		# Lien podcast
		my $podcast_url = defined $playerid
		? "https://www.radiofrance.fr/transistor/aod/$playerid"
		: '';
		$subtitle .= "\npod:$podcast_url" if ($podcast_url);

		my @tab = (undef, $name, $title, $starttimeunix,
			undef, # end time
			"",
			$subtitle,
			undef,"",$img_url,0,0,$date);
		$p->insert(\@tab,$rtab,600);
	}
	return $rtab;
}

# ── Helpers ──────────────────────────────────────────────────────────────────
sub _clean_html {
    my ($s) = @_;
    $s =~ s/<[^>]+>//g;
    $s =~ s/&amp;/&/g;
    $s =~ s/&lt;/</g;
    $s =~ s/&gt;/>/g;
    $s =~ s/&quot;/"/g;
    $s =~ s/&#039;/'/g;
	# the next line if uncommented breaks utf8 encoding!
	#    $s =~ s/\s+/ /g;
    $s =~ s/^\s+|\s+$//g;
    $s;
}

1;

