# Extract author-venue relations from dblp.extracted.txt
# Save in different formats: 
# blei: blei's LDA code
# vw: Vowpal Wabbit
# human: easy for human to read
use feature qw(switch say);

use strict;
use warnings 'all';
use Getopt::Std;
#use IO::File;
use List::Util qw(max);

use lib '.';
use NLPUtil;

use constant{
	OPTIONS 						=> 'p:',
};

my $OUTPUT_AUTHOR_MAX_AMBIGUITY	= 1.8;

my %opt;
getopts(OPTIONS, \%opt);

if(@ARGV == 0){
    die "Please specify the DBLP file to process\n";
}

my $M = INT_MAX;
my $processedOptionCount = 0;

if(exists $opt{'p'}){
	$M = $opt{'p'};
	if($M =~ /[^0-9]/){
		die "FATAL  maximum publication num '$M' is not understood\n";
	}
	print "No more than $M publications will be processed\n";
	$processedOptionCount++;
}

if(grep { OPTIONS !~ /$_/ } keys %opt){
	die "FATAL  Unknown options: ", join(',', keys %opt), "\n";
}

print "\n" if $processedOptionCount;

my $file = shift;

open_or_die(DB, "< $file");

openLogfile();

our $recordStartLn;
our $gRecordCount = 0;

my $venue;
my @authorNames;
my $pubYear;
my $thisPublication;

my $pubCount;
my $pubWithVenueCount = 0;
my $authorCount;

my @gVenues = ( "BUG" );
my %venue2ID;
my $venueGID = 1;

my %gAuthorVenues;
my %gPubCountByYear;

my %chnNameProb;
my %surnameProb;
my %givennameProb;

loadChnNameAmbig("./ambiguity.csv", \%surnameProb, \%givennameProb, \%chnNameProb);

NLPUtil::initialize( progressDelim => "\t", progressVars => 
						[ \$gRecordCount, \$pubWithVenueCount, \$venueGID, \$recordStartLn ], 
				noLoadGram => 1 );

while(!eof(DB)){
	$thisPublication = parseCleanDBLP(DB);
	
	$venue = $thisPublication->venue;
	$pubYear = $thisPublication->pubYear;
	
	@authorNames = @{ $thisPublication->authors };
	if(@authorNames > 3){	# keep the first 3 authors
		$#authorNames = 2;
	}
	
	if($venue){
		$pubWithVenueCount++;
		recordVenue($venue, $pubYear, \@authorNames);
	}
	
	if($gRecordCount >= $M){
		summary();
		print $tee "\nLast line being processed is ", $recordStartLn + 3, "\n";
		die "Exit early.\n";
	}
}

progress2();

summary();

sub getVenueID
{
	
	my $venue = shift;
	
	return key2id($venue, \%venue2ID, \@gVenues, $venueGID);

=pod
	my $id = $venue2ID{$venue};
	if(!defined($id)){
		$venue2ID{$venue} = $venueGID;
		$id = $venueGID;
		$venueGID++;
		push @gVenues, $venue;
	}

	return $id;	
=cut
	
}
	
sub recordVenue
{
	my ($venue, $year, $authorNames) = @_;
	
	$venue =~ s/ /-/g;
	
	my $id = getVenueID($venue);
	
	my $author;
	for $author(@$authorNames){
		$gAuthorVenues{$author}{$id}++;
	}
	
	$gPubCountByYear{$year}++;
	$pubCount++;
}

sub summary
{
	$authorCount = scalar keys %gAuthorVenues;

	print $tee "\n\n$gRecordCount records processed\n";
	
	print $tee c1000($pubCount), " publications by ", $authorCount, " authors.\n";
	if($pubCount > 0){
		print $tee $authorCount / $pubCount, " authors each publication.\n";
	}

#	print $tee "\nPublication breakdown by year:\n";
#	my @years = sort { $a <=> $b }keys %gPubCountByYear;
#	my $year;
#	for $year(@years){
#		print $tee "$year:\t", c1000($gPubCountByYear{$year}), "\n";
#	}
#	print $tee "\n";

	my $venueCount = $venueGID - 1;
	print $tee "$venueCount venues found\n";
	
	print $tee "Saving venue-id relations...\n";
	my $FH;
	
	open_or_die($FH, "> venue2id.txt");
	my $i;
	for($i = 1; $i < @gVenues; $i++){
		print $FH "$gVenues[$i]\t$i\n";
	}
	print $tee "Done.\n";
	
	my $venueFilename = "venues-vw.txt";
	dumpVenues($venueFilename, \%gAuthorVenues, "vw");
	
	$venueFilename = "venues-blei.txt";
	dumpVenues($venueFilename, \%gAuthorVenues, "blei");
	
	$venueFilename = "venues.txt";
	dumpVenues($venueFilename, \%gAuthorVenues, "human");
	
}

sub dumpVenues
{
	my ($filename, $authorVenues, $format) = @_;
	
	print $tee "Dumping venues into '$filename'... ";
	
	given($format){
		when(/^human$/){
			print $tee "(for human read)\n";
		}
		when(/^blei$/){
			print $tee "(blei format)\n";
		}
		when(/^vw$/){
			print $tee "(vw format)\n";
		}
		default{
			die "Unknown output format '$format'\n";
		}
	}
		
	my $FH;
	if(! open_or_warn($FH, "> $filename") ){
		return;
	}

	my $author;
	my $venueList;
	my $venueNum;
	my @venues;
	my $validAuthorCount = 0;
	
	my @authors = sort { keys %{ $authorVenues->{$b} } <=> keys %{ $authorVenues->{$a} } } 
						keys %$authorVenues;
	
	for $author(@authors){
		if( $chnNameProb{$author} && $chnNameProb{$author} > $OUTPUT_AUTHOR_MAX_AMBIGUITY ){
			next;
		}
		
		$venueList = $authorVenues->{$author};
		$venueNum = keys %$venueList;
		next if $venueNum == 1;
		
		@venues = sort { $venueList->{$b} <=> $venueList->{$a} 
										   ||
							           $a <=> $b
						} keys %$venueList;
		
		if($format eq "human"){
			print $FH "$author\t", join( "\t", map { "$gVenues[$_]:$venueList->{$_}" } @venues ), "\n";
		}
		elsif($format eq "blei"){
			print $FH "$venueNum ", join( " ", map { "$_:$venueList->{$_}" } @venues ), "\n";
		}
		elsif($format eq "vw"){
#			$author =~ s/ /-/g;
#			if($outAuthor){
#				print $FH "$author ";
#			}
			print $FH "| ", join( " ", map { "$_:$venueList->{$_}" } @venues ), "\n";
		}
		
		$validAuthorCount++;
	}
	
	print $tee "Done. $validAuthorCount authors' venues are dumped.\n";
}
