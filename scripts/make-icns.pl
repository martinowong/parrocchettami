#!/usr/bin/perl
use strict;
use warnings;

my ($iconset, $output) = @ARGV;
die "usage: make-icns.pl <iconset> <output.icns>\n" unless $iconset && $output;

my @icons = (
    ["icp4", "icon_16x16.png"],
    ["icp5", "icon_32x32.png"],
    ["icp6", "icon_32x32\@2x.png"],
    ["ic07", "icon_128x128.png"],
    ["ic08", "icon_256x256.png"],
    ["ic09", "icon_512x512.png"],
    ["ic10", "icon_512x512\@2x.png"],
);

my $body = "";
for my $icon (@icons) {
    my ($type, $name) = @$icon;
    my $path = "$iconset/$name";
    open my $input, "<:raw", $path or die "cannot read $path: $!\n";
    local $/;
    my $png = <$input>;
    close $input;
    $body .= $type . pack("N", length($png) + 8) . $png;
}

open my $out, ">:raw", $output or die "cannot write $output: $!\n";
print {$out} "icns", pack("N", length($body) + 8), $body;
close $out;
