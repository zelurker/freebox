#!/usr/bin/perl

use strict;
use v5.10;
use lyrics;

our $latin = ($ENV{LANG} !~ /UTF/i);

my $file = shift @ARGV || die "file ?\n";
my $lyrics = lyrics::get_lyrics($file);
say "got lyrics $lyrics" if ($lyrics);

