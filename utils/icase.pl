use strict;
use warnings 'all';
use lib '.';
use NLPUtil;

$| = 1;

if(@ARGV < 2){
	die "Usage: $0 filename string-to-search\n";
}

my ($filename, $pat) = @ARGV;

my $DATA;
open_or_die($DATA, "< $filename");

my $line;

my %findings;

while($line = <$DATA>){
	if($. % 1000 == 0){
		print "\r$.\r";
	}
	
	while($line =~ /($pat)/gi){
		$findings{$1}++;
	}
}
print "\r$.\n";

print "Found occurrences of '$pat':\n";

my $s;
for $s(sort keys %findings){
	print "$s\t=>\t$findings{$s}\n";
}
