#!/usr/bin/perl

# R�cup�ration des liens mms ou autres � partir d'une page web

use Coro::LWP;
use strict;
use v5.10;

my $debug = 0;

sub get_mms {
	my $url = shift;
	return $url if ($url =~ /(mp4|mp3|avi|mov|asf|m4a|\d\d)$/);
	my $useragt = "Mozilla/5.0 (X11; Linux x86_64; rv:72.0) Gecko/20100101 Firefox/72.0";
	my $browser = LWP::UserAgent->new(keep_alive => 0,
		agent =>$useragt);
	$browser->timeout(5);
	$browser->default_header(
		[ 'Accept-Language' => "fr-fr"
			#                          'Accept-Encoding' => "gzip,deflate",
			# 'Accept-Charset' => "ISO-8859-15,utf-8"
		]
	);

	$browser->max_size(65000);
	my ($page,$type);
	if (!$debug) {
		my $response = $browser->head($url);
		$type = $response->header("Content-type");
		if (!$response->is_success) {
			say "get_mms error : ",$response->status_line;
			say "trying get (max size = 65000)...";
			$response = $browser->get($url);
			$type = $response->header("Content-type");
		}
		return undef if (!$response->is_success);
		if ($type =~ /(audio|video)/ && $type !~ /charset/) {
			# audio/xxx est quand m�me prenable !
			print "url is not text : $type\n";
			$browser->max_size(5000);
			$page = $response->content;
			if ($page !~ /^(\#EXTM3U|http|\[playlist)/) {
				# Evitez les cr�tins qui g�rent le m3u en audio !!!
				return $url;
			} else {
				print "cr�tin de m3u �vit�\n";
			}
		} else {
			if (!$type) {
				print "mms: pas de content-type: $type\n";
			}
			$page = $response->content;
		}
	} else {
		open(F,"<yt.html") || die "can't open yt.html\n";
		@_ = <F>;
		close(F);
		$page = join("",@_);
	}
	if (!$page) {
		print STDERR "could not get $url\n";
	} elsif ($page =~ /^(\#EXTM3U|http)/) {
		# m3u, on interpr�te d'apr�s le contenu et pas l'extension
		foreach (split /\r?\n/,$page) {
			next if (/^\#/);
			return $_ if (/^http/);
		}
		print "could not find url in m3u $page from $url\n";
		return undef;
	} elsif ($page =~ /^\[playlist/) {
		foreach (split /\r?\n/,$page) {
			return $1 if (/^File\d*\=(http.+)/);
		}
		print "pls impossible � traiter $page from $url\n";
		exit(1);
	} elsif ($page =~ /"(mms.+?)"/) {
		print "mms url : $1 from $url\n";
		return $1;
	} elsif ($page =~ /yt.preload.start\(/) { # Youtube
		while ($page =~ s/yt.preload.start\("(.+?)"\)//) {
			next if ($1 =~ /xml$/);
			my $url = $1;
			$url =~ s/\\\//\//g;
			$url =~ s/%(..)/chr(hex($1))/ge;
			$url =~ s/generate_204/videoplayback/g;
			$url =~ s/\\u(....)/chr(hex($1))/ge;
			print "youtube url $url\n";
			return $url;
		}
	} else {
# 		open(F,">dump");
# 		print F $page;
# 		close(F);
		while ($page =~ s/iframe src\="(.+?)"//m) {
			print "trying iframe $1\n";
			my $r = get_mms($1);
			return $r if ($r);
		}
		print "did not find mms from $url\n";
		if (!$type) {
			return $url;
		} else {
			return undef;
		}
	}
	return $url;
}

get_mms() if ($debug);

1;

