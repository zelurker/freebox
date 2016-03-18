# test de signature youtube pour ce qu'on en sait...

use strict;

my %args;

$_ = <>;
chomp;
$args{s} = $_;
$args{key} = "yt6";
print "len ",length($_)," reverse ",scalar reverse( $_),"\n";
my $s = delete $args{s};
my $pre = substr($s,0,1);
my $post = substr($s,length($s)-1,1);
if (length($s) == 87) {
	# url :
	# https://r8---sn-25g7sn76.googlevideo.com/videoplayback?c=web&clen=3245650&cpn=gXhweADxfv4A4CHD&cver=as3&dur=235.960&expire=1449932638&fexp=9406819,9416126,9418203,9418751,9420452,9420771,9422596,9423241,9423329,9423662,9424163,9424428,9424713,9425308,9425865&gcr=fr&gir=yes&id=o-AOTQh-K_bFAADRndo_d2cSCuDVCKbKXBAE6Uc0kvLNgO&initcwndbps=3068750&ip=2001:41d0:fe0b:6d00:7a34:fe66:1360:c62f&ipbits=0&itag=160&keepalive=yes&key=yt6&lmt=1417368535732977&mime=video/mp4&mm=31&mn=sn-25g7sn76&ms=au&mt=1449910888&mv=m&nh=IgpwcjAxLnBhcjEwKgkxMjcuMC4wLjE&pl=47&range=0-208895&ratebypass=yes&requiressl=yes&signature=E088DF9C6089AEB398864D7FC8BEB602991DFDCD.030115079646C58755B5E67CBA6791FCCCD48315&source=youtube&sparams=clen,dur,gcr,gir,id,initcwndbps,ip,ipbits,itag,keepalive,lmt,mime,mm,mn,ms,mv,nh,pl,requiressl,source,upn,expire&sver=3&upn=1CiYfJswzHw
	# clé origine : 808F088DF9C60F9AEB398864D7FC8BEB602991DEDCD.030115079646C58755B5E67CBA6791FCCCD48513513
	# décoée : E088DF9C6089AEB398864D7FC8BEB602991DFDCD.030115079646C58755B5E67CBA6791FCCCD48315
	my $old = $s = reverse(substr($s,3,81));
#	substr($s,0,1) = substr($s,36,1);
#	substr($s,10,1) = $pre;
#	substr($s,36,1) = substr($old,0,1);
#	substr($s,78,1) = substr($s,80,1);
#	substr($s,80,1) = substr($old,78,1);
	substr($s,0,1) = substr($s,21,1);
	substr($s,21,1) = substr($old,0,1);
	substr($s,48,1) = $post;
	substr($s,74,1) = $pre;
	substr($s,56,1) = substr($old,74,1);
	substr($s,80,1) = substr($old,56,1);

} elsif (length($s) == 91) {
	$s = substr($s,6,81);
	substr($s,24,1) = $pre;
	substr($s,53,1) = $post;

} elsif (length($s) == 88) {
	# key ???
	my $key = 6;
	if ($key == 1) {
		$s = substr($s,1);
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
		$s = substr($s,4,81);
		my $t = substr($s,52,1);
		substr($s,52,1) = $pre;
		my $t2 = substr($s,29,1);
		substr($s,29,1) = $t;
		$t = substr($s,36,1);
		substr($s,36,1) = $t2;
		substr($s,63,1) = $t;
#		$s = reverse($s);
#		substr($s,2,2) = "";
#		substr($s,43,1) = $pre;
#		$s = substr($s,0,81);
	}
} elsif (length($s) == 86) {
	# url de départ
	# https://r6---sn-25ge7nls.googlevideo.com/videoplayback?requiressl=yes&ipbits=0&fexp=9406819%2C9408710%2C9414602%2C9416126%2C9417683%2C9418203%2C9418751%2C9420452%2C9420771%2C9422596%2C9422618%2C9423241%2C9423329%2C9423662%2C9424163%2C9424428%2C9424713%2C9425308&clen=2993338&mime=video%2Fmp4&gir=yes&mm=31&mn=sn-25ge7nls&itag=160&mt=1449581375&mv=m&ms=au&sver=3&dur=217.600&gcr=fr&ip=2001%3A41d0%3Afe0b%3A6d00%3A7a34%3Afe66%3A1360%3Ac62f&lmt=1417346102810277&id=o-AAkOGD8yzVt587O-Se0Y4JHXZ9Vd7wxonDG0hHn8Clgz&expire=1449603143&nh=IgpwcjAxLnBhcjEwKgkxMjcuMC4wLjE&upn=OFeI1Ltet3M&keepalive=yes&source=youtube&sparams=clen%2Cdur%2Cgcr%2Cgir%2Cid%2Cinitcwndbps%2Cip%2Cipbits%2Citag%2Ckeepalive%2Clmt%2Cmime%2Cmm%2Cmn%2Cms%2Cmv%2Cnh%2Cpl%2Crequiressl%2Csource%2Cupn%2Cexpire&initcwndbps=2747500&key=yt6&pl=47&itag=160&s=232395E582AFBC4E64D6F0E921EEBD41837D6D1339.F3F7CE0350EB5B275216FB254D12DA15B9421A76A77&init=0-672&size=192x144&index=673-1196&fps=13&bitrate=111831,lmt=1449572842523717&clen=2038975&quality_label=144p&projection_type=1&type=video/webm;+codecs="vp9
	$s = reverse substr($s,0,83);
	substr($s,81-1,1) = substr($s,31-1,1);
	substr($s,31-1,1) = $pre;
	substr($s,64-1,1) = substr($s,13-1,1);
	substr($s,13-1,1) = $post;
	$s = substr($s,0,81);
	# clé convertie :
# 67A1249B51AD71D452BF612572B5BE2530EC7F3F.9331D6D73814DBEE129E0F2D46E4CBFA285E5930
} elsif (length($s) == 84) {
	$s = substr(reverse($s),1);
	$s = substr($s,1);
	substr($s,0,1) = substr($s,39,1);
	substr($s,39,1) = $pre;
	substr($s,20,1) = substr($s,26,1);
	substr($s,26,1) = $post;
	substr($s,56,1) = substr($s,81,1);
	substr($s,81,1) = "";
} elsif (length($s) == 82) {
	my $old = $s = substr($s,0,81);
# 	if ($args{key} eq "yt6") {
# 		substr($s,17,1) = $pre;
# 		# substr($s,36,1) = substr($s,0,1);
# 		substr($s,0,1) = substr($old,17,1);
# 		# substr($s,41,1) = substr($s,80,1);
# 		substr($s,80,1) = substr($old,79,1);
# 		# substr($s,50,1) = substr($old,2,1);
# 		substr($s,79,1) = substr($s,13,1);
# 		substr($s,13,1) = substr($old,80,1);
# 	} else {
# 		substr($s,14,1) = substr($s,36,1);
# 		substr($s,36,1) = substr($s,0,1);
# 		substr($s,0,1) = substr($old,14,1);
# 		substr($s,2,1) = $pre;
# 		substr($s,41,1) = substr($s,80,1);
# 		substr($s,80,1) = substr($old,41,1);
# 		substr($s,50,1) = substr($old,2,1);
# 	}

	# grrr, variation suivante, ils me rendent dingue !
	# Au moins elles sont simples...
	substr($s,0,1) = substr($s,48,1);
	substr($s,48,1) = substr($old,0,1);
} elsif (length($s) == 83) {
	# url originale
	# s=073AAC043F70F58C8CFADBAF38B2F3D7935439026.C8BD1CCFA2117B4AFB25C230547A310C2AB2D93EE
	# https://r5---sn-25ge7nl6.googlevideo.com/videoplayback?expire=1449684773&gcr=fr&itag=160&keepalive=yes&requiressl=yes&ms=au&mv=m&mt=1449663065&sparams=clen,dur,gcr,gir,id,initcwndbps,ip,ipbits,itag,keepalive,lmt,mime,mm,mn,ms,mv,nh,pl,requiressl,source,upn,expire&pl=47&id=o-AErYrG8stYzRckK7GxXbjAVt9EN0_s9xSw_IVDKHvCyq&mime=video/mp4&sver=3&lmt=1434106452912156&gir=yes&mn=sn-25ge7nl6&ip=2001:41d0:fe0b:6d00:7a34:fe66:1360:c62f&mm=31&ipbits=0&upn=IypybhqI7pY&initcwndbps=2805000&source=youtube&dur=284.283&clen=3873553&nh=IgpwcjAxLnBhcjAxKgkxMjcuMC4wLjE&fexp=9406819,9414602,9416126,9418203,9418751,9420452,9420771,9422596,9423241,9423329,9423662,9424163,9424428,9424713,9425308&key=yt6&type=video/mp4;+codecs="avc1.4d400c"&itag=160&lmt=1434106452912156&quality_label=144p&init=0-671&projection_type=1&fps=15&clen=3873553,size=192x144
	# signature décodée :
	# 73AAC043F70F58C8CFADBAF38B2F3D0935439026.C8BD1CCFA2117B4AFB25C230547A310C2AB2D93E
	if ($args{key} eq "yt6") {
		$s = substr($s,1,81);
		substr($s,30,1) = $pre;
	} else {
		my $old = $s;
		substr($s,0,1) = substr($s,43,1);
		substr($s,43,1) = substr($old,0,1);
		substr($s,81) = "";
	}
}
if (length($s) == 81) {
	print "$s ok\n";
} else {
	print "not ok (",length($s),"):$s from orig ",length($s),"\n";
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

