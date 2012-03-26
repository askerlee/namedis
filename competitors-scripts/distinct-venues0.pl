use strict;
use lib '.';
use NLPUtil;
use Distinct;

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

my $DB;
open($DB, "< dblp.extracted.txt");

my $thisPublication;
my ($year, $venue, $venueType);

my %venueHistory;

while(!eof($DB)){
	$thisPublication = parseCleanDBLP($DB);
	$year = $thisPublication->year;
	$venue = $thisPublication->venue;
	$venueType = $thisPublication->type;

	if($year > $yearThres){
		next;
	}
		
	# in DISTINCT, all types are considered
	if( $venue ){
		$venueHistory{$venue}{$year}++;
		$venueHistory{$venue}{all}++;
	}
}
print STDERR "\n";
print STDERR scalar keys %venueHistory, " venues\n";

my @venues = sort { scalar keys %{$venueHistory{$b}} <=> scalar keys %{$venueHistory{$a}}
													 ||
							  $venueHistory{$b}{all} <=> $venueHistory{$a}{all}
				  } keys %venueHistory;

my $VENUES;
open_or_die($VENUES, "> ${dirPrefix}distinct-venues0.txt");

my $venue;
my $index = 0;

my @venueYears;
my $year;

for $venue(@venues){
	@venueYears = sort { $a <=> $b } keys %{$venueHistory{$venue}};
	
	# @venueYears -1, cuz "all" is in @venueYears
	next if @venueYears -1 < $VENUE_YEAR_THRES || $venueHistory{$venue}{all} < $VENUE_PUB_SUM_THRES;

	for $year(@venueYears){
		next if $year eq "all";
		
		print $VENUES join( "\t", $index, "$venue, $year", $venue, $year, $venueHistory{$venue}{$year} ), "\n";
		$index++;
	}
}

