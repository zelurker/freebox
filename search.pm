package search;

use common::sense;
use WWW::Mechanize;
use HTTP::Cookies;
use HTML::Entities;

sub init {
	my $cookie_jar = HTTP::Cookies->new(
           file => "$ENV{'HOME'}/lwp_cookies.dat",
           autosave => 1,
         );
	my $mech = WWW::Mechanize->new(cookie_jar => $cookie_jar);
	# $mech->agent_alias("Linux Mozilla");

	$mech->agent("Mozilla/5.0 (X11; Linux x86_64; rv:152.0) Gecko/20100101 Firefox/152.0");
	$mech->timeout(12);
	$mech->default_header('Accept-Encoding' => scalar HTTP::Message::decodable());
	$mech;
}

sub search {
	my $q = shift;

	my $mech = init();
	$q =~ s/ /\+/g;
	say "search: q=$q";
	eval {
		$mech->get("https://search.brave.com/search?q=$q");
	};
	return $mech;
}

sub search_yahoo {
	my $q = shift;

	my $mech = init();
	eval {
		$mech->get("https://fr.search.yahoo.com/search");
		$mech->submit_form(
			form_number => 1,
			fields      => {
				"p" => $q,
				"fr" => "yfp-search-sb"
			}
		);
	};
	my $html = $mech->content;
	$html =~ s/href="https?:\/\/f?r.search.yahoo.com.+?RU=(.+?)\/.+?"/href="$1"/g;
	$html =~ s/%(..)/chr(hex($1))/ge;
	$mech->update_html($html);

	return $mech;
}

1;
