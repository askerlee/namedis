use feature qw(switch say);

use strict;
use warnings 'all';

$| = 1;

my $pat = shift @ARGV;
my $file = shift @ARGV;

open(IN, "< $file") || die "Cannot open '$file': $!\n";
my $count = 0;
my $lc = 0;
while(<IN>){
	while(m/$pat/g){
		$count++;
	}
	$count++;
	if($count % 1000 <= 10){
		print "\r$count\t$lc\r";
	}
	$lc++;
}
print "\r$count\t$lc\n";
