use feature qw(switch say);
use strict;
use warnings 'all';
use Getopt::Std;
use List::Util qw(sum);

use constant{
	OPTIONS						=> "v",
	namedisDir 					=> "/media/tough/namedis",
};

use lib namedisDir;
use NLPUtil;
use Distinct;

my %opt;
getopts(OPTIONS, \%opt);

my $isVerbose = 0;
if($opt{v}){
	$isVerbose = 1;
}

if(@ARGV < 2){
	die "Usage:\t$0 [-v] groundtruth-file arnet-file\n";
}

# for stat purpose only. a lot of pubs may be not matched.
my $groundtruthTotalPairCount = 0;
# matched groundtruth pairs. For calc'ing recall
my $matchedGroundtruthTotalPairCount = 0;
my $matchedGroundtruthPubCount = 0;

# for calc'ing prec
my $arnetTotalPairCount = 0;
# freqs of different (groundtruth) authors in each Arnet cluster. 
# For calc'ing correct pairs in each cluster
my %gAuthorCountInClust;
my $arnetTotalCorrectPairCount;

# map title-year to author ID, coauthor line, venue 
# plus the number of pubs in ground truth, if title-year is duplicate; 
# and matched number in arnet file
my %titleYear2IDAuVenue;

my %gNames;

# groundtruth publications
# the '0'th publication is a place holder, to make the ID starts from 1
my @gPublications = ("BUG");
# the next (new) identity's ID number
my $gIdID;
my @gIdentities;
my %gIdentity2id;

my @gAuthorPubCount;
my @gAuthorMatchedPubCount;

# arnet publications
# the '0'th publication is a place holder, to make the ID starts from 1
my @aPublications = ("BUG");
my $aIdID;
my @aIdentities;
my %aIdentity2id;
# the size of each cluster (coz each supposed author's publications are only in one cluster)
my @aClusterPubCount;
my @aMatchedPubCountPerClust;
my @aUnmatchedPubCountPerClust;
my @aCorrectPairCountPerClust;
my @aPairCountInClust;

loadGroundtruth($ARGV[0]);
loadArnet($ARGV[1]);

sub gIdentity2id
{
	my $identity = shift;
	
	# an "N/A" may be followed by comments/reasons
	if($identity =~ m{^N/A}){
		return -1;
	}
	
	return key2id($identity, \%gIdentity2id, \@gIdentities, $gIdID);
}

sub aIdentity2id
{
	my $identity = shift;
	
	return key2id($identity, \%aIdentity2id, \@aIdentities, $aIdID);
}

