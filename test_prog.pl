#!/usr/bin/env perl

# use progs::podcasts;
use Cpanel::JSON::XS qw(decode_json);
use Data::Dumper;
use strict;
use warnings;
use chaines;

my $file = $ARGV[0] || "cache/telerama/day0-4";
open(F,"<$file");
@_ = <F>;
close(F);
my $res = join("",@_);
my $json = decode_json($res);
print Dumper($json);

