# test de signature youtube pour ce qu'on en sait...

use strict;

my %args;

$_ = <>;
chomp;
$args{s} = $_;
print "reverse ",scalar reverse $_,"\n";
my $s;
if (length($args{s}) == 81) {
	$s = $args{s};
} elsif (length($args{s}) == 88) {
	# key ???
	my $key = 6;
	if ($key == 1) {
		my $pre = substr($args{s},0,1);
		$s = substr(delete $args{s},1);
		my $post = substr($s,length($s)-6);
		my $s2 = "";
		for (my $n=length($s)-7; $n>=0; $n--) {
			$s2 .= substr($s,$n,1);
		}
		$s = $s2;
		my $prev = substr($s,16,1);
		substr($s,16,1) = substr($post,2,1);
		substr($s,21,1) = $prev;
		substr($s,49,1) = $pre;
	} else {
		# déduit à partir de :
		# original : 3E37E7EF363ED472A3E66C5913B9EA776B196A882B7C1.DB000454D23DE1813148366A385335F6C2F62DE6E6
		# résultat : 6ED26F2C6F533583A6638413181ED32D454000BD.1C3B288A691B677AE9B3195C66E3A274DE363FE7
		my $pre = substr($args{s},0,1);
		$s = reverse($args{s});
		substr($s,2,2) = "";
		substr($s,43,1) = $pre;
		$s = substr($s,0,81);
	}
} elsif (length($args{s}) == 86) {
	# url de départ
	# https://r6---sn-25ge7nls.googlevideo.com/videoplayback?requiressl=yes&ipbits=0&fexp=9406819%2C9408710%2C9414602%2C9416126%2C9417683%2C9418203%2C9418751%2C9420452%2C9420771%2C9422596%2C9422618%2C9423241%2C9423329%2C9423662%2C9424163%2C9424428%2C9424713%2C9425308&clen=2993338&mime=video%2Fmp4&gir=yes&mm=31&mn=sn-25ge7nls&itag=160&mt=1449581375&mv=m&ms=au&sver=3&dur=217.600&gcr=fr&ip=2001%3A41d0%3Afe0b%3A6d00%3A7a34%3Afe66%3A1360%3Ac62f&lmt=1417346102810277&id=o-AAkOGD8yzVt587O-Se0Y4JHXZ9Vd7wxonDG0hHn8Clgz&expire=1449603143&nh=IgpwcjAxLnBhcjEwKgkxMjcuMC4wLjE&upn=OFeI1Ltet3M&keepalive=yes&source=youtube&sparams=clen%2Cdur%2Cgcr%2Cgir%2Cid%2Cinitcwndbps%2Cip%2Cipbits%2Citag%2Ckeepalive%2Clmt%2Cmime%2Cmm%2Cmn%2Cms%2Cmv%2Cnh%2Cpl%2Crequiressl%2Csource%2Cupn%2Cexpire&initcwndbps=2747500&key=yt6&pl=47&itag=160&s=232395E582AFBC4E64D6F0E921EEBD41837D6D1339.F3F7CE0350EB5B275216FB254D12DA15B9421A76A77&init=0-672&size=192x144&index=673-1196&fps=13&bitrate=111831,lmt=1449572842523717&clen=2038975&quality_label=144p&projection_type=1&type=video/webm;+codecs="vp9
	$s = $args{s};
	my $post = substr($s,length($s)-1,1);
	my $pre = substr($s,0,1);
	$s = reverse substr($s,0,83);
	substr($s,81-1,1) = substr($s,31-1,1);
	substr($s,31-1,1) = $pre;
	substr($s,64-1,1) = substr($s,13-1,1);
	substr($s,13-1,1) = $post;
	$s = substr($s,0,81);
	# clé convertie :
# 67A1249B51AD71D452BF612572B5BE2530EC7F3F.9331D6D73814DBEE129E0F2D46E4CBFA285E5930
} elsif (length($args{s}) == 84) {
	$s = substr(reverse(delete $args{s}),1);
	my $post = substr($s,0,1);
	$s = substr($s,1);
	my $pre = substr($s,0,1);
	substr($s,0,1) = substr($s,39,1);
	substr($s,39,1) = $pre;
	substr($s,20,1) = substr($s,26,1);
	substr($s,26,1) = $post;
	substr($s,56,1) = substr($s,81,1);
	substr($s,81,1) = "";
} elsif (length($args{s}) == 82) {
	$s = delete $args{s};
	my $pre = substr($s,0,1);
	my $old = $s = substr($s,1);
	substr($s,14,1) = substr($s,36,1);
	substr($s,36,1) = substr($s,0,1);
	substr($s,0,1) = substr($old,14,1);
	substr($s,2,1) = $pre;
	substr($s,41,1) = substr($s,80,1);
	substr($s,80,1) = substr($old,41,1);
	substr($s,50,1) = substr($old,2,1);
} elsif (length($args{s}) == 83) {
	my $old = $s = delete $args{s};
	substr($s,0,1) = substr($s,43,1);
	substr($s,43,1) = substr($old,0,1);
	substr($s,81) = "";
}
if (length($s) == 81) {
	print "$s ok\n";
} else {
	print "not ok (",length($s),"):$s from orig ",length($args{s}),"\n";
}
$_ = <>;
chomp;
if ($s eq $_) {
	print "match\n";
} else {
	for (my $n=0; $n<length($s); $n++) {
		if (substr($s,$n,1) ne substr($_,$n,1)) {
			print "$n: ",substr($s,$n,1)," ",substr($_,$n,1),"\n";
		}
	}
}

