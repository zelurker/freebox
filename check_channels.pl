#!/usr/bin/perl

use strict;
use LWP;
use HTTP::Cookies;
use Data::Dumper;
use chaines;

my %icons = chaines::get_icons();
my $useragt = 'Telerama/1.0 CFNetwork/445.6 Darwin/10.0.0d3';
my $site_addr = "guidetv-iphone.telerama.fr";
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

foreach (sort keys %icons) {
			my ($name) = $icons{$_} =~ /.+\/(.+)/;
			next if (-f $name);
			my $response = $browser->get($icons{$_});

			if (!$response->is_success) {
				print "got error ",$response->code," msg ",$response->message," for $icons{$_}\n";
				next if ($response->code == 404);
			    sleep(3);
			    my $response = $browser->get($icons{$_});
			}
			if (!$response->is_success) {
				print "2nd try got error $response->{code}\n";
				next;
			}
			open(F,">chaines/$name") || die "can't create $name\n";
			print F $response->content;
			close(F);
}
