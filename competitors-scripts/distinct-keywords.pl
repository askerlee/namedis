use strict;
use lib '.';
use NLPUtil;

use Getopt::Std;
my %opt;
getopts("p:y:", \%opt);

my $dirPrefix = "";
if(exists $opt{'p'}){
	$dirPrefix = $opt{'p'};
	if( $dirPrefix !~ /\/$/ ){
		$dirPrefix .= "/";
	}
	print STDERR "Data file path prefix: '$dirPrefix'\n";
}

my $yearThres = 2100;
if(exists $opt{'y'}){
	$yearThres = $opt{'y'};
	print $tee "Only publications with year <= $yearThres will be considered\n";
}

NLPUtil::initialize( lemmaCacheLoadFile => "/home/shaohua/wikipedia/lemma-cache.txt",
						noLoadGram => 1 );

open(TITLES, "< titles.txt");

my $line;
my (@unigrams, @bigrams);
my $w;
my %wordfreq;

my $progresser = makeProgresser( vars => [ \$. ] );

while($line = <TITLES>){
	extractTitleGrams($line, \@unigrams, \@bigrams, 1);
	for $w(@unigrams){
		$wordfreq{$w}++;
	}
	&$progresser();
}

print STDERR "$. titles processed\n";
print STDERR scalar keys %wordfreq, " unique words\n";

# delete impossible candidates to save sorting time
for $w (keys %wordfreq){
	if($wordfreq{$w} < 10){
		delete $wordfreq{$w};
	}
}

print STDERR scalar keys %wordfreq, " words with freq >= 10\n";

my @topwords = sort { $wordfreq{$b} <=> $wordfreq{$a} } keys %wordfreq;
my $N = 2568;

$#topwords = $N - 1;

my @top50 = splice @topwords, 0, 50;
print STDERR "Top 50 words removed as stop words:\n", join(", ", @top50), "\n";

open(KW, "> ${dirPrefix}distinct-keywords.txt");

my $idx = 0;
for $w(@topwords){
	print KW "$idx\t$w\t$wordfreq{$w}\n";
	$idx++;
}
print STDERR "$idx words saved to 'distinct-keywords.txt'\n";
