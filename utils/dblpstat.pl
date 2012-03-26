use strict;
use warnings 'all';

use lib '.';
use NLPUtil;

open_or_die(DB, "< dblp.extracted.txt");

my %authorStat;

my ($i, $author, $thisPublication, @authorNames);

my $progresser = makeProgresser( vars => [ \$. ] );

while(!eof(DB)){
	$thisPublication = parseCleanDBLP(DB);
	
	@authorNames = @{ $thisPublication->authors };

	for $author(@authorNames){
		$authorStat{$author}++;
	}
	
	&$progresser();
}

&$progresser(1);

my @authors = sort { $authorStat{$b} <=> $authorStat{$a} } keys %authorStat;

print scalar keys %authorStat, "\n\n";

print "Top prolific authors:\n";
for($i = 0; $i < 10; $i++){
	print "$authors[$i] => $authorStat{ $authors[$i] }\n";
}
