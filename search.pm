package search;

use WWW::Mechanize;

sub init {
	my $mech = WWW::Mechanize->new();
	$mech->agent_alias("Linux Mozilla");
	# $mech->agent("Mozilla/5.0 (X11; Linux x86_64; rv:57.0) Gecko/20100101 Firefox/57.0");
	$mech->timeout(12);
	$mech->default_header('Accept-Encoding' => scalar HTTP::Message::decodable());
	$mech;
}

sub search {
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
