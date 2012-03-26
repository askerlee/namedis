# filter out disambiguation terms (ending with (disambiguation)) and terms with "<>{}\t".

use feature qw(switch say);

use strict;
use warnings 'all';

use IO::Handle;
use lib '/media/tough/namedis';
use NLPUtil;

use lib '.';
use ConceptNet;

my $outcount = 0;

my $progresser = makeProgresser(vars => [ \$., \$outcount ]);

my ($child, $parent, $redir);

while(<>){
	if(/^#/){
		print $_;
		next;
	}
	
	chomp;
	
	($child, $parent, $redir) = split /\t/;
	
	cleanTerm($child, $parent);
	
	next if hasIllegalChar($child, $parent);
	next if substr($child, -16, 16) eq "(disambiguation)";
	
	if($redir){
		print join("\t", $child, $parent, $redir), "\n";
	}
	else{
		print join("\t", $child, $parent), "\n";
	}
	
	$outcount++;
	&$progresser();
}

&$progresser(1);