sub loadGroundtruth
{
	my $truthFilename = shift;
	print $tee "Open groundtruth file '$truthFilename' to process...\n";

	my $DB;
	if(! open_or_warn($DB, "< $truthFilename")){
		return;
	}
	
	$groundtruthTotalPairCount = 0;
	
	%titleYear2IDAuVenue = ();
	@gPublications = ("BUG");

	$gIdID = 1;
	@gIdentities = ("BUG");
	%gIdentity2id = ();
	@gAuthorPubCount = ("BUG");
	@gAuthorMatchedPubCount = ("BUG");
	
	my $expectClusterHeading = 1;
	my $line;
	my ($clustID, $clustSize, $identity);
	my $authorID;
	
	$clustSize = 0;
	my $readcount = 0;
	
	my $title;
	my $authorLine;
	my $yearVenueLine;
	my $thisPublication;
	my @authorNames;

	my $name;
	my $pubID;
	
	while(!eof($DB)){
		$line = <$DB>;
		trim($line);
		if(!$line){
			if($readcount != $clustSize){
				print $tee $DB->input_line_number, ": Cluster size $clustSize != $readcount (read count)\nStop reading the file.\n";
				return 0;
			}
			$readcount = 0;

			$expectClusterHeading = 1;
			next;
		}
		
		if($. == 1 && $line =~ /^\d+ clusters\.$/){
			next;
		}
		
		if($expectClusterHeading){
			if($line =~ /Cluster (\d+), (\d+) papers:(\s+(.+))?$/){
				$clustID = $1;
				$clustSize = $2;
				$identity = $4;
				
				trim($identity);
				$identity =~ tr/()/[]/;
				
				$authorID = gIdentity2id($identity);
				
				$expectClusterHeading = 0;
				next;
			}
			else{
				print $tee "$.: Unknown cluster heading:\n$line\nStop reading the file.\n";
				return 0;
			}
		}
		
		$title = $line;
		$authorLine = <$DB>;
		$yearVenueLine = <$DB>;
		
		# some papers (very few) couldn't be retrieved from Internet, so they are discarded
		# ignore clusters whose identities are not given, i.e., clusters not labeled
		if($authorID == -1){
			$readcount++;
			next;
		}
		
		trim($authorLine, $yearVenueLine);
		
		$thisPublication = parseDBLPBlock($title, $authorLine, $yearVenueLine);
		$thisPublication->authorID($authorID);
		
		$gAuthorPubCount[$authorID]++;
		$readcount++;
		
		$title = $thisPublication->title;
		trimPunc($title);
		$thisPublication->title($title);
		
		@authorNames = @{ $thisPublication->authors };
	
		$pubID = @gPublications;
		push @gPublications, $thisPublication;
		
		my $isNameReverse = $thisPublication->isNameReverse;
		if($isNameReverse < 0){
			next;
		}

		
		my ($year, $venue);
		$year  = $thisPublication->year;
		$venue = $thisPublication->venue;

		$authorLine = join(",", @{$thisPublication->authors} );
		
		my $titleYear = "$title-$year";
		if( exists $titleYear2IDAuVenue{$titleYear} ){
			$titleYear2IDAuVenue{$titleYear}->{groundCount}++;
			print $tee "WARN: Two papers are with the same title/year:\n";
			my $prevPubID = $titleYear2IDAuVenue{$titleYear}->{pubID};
			dumpPub( $tee, $gPublications[$prevPubID] );
			dumpPub( $tee, $thisPublication );
			print $tee "\n";
		}
		else{
			$titleYear2IDAuVenue{$titleYear} = { venue => $venue, authorLine => $authorLine, 
												groundCount => 1, 
												arnetPubIDs => [], arnetCount => 0, 
												authorID => $authorID, pubID => $pubID
												 };
		}												
	}
	
	print $tee scalar @gPublications - 1, " publications of ", $gIdID - 1, " authors loaded\n";
	
	my @authorIndices = sort { $gAuthorPubCount[$b] <=> $gAuthorPubCount[$a] } ( 1 .. $gIdID - 1 );

	print $tee join(" | ", map { "$gIdentities[$_]: $gAuthorPubCount[$_]" } @authorIndices );
	print $tee "\n";

	my $i;
	for($i = 1; $i < $gIdID; $i++){
		$groundtruthTotalPairCount += NChoose2( $gAuthorPubCount[$i] );
	}
	print $tee "Groundtruth total pairs: $groundtruthTotalPairCount\n\n";
}

