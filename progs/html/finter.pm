package progs::html::finter;

use Time::Local qw(timelocal_nocheck timegm_nocheck);
use common::sense;
use myutf;

sub disp_date {
	my $start = shift;
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime($start);
	return sprintf("%d/%d/%d %02d:%02d",$mday,$mon+1,$year+1900,$hour,$min);
}

sub decode_html {
	my ($p,$l,$name,$date) = @_;
	# c'est à moitié con, la date passée est au format localtime, mais la date à stocker pour le prog doit être au format j/m/a. get_date de finter fait ça très bien.
	$date = $p->get_date($date);
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

