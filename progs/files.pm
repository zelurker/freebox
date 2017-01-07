package progs::files;

# basé sur podcasts.pm

use strict;
use progs::telerama;

@progs::files::ISA = ("progs::telerama");

our $debug = 0;

sub get {
	my ($p,$channel,$source,$base_flux) = @_;
	return undef if ($source !~ /(livetv|Enregistrement)/);

	return undef if (!-f "$channel.info");
	open(F,"<$channel.info");
	my $title = <F>;
	my $sub = <F>;
	my $desc = "";
	chomp $sub;
	while (<F>) {
		$desc .= $_;
	}
	close(F);
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
		"", # img
		0,0,
		$date);
	return \@tab;
}

1;
