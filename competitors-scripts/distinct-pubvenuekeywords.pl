use strict;
use lib '.';
use NLPUtil;

use Distinct;

# use string format, to keep the order while sorted
my $unknownVenueSN = "0000";
my @unknownVenues;

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

NLPUtil::initialize( progressDelim => "\t", 
				progressVars => [ \$gRecordCount, \$recordStartLn, \$unknownVenueSN ],
				lemmaCacheLoadFile => "/home/shaohua/wikipedia/lemma-cache.txt", 
				noLoadGram => 1 
				   );

loadChosenConfs("${dirPrefix}distinct-venues0.txt");
loadChosenAuthors("${dirPrefix}distinct-authors.txt");
loadKeywordTable("${dirPrefix}distinct-keywords.txt");

my $pubkey;

my @pubkeys;

my %pubKeywords;
#my %authorKeywords;
my %confKeywords;

my %venueHistory;

my %pub2conf;
my %author2pubs;

my ($title, @authorNames, $year, $venue);
my (@unigrams, @bigrams);
my $w;

my $DB;
open($DB, "< dblp.extracted.txt");

my $thisPublication;
my $author;

my $authorChosenCount;
my $confkey;

while(!eof($DB)){
	$thisPublication = parseCleanDBLP($DB);
	
	$venue = $thisPublication->venue;
	$year = $thisPublication->year;
	$title = $thisPublication->title;
	$pubkey = $thisPublication->pubkey;
	$year = $thisPublication->year;

	if($year > $yearThres && !$safeKeys{$pubkey}){
		next;
	}
		
	@authorNames = @{ $thisPublication->authors };
	@authorNames = replaceAuthorNames(@authorNames);
	
	if( 0 == grep { exists $chosenAuthors{$_} } @authorNames ){
		next;
	}
	
	if(! $venue){
		# lower case "u", to make them at the end when sorting all venue names
		$venue = "unknown venue $unknownVenueSN";
		$confkey = "$venue, $year";
		push @unknownVenues, [ $confkey, $venue, $year ];
		$unknownVenueSN++;
	}
	else{
		$confkey = "$venue, $year";
		if(! exists $chosenConfs{$confkey}){
			$maxConfIndex++;
			# update %chosenConfs & %chosenConfs2. %chosenConfs will be used later, so need be updated
			# $chosenConfs{$confkey}{papercount} is unused, so don't set it
			$chosenConfs{$confkey} = { index => $maxConfIndex, venue => $venue, year => $year };
		}
	}
		
	extractTitleGrams($title, \@unigrams, \@bigrams, 1);
	
	$authorChosenCount = 0;

	$venueHistory{$venue}{$year}++;
	$venueHistory{$venue}{all}++;
	
	for $author(@authorNames){
		if(! $chosenAuthors{$author} ){
			next;
		}
		$authorChosenCount++;
		
		# first chosen author. It's to add pub keywords only once for each title
		if($authorChosenCount == 1){
			for $w(@unigrams){
				if($chosenKeywords{$w}){
					$pubKeywords{$pubkey}{$w}++;
				}
			}
			push @pubkeys, $pubkey;
			
			$pub2conf{$pubkey} = $confkey;
			
			for $w(@unigrams){
				if($chosenKeywords{$w}){
					$confKeywords{$confkey}{$w}++;
				}
			}
		}
		
		push @{ $author2pubs{$author} }, $pubkey;
		
		# author keywords are not used in DISTINCT
#		for $w(@unigrams){
#			if($chosenKeywords{$w}){
#				$authorKeywords{$author}{$w}++;
#			}
#		}

	}
}

progress2();
print STDERR "\n";

print STDERR "Pubs with unknown venues: $unknownVenueSN\n";

# @unknownVenues: [ $confkey, $venue, $year ];
my $unknownVenueTuple;
for $unknownVenueTuple(@unknownVenues){
	($confkey, $venue, $year) = @$unknownVenueTuple;
	$maxConfIndex++;
	# update %chosenConfs & %chosenConfs2. %chosenConfs will be used later, so need be updated
	$chosenConfs{$confkey} = { index => $maxConfIndex, venue => $venue, year => $year };
}

my $PUBS;
open_or_die($PUBS, "> ${dirPrefix}distinct-pubs.txt");

my $index = 0;
for $pubkey(@pubkeys){
	print $PUBS join( "\t", $index, $pubkey, $pub2conf{$pubkey} ), "\n";
	$index++;
}
print STDERR "$index publications saved into '${dirPrefix}distinct-pubs.txt'\n";

dumpKeywords( \@pubkeys, \%pubKeywords, "${dirPrefix}distinct-pubkeywords.txt" );

my $PUBLISH;
open_or_die($PUBLISH, "> ${dirPrefix}distinct-publish.txt");

$index = 0;
my @authors = sort { $chosenAuthors{$a}{index} <=> $chosenAuthors{$b}{index} } keys %author2pubs;
my @authorPubkeys;

for $author(@authors){
	@authorPubkeys = @{ $author2pubs{$author} };
	
	for $pubkey(@authorPubkeys){
		print $PUBLISH join( "\t", $index, $author, $pubkey ), "\n";
		$index++;
	}
}

print STDERR "$index publish relations saved into '${dirPrefix}distinct-publish.txt'\n";

my @confs   = sort { $chosenConfs{$a}{index} <=> $chosenConfs{$b}{index} }   keys %confKeywords;

dumpKeywords( \@confs, \%confKeywords, "${dirPrefix}distinct-confkeywords.txt" );

#my @authors = sort { $chosenAuthors{$a}{index} <=> $chosenAuthors{$b}{index} } keys %authorKeywords;
#dumpKeywords( \@authors, \%authorKeywords, "distinct-authorkeywords.txt" );

print STDERR scalar keys %venueHistory, " venues\n";

my @venues = sort { scalar keys %{$venueHistory{$b}} <=> scalar keys %{$venueHistory{$a}}
													 ||
							  $venueHistory{$b}{all} <=> $venueHistory{$a}{all}
							  						 ||
							  					 $a cmp $b
				  } keys %venueHistory;

my $VENUES;
open_or_die($VENUES, "> ${dirPrefix}distinct-venues.txt");

my $venue;
my @venueYears;
my $year;

$index = 0;

for $venue(@venues){
	@venueYears = sort { $a <=> $b } keys %{$venueHistory{$venue}};
	
	for $year(@venueYears){
		next if $year eq "all";
		
		print $VENUES join( "\t", $index, "$venue, $year", $venue, $year, $venueHistory{$venue}{$year} ), "\n";
		$index++;
	}
}
print STDERR "$index venue-year pairs saved into '${dirPrefix}distinct-venues.txt'\n";