sub loadArnet
{
	my $arnetFilename = shift;
	print $tee "Open Arnetminer file '$arnetFilename' to process...\n";

	my $DB;
	if(! open_or_warn($DB, "< $arnetFilename")){
		return;
	}
	
	$matchedGroundtruthPubCount = 0;
	
	$arnetTotalPairCount = 0;
	%gAuthorCountInClust = ();
	
	@aPublications = ("BUG");

	$aIdID = 1;
	@aIdentities = ("BUG");
	%aIdentity2id = ();
	@aClusterPubCount = ("BUG");
	@aMatchedPubCountPerClust = ("BUG");
	@aUnmatchedPubCountPerClust = ("BUG");
	
	my $expectClusterHeading = 1;
	my $line;
	my ($clustID, $clustSize, $identity);
	my $authorID = -1;
	
	$clustSize = 0;
	my $readcount = 0;
	
	my $title;
	my $authorLine;
	my $yearVenueLine;
	my $thisPublication;
	my @authorNames;

	my $name;
	my $pubID;
	
	while(!eof($DB)){
		$line = <$DB>;
		trim($line);
		if(!$line){
			if($readcount != $clustSize){
				print $tee $DB->input_line_number, ": Cluster size $clustSize != $readcount (read count)\nStop reading the file.\n";
				return 0;
			}
			$readcount = 0;

			$expectClusterHeading = 1;
			
			# Has read at least one cluster
			if($authorID >= 1){
				print "$identity:\n";
				my $matchedPubCountInClust = $aMatchedPubCountPerClust[$authorID] || 0;
				my $unmatchedPubCountInClust = $aUnmatchedPubCountPerClust[$authorID] || 0;
								
				print $tee "$aClusterPubCount[$authorID] pubs read, $unmatchedPubCountInClust unmatched. $matchedPubCountInClust matched, distribution:\n";
				if( $aClusterPubCount[$authorID] != $unmatchedPubCountInClust + $matchedPubCountInClust ){
					print $tee "!!!!!! FATAL: cluster count inconsistent\n";
				}

				my @gAuthorIDsInClust = sort { $gAuthorCountInClust{$b} <=> $gAuthorCountInClust{$a} } keys %gAuthorCountInClust;
				print $tee join(" | ", map { "$gIdentities[$_]: $gAuthorCountInClust{$_}" } @gAuthorIDsInClust );
				print "\n\n";
				
				$aPairCountInClust[$authorID] = NChoose2($matchedPubCountInClust);
				$aCorrectPairCountPerClust[$authorID] = 0;
				for(values %gAuthorCountInClust){
					$aCorrectPairCountPerClust[$authorID] += NChoose2($_);
				}
				%gAuthorCountInClust = ();
			}
			
			next;
		}
		
		if($. == 1 && $line =~ /^\d+ clusters\.$/){
			next;
		}
		
		if($expectClusterHeading){
			if($line =~ /Cluster (\d+), (\d+) papers:(\s+(.+))?$/){
				$clustID = $1;
				$clustSize = $2;
				$identity = $4;
				
				trim($identity);
				$identity =~ tr/()/[]/;
				
				$authorID = aIdentity2id($identity);
				
				$expectClusterHeading = 0;
				next;
			}
			else{
				print $tee "$.: Unknown cluster heading:\n$line\nStop reading the file.\n";
				return 0;
			}
		}
		
		$title = $line;
		$authorLine = <$DB>;
		$yearVenueLine = <$DB>;
		
		# some papers (very few) couldn't be retrieved from Internet, so they are discarded
		# ignore clusters whose identities are not given, i.e., clusters not labeled
		if($authorID == -1){
			$readcount++;
			next;
		}
		
		trim($authorLine, $yearVenueLine);
		
		$thisPublication = parseDBLPBlock($title, $authorLine, $yearVenueLine);
		$thisPublication->authorID($authorID);
		
		$aClusterPubCount[$authorID]++;
		$readcount++;
		
		$title = $thisPublication->title;
		trimPunc($title);
		$thisPublication->title($title);
		
		@authorNames = @{ $thisPublication->authors };
	
		$pubID = @aPublications;
		push @aPublications, $thisPublication;
		
#		my $isNameReverse = $thisPublication->isNameReverse;
#		if($isNameReverse < 0){
#			next;
#		}

		
		my ($year, $venue);
		$year  = $thisPublication->year;
		$venue = $thisPublication->venue;

		$authorLine = join(",", @{$thisPublication->authors} );
		
		my $titleYear = "$title-$year";
		if( exists $titleYear2IDAuVenue{$titleYear} ){
			$titleYear2IDAuVenue{$titleYear}->{arnetCount}++;
			push @{ $titleYear2IDAuVenue{$titleYear}->{arnetPubIDs} }, $pubID;
			if( $titleYear2IDAuVenue{$titleYear}->{arnetCount} > 
				$titleYear2IDAuVenue{$titleYear}->{groundCount} ){
				print $tee "!!!!!! WARN: Too many papers matching the same groundtruth paper(s):\n";
				my @matchingArnetPubIDs = @{ $titleYear2IDAuVenue{$titleYear}->{arnetPubIDs} };
				for(@matchingArnetPubIDs){
					dumpPub( $tee, $aPublications[$_] );				
				}
				print $tee "Groundtruth paper:\n";
				my $gPaperID = $titleYear2IDAuVenue{$titleYear}->{pubID};
				dumpPub( $tee, $gPublications[$gPaperID] );
				
				# still regards as being unmatched
				$aUnmatchedPubCountPerClust[$authorID]++;
			}
			else{
				my $matchedAuthorID = $titleYear2IDAuVenue{$titleYear}->{authorID};
				$gAuthorCountInClust{$matchedAuthorID}++;
				# since one author is in and only in one cluster, $authorID acts as the cluster ID
				$aMatchedPubCountPerClust[$authorID]++;
				$gAuthorMatchedPubCount[$matchedAuthorID]++;
				$matchedGroundtruthPubCount++;
			}
		}
		else{
			if($isVerbose){
				print $tee "Unmatched:\n";
				dumpPub( $tee, $thisPublication );
			}
			# since one author is in and only in one cluster, $authorID acts as the cluster ID
			$aUnmatchedPubCountPerClust[$authorID]++;
		}
	}
	
	print $tee scalar @aPublications - 1, " publications of ", $aIdID - 1, " authors loaded\n";
	
	my @nonemptyAuthorIndices = grep { $aMatchedPubCountPerClust[$_] && $aMatchedPubCountPerClust[$_] > 0 } ( 1 .. $aIdID - 1 );
	my @authorIndices = sort { $aMatchedPubCountPerClust[$b] <=> $aMatchedPubCountPerClust[$a] } @nonemptyAuthorIndices;

	print $tee join(" | ", map { "$aIdentities[$_]: $aMatchedPubCountPerClust[$_]" } @authorIndices );
	print $tee "\n\n";

	$arnetTotalPairCount = sum( grep { defined } @aPairCountInClust);
	$arnetTotalCorrectPairCount = sum( grep { defined } @aCorrectPairCountPerClust);
	
	$matchedGroundtruthTotalPairCount = 0;
	my $i;
	for($i = 1; $i < $gIdID; $i++){
		next if  ! $gAuthorMatchedPubCount[$i];
		
		$matchedGroundtruthTotalPairCount += NChoose2($gAuthorMatchedPubCount[$i]);
	}

	my $matchedGroundtruthPubCount2 = sum( map { $_->{arnetCount} } values %titleYear2IDAuVenue );
	my $matchedGroundtruthPubCount3 = scalar grep { $_->{arnetCount} > 0 } values %titleYear2IDAuVenue;
	
	if( $matchedGroundtruthPubCount != $matchedGroundtruthPubCount2 ){
		print $tee "!!!!!! WARN: Matched groundtruth pub counts disagree: $matchedGroundtruthPubCount != $matchedGroundtruthPubCount2\n";
	}

	print $tee scalar @gPublications - 1, " groundtruth publications, $matchedGroundtruthPubCount matched, $matchedGroundtruthPubCount3 matched title-year\n";
	
	print $tee "Groundtruth pairs total: $groundtruthTotalPairCount, between matched pubs: $matchedGroundtruthTotalPairCount\n";
	print $tee "Arnet total pairs: $arnetTotalPairCount\n";
	print $tee "Arnet total correct pairs: $arnetTotalCorrectPairCount\n";
	
	my $precision = $arnetTotalCorrectPairCount / $arnetTotalPairCount;
	my $recall    = $arnetTotalCorrectPairCount / $matchedGroundtruthTotalPairCount;
	my $f1        = f1($precision, $recall);

	($precision, $recall, $f1) = trunc(4, $precision, $recall, $f1);

	print $tee "Summary:\n";
	print $tee "Prec: $precision. Recall: $recall. F1: $f1\n\n";
	
}

