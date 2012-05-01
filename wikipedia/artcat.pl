# process article_categories_en.nq and produce article-category relations

#<http://dbpedia.org/resource/River_Valley_Charter_School> 
#<http://purl.org/dc/terms/subject> 
#<http://dbpedia.org/resource/Category:High_schools_in_San_Diego_County,_California> .
use strict;
use warnings 'all';

use lib '/media/tough/namedis';
use NLPUtil;
use lib '.';
use ConceptNet;

my ($article, $origArticle, $lastOrigArticle, $categ);
my $lastarticle = "";
my @cats;
my $beginning = 1;

my %seenwords;
my $nonEngCount = 0;
my $dupCount = 0;
my $validCount = 0;

$| = 1;

#if(@ARGV < 2){
#	die "Usage: $0 input_file output_file\n";
#}
#	
#open_or_die(IN, "< $ARGV[0]");
#open_or_die(OUT, "> $ARGV[1]");

my $inFilename	= "extraction/en/article_categories_en.nt";
my $outFilename = "cat0.txt";

open_or_die(IN,		"< $inFilename");
open_or_die(OUT, 	"> $outFilename");
open_or_die(NONENG, "> nonenglish_art_cat.txt");

my @fhs = (\*IN, \*OUT, \*NONENG);	# just to remove nagging bareword warnings

while(<IN>){
	if($. % 10000 == 0){
		print STDERR "\r$.\r";
	}
	($article, $categ) = (m{^<http://dbpedia.org/resource/([^>]+)> <[^>]+> <http://dbpedia.org/resource/Category:([^>]+)>});
	if($article =~ /%[89a-fA-F][0-9a-fA-F]/
						||
	   $categ =~ /%[89a-fA-F][0-9a-fA-F]/){
	   	
		$nonEngCount++;
		print NONENG "$article\t$categ\n";
		next;
	}
	
	$origArticle = $article;
	cleanTerm($article, $categ);
#	$article =~ s/_/ /g;
#	$article =~ s/%([0-9a-fA-F]{2})/chr(hex($1))/eg;
#	$categ =~ s/_/ /g;
#	$categ =~ s/%([0-9a-fA-F]{2})/chr(hex($1))/eg;
	
	if(!$article){
		print STDERR "\nWeird line format: $_\n";
		next;
	}
	if($article eq $lastarticle){
		push @cats, $categ;
	}
	else{
		if(!$beginning){
			if(exists $seenwords{$lastarticle}){
				print STDERR "\r$.\n'$lastarticle ($lastOrigArticle)' was seen before (CAT: '", join("|", @cats), "' discarded)\n";
				$dupCount++;
			}
			else{
				$seenwords{$lastarticle} = 1;
				print OUT "$lastarticle\t", join("|", @cats), "\n";
				$validCount++;
			}
		}
		$beginning = 0;	
		$lastarticle = $article;
		$lastOrigArticle = $origArticle;
		@cats = ($categ);
	}
}

if(exists $seenwords{$lastarticle}){
	print STDERR "\r$.\n'$lastarticle' was seen before (CAT: '", join("|", @cats), "' discarded)\n";
	$dupCount++;
}
else{
	print OUT "$lastarticle\t", join("|", @cats), "\n";
	$validCount++;
}
			
print STDERR "\r$.\n";
print STDERR "$nonEngCount non-English entries ignored\n";
print STDERR "$dupCount duplicate entries ignored\n";
print STDERR "$validCount valid entries output\n";
