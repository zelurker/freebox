package progs::files;

# basé sur podcasts.pm

use strict;
use progs::telerama;
use v5.10;

@progs::files::ISA = ("progs::telerama");

our $debug = 0;

sub get {
	my ($p,$channel,$source,$base_flux,$serv) = @_;
	if ($source eq "Enregistrements" && $channel !~ /^records/) {
		$channel = "records/$channel";
	}
	if ($channel !~ /\./) { # même pas un fichier
		if (open(F,"<current")) {
			(undef,undef,$channel) = <F>;
			chomp $channel;
			close(F);
			$channel =~ s/\.part$//;
		}
	}
	$channel =~ s/ \d+ Mo$//; # supprime la taille en suffixe éventuelle
	$channel =~ s/.part$//; # supprime un éventuel . part à la fin
	say STDERR "info/files: source $source channel $channel base_flux $base_flux serv $serv";
	return undef if ($source !~ /(livetv|Enregistrement|flux)/);

	return undef if (!-f "$channel.info" && !-f "$channel.png");
	my ($title,$pic,$sub,$desc) = ();
	if (open(F,"<$channel.info")) {
		$title = <F>;
		$pic = "";
		if ($title =~ s/pic:(http.+?) //) {
			$pic = $1;
		}
		$sub = <F>;
		$desc = "";
		chomp $sub;
		while (<F>) {
			$desc .= $_;
		}
		close(F);
	}
	if (!$pic && -f "$channel.png") {
		$pic = "$channel.png";
	}
	my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
		$atime,$mtime,$ctime,$blksize,$blocks) = stat($channel);
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
	localtime($mtime);
	my $date = sprintf("%02d/%02d/%d",$mday,$mon+1,$year+1900);
	$desc = "$sub\n$desc"; # apparemment pas de champ séparé pour le sous titre?
	while ($desc =~ s/<(.+?)>//g) {} # dégage les trucs html

	my @tab = (undef, # chan id
		"$source", "$title",
		undef, # début
		undef, "", # fin
		$desc, # desc
		"","",
		$pic, # img
		0,0,
		$date);
	return \@tab;
}

1;
