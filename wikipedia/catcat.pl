# process skos_categories_en.nq and produce category-category relations

use feature qw(switch say);

use strict;
use warnings 'all';

use IO::Handle;
use lib '/media/tough/namedis';
use NLPUtil;

use lib '.';
use ConceptNet;

my ($child, $parent);

my ($inc, $outc);
my $nonEngCount = 0;

my $progresser = makeProgresser(vars => [ \$inc, \$outc, \$nonEngCount ]);

my $inFilename	= "extraction/en/skos_categories_en.nt";
my $outFilename = "catcat0.txt";

open_or_die(IN,		"< $inFilename");
open_or_die(OUT, 	"> $outFilename");
open_or_die(NONENG, "> nonenglish_cat_cat.txt");

my @fhs = (\*IN, \*OUT, \*NONENG);	# just to remove nagging bareword warnings

print STDERR "Reading 'skos_categories_en.nt'...\n";

while(<IN>){
	$inc++;
#	last if $. > 500000;
	
	if(m{^<http://dbpedia.org/resource/Category:([^>]+)> <http://www.w3.org/2004/02/skos/core#broader> <http://dbpedia.org/resource/Category:([^>]+)>}){
		$child = $1;
		$parent = $2;
	
		if($child =~ /%[89a-fA-F][0-9a-fA-F]/
							||
		   $parent =~ /%[89a-fA-F][0-9a-fA-F]/){
		   	
			$nonEngCount++;
			print NONENG "$child\t$parent\n";
			next;
		}
		
		cleanTerm($child, $parent);
	
		if(!$child){
			print STDERR "\nWeird line format: $_\n";
			next;
		}
		if(!$parent){
			print STDERR "\nWeird line format: $_\n";
			next;
		}
		
		print OUT "$child\t$parent\n";
		
		$outc++;
	}
	&$progresser();
}

print STDERR "\r$.\n";
print STDERR "$nonEngCount non-English entries ignored\n";
print STDERR "\r$inc lines read, $outc lines written\n";
