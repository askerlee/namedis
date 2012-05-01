use strict;

use constant{
	namedisDir 					=> "/media/tough/namedis",
	wikipediaDir 				=> "/media/first/wikipedia",
};

use lib namedisDir;
use NLPUtil;
use Distinct;

use lib wikipediaDir;
use ConceptNet;

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

NLPUtil::initialize( progressDelim => "\t", progressVars => [ \$gRecordCount, \$recordStartLn ], 
				noLoadGram => 1 );

loadChosenConfs("${dirPrefix}distinct-venues0.txt");

my %authorPubCount;

my ($title, @authorNames, $year, $venue, $pubkey);

my $DB;
open($DB, "< dblp.extracted.txt");

my $thisPublication;
my $confkey;

while(!eof($DB)){
	$thisPublication = parseCleanDBLP($DB);
	
	$venue = $thisPublication->venue;
	$year = $thisPublication->year;
	$pubkey = $thisPublication->pubkey;
	
	if($year > $yearThres && !$safeKeys{$pubkey}){
		next;
	}
	
	$confkey = "$venue, $year";
	
	if(! $chosenConfs{$confkey}){
		next;
	}
	
	$title = $thisPublication->title;
	@authorNames = @{ $thisPublication->authors };
	@authorNames = replaceAuthorNames(@authorNames);
	
#	if(@authorNames > 3){
#		$#authorNames = 2;
#	}
	
	for(@authorNames){
		$authorPubCount{$_}++;
	}
}

progress2();
print STDERR "\n";

print STDERR scalar keys %authorPubCount, " authors found\n";

my ($author, $pubcount);

while( ($author, $pubcount) = each %authorPubCount){
	if( $pubcount < $AUTHOR_PUBCOUNT_THRES ){
		delete $authorPubCount{$author};
	}
}
print STDERR scalar keys %authorPubCount, " authors have >= $AUTHOR_PUBCOUNT_THRES papers\n";

my @authors = sort { $authorPubCount{$b} <=> $authorPubCount{$a} } keys %authorPubCount;

my $AUTHORS;
open_or_die($AUTHORS, "> ${dirPrefix}distinct-authors.txt");

my $author;
my $index = 0;
for $author(@authors){
	print $AUTHORS join( "\t", $index, $author, $authorPubCount{$author} ), "\n";
	$index++;
}
