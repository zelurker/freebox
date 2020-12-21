package http;

use strict;
use warnings;
use LWP::UserAgent;
use HTTP::Cookies;
use File::Path qw(make_path);
use Coro::LWP;
use feature qw(say);

# Un get qui stocke les cookies et tient compte de l'utf dans le content-type
sub myget {
	# arguments optionnels : $cache un fichier à utiliser pour le cache
	# et $age age du cache avant update en jours (nb à virgule ok)

	my ($url,$cache,$age) = @_;
	say "myget url $url";
	if ($cache) {
		$age = 1 if (!$age);
		my ($dir) = $cache =~ /^(.+)\//;
		make_path($dir) if ($dir && !-d $dir);
		if (-f $cache && -M $cache < $age) {
			# print STDERR "http.pl: cache hit fichier $cache url $url, age ",(-M $cache),"\n";
			open(my $f,"<$cache") || die "can't open $cache\n";
			@_ = <$f>;
			close($f);
			return join("\n",@_);
		}
	}

	my $cookie_jar = HTTP::Cookies->new(
           file => "$ENV{'HOME'}/lwp_cookies.dat",
           autosave => 1,
         );
		 # my $useragt = 'Telerama/1.0 CFNetwork/445.6 Darwin/10.0.0d3';
#	my $useragt = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_5) AppleWebKit/537.71 (KHTML, like Gecko) Version/6.1 Safari/537.71";
	my $useragt = "Mozilla/5.0 (X11; Linux x86_64; rv:72.0) Gecko/20100101 Firefox/72.0";
	my $ua = LWP::UserAgent->new(keep_alive => 0,
		agent =>$useragt);
	$ua->timeout(15);
	$ua->cookie_jar($cookie_jar);
	my $r = $ua->get($url);
	if (!$r->is_success) {
		say STDERR "myget: error for url $url";
		return undef;
	}
	my $type = $r->header("Content-type");
	# print STDERR "myget: got type $type\n";
	if ($type =~ /charset=(.+)/) {
		print "encoding: $1\n";
	}
	if ($cache) {
		open(my $f,">$cache");
		print $f $r->content;
		close($f);
	}
	return $r->content;
}

1;

