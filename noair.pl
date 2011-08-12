#!/usr/bin/perl

# Récupération du programme de nolife par leur xml noair : la frime !!!
# test iso : c½ur en fête

use LWP::Simple;
use LWP::UserAgent;
use Time::Local;
use strict;
require "output.pl";
use Encode;

sub update_noair {
	print STDERR "updating noair...\n";
	my $xml = get "http://www.nolife-tv.com/noair/noair.xml";
	open(F,">air.xml");
	print F $xml;
	close(F);
}

my $long = shift @ARGV;

if (!open(F,"<air.xml")) {
	update_noair();
	die "can't get noair listing\n" if (!open(F,"<air.xml"));
}

our $xml;
while (<F>) {
	$xml .= $_;
}
close(F);
Encode::from_to($xml, "utf-8", "iso-8859-15");
$xml =~ s/½/oe/g;
# XML::Simple is easy to use but slow as hell here.

# our $tz = strftime("%z",localtime());

sub conv_date {
	my $date = shift;
	my ($a,$mois,$j,$h,$m,$s) = $date =~ /^(....).(..).(..) (..).(..).(..)/;
	$a -= 1900;
	$mois--;
	timegm($s,$m,$h,$j,$mois,$a);
}

sub get_time {
	my $time = shift;
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime($time);
	# sprintf("%d/%02d/%02d %02d:%02d:%02d $tz",$year+1900,$mon,$mday,$hour,$min,$sec);
	sprintf("%02d:%02d:%02d",$hour,$min,$sec);
}

sub get_date {
	my $time = shift;
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime($time);
	sprintf("%d%02d%02d",$year+1900,$mon,$mday);
}

sub get_field {
	my ($line,$field) = @_;
	$line =~ /$field\=\"(.+?)\"/;
	$1;
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

sub disp_details {
	my ($start,$date,$old_title,$old_sub,$desc,$old_shot) = @_;
	my $out = setup_output("bmovl-src/bmovl","",$long);
	my $browser = LWP::UserAgent->new(keep_alive => 0);
	my $name = setup_image($browser,"http://upload.wikimedia.org/wikipedia/fr/thumb/3/3f/Logo_nolife.svg/208px-Logo_nolife.svg.png");
	my $raw;
	if ($old_shot) {
		$raw = get $old_shot;
		if ($raw) {
			open(F,">picture.jpg");
			print F $raw;
			close(F);
		}
	}
	print $out "$name\n";
	print $out "picture.jpg" if ($raw);
	print $out "\n";
	print $out get_time($start)," - ",get_time($date),"\n";
	print $out "$old_title - $old_sub\n";
	print $out "$desc\n";
	close($out);
}

sub find_prg {
	my $time = time();
	my ($title,$start,$old_title,$sub,$desc,$old_sub,$old_shot,$shot);
	my $date;
	foreach (split /\n/,$xml) {
		next if (!/\<slot/);

		$date = conv_date(get_field($_,"dateUTC"));
		# print get_time($date)," ",$_->{title},"\n";
		$start = $date if (!$start);
		$old_title = $title;
		$old_sub = $sub;
		$old_shot = $shot;
		$title = get_field($_,"title");
		$sub = get_field($_,"sub-title");
		$title = $sub if (!$title);
		$shot = get_field($_,"screenshot");
		if ($start && $old_title ne $title && $old_title) {
			if ($start <= $time && $date >= $time) {
				disp_details($start,$date,$old_title,$old_sub,$desc,$old_shot);
				return 1;
			}
# 		print '<programme start="',get_time($start).'" stop="'.get_time($date).'" channel="1500.telerama.fr">
#   <title lang="fr">'.$old_title.'</title>
#   <sub-title lang="fr">'.$old_sub.'</sub-title>
#   <desc lang="fr">'.$desc.'</desc>
#   <category>'.$old_cat.'</category>
#   <date>'.get_date($start).'</date>
#   <length units="minutes">'.$duree.'</length>
#  </programme>
#  ';
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
	if ($start <= $time && $date >= $time) {
		disp_details($start,$date,$old_title,$old_sub,$desc,$old_shot);
		return 1;
	}
	return 0;
}

if (!find_prg()) {
	print STDERR "did not find prg\n";
	exit(1);
	update_noair();
	die "can't get noair listing\n" if (!open(F,"<air.xml"));
	$xml = "";
	while (<F>) {
		$xml .= $_;
	}
	close(F);
	Encode::from_to($xml, "utf-8", "iso-8859-15");
	$xml =~ s/½/oe/g;
	if (!find_prg()) {
		print STDERR "programme introuvable même après update\n";
	}
}

