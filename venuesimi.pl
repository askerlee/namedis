use strict;
use warnings 'all';
use lib '.';
use NLPUtil;
use Distinct;
use Statistics::Descriptive;

NLPUtil::initialize( progressDelim => "\t", 
				progressVars => [ \$gRecordCount, \$recordStartLn ],
				noLoadGram => 1 
				   );

loadChosenConfs('distinct-venues0.txt');
loadChosenAuthors('distinct-authors.txt');

my $DB;
open($DB, "< dblp.extracted.txt");

my %author2venues;
my %venue2authors;

my %authorPubCount;
my %venuePubCount;

my %author2id;
my %venue2id;
my $authorGID = 0;
my $venueGID = 0;

my @authors;
my $author;
my $authorID;

my @venues;
my $venue;
my $venueID;
# the index value in 'distinct-venues0.txt'. for sorting only
my @venueIndices;

my $thisPublication;
my @authorNames;

while(!eof($DB)){
	$thisPublication = parseCleanDBLP($DB);
	
	$venue = $thisPublication->venue;
	if(! $venue || !exists $chosenConfs2{$venue}){
		next;
	}
	
	$venueID = key2id($venue, \%venue2id, \@venues, $venueGID);
	$venueIndices[$venueID] = $chosenConfs2{$venue};
	
	@authorNames = @{ $thisPublication->authors };
	
	if($#authorNames > 2){
		$#authorNames = 2;
	}
	
	for $author(@authorNames){
		if(! $chosenAuthors{$author}){
			next;
		}
		$authorID = key2id($author, \%author2id, \@authors, $authorGID);
		$author2venues{$authorID}{$venueID}++;
		$venue2authors{$venueID}{$authorID}++;
		$authorPubCount{$authorID}++;
		# each author contributes one count. cuz when comparing venue1 with venue2,
		# the total count by all shared authors is repetitive (diff authors may contribute to one pub). 
		# So venue1 pub counting is also reptitive, to make their ratio fair
		$venuePubCount{$venueID}++; 
	}
	# if all authors are not chosen, $venuePubCount{$venueID} is 0.
}

progress2();
print STDERR "\n";

print STDERR scalar keys %venue2authors, " venues, ", scalar keys %author2venues, " authors.\n";

my $VENUE_SIMI_THRES = 0.2;

my ($i, $j);

# pred_i = actual_i * Sigma( actual_i ) / Sigma ( x_i )
# $residueVar: stdandarized variance. Sigma( (actual_i - pred_i)^2 ) / Sigma ( (x_i)^2 )
# Use it to make the variance scale-free and less influenced by how big i is
# e.g., Sigma( actual_i ) = Sigma( x_i ) = 40. 
# in the first case, { actual_i | i = 1,2 } = { 10,30 }, { x_i } = { 20,20 }.
# so $residueVar = ( (10 - 20)^2 + (30 - 20)^2 ) / ( 20^2 + 20^2 ) = 0.25
# in the second case, { actual_i | i = 1,2,3,4 } = { 5,5,15,15 }, { x_i } = { 10,10,10,10 }.
# so $residueVar = ( (5 - 10)^2 + (5 - 10 )^2 + (15 - 10)^2 + (15 - 10)^2 ) / ( 10^2 * 4) = 0.25
# the two $residueVar's are the same (they should be the same since they are proportional.
# The only difference is in the second case the two predicted sets are split into halves,
# but the ratios are the same)
# This measure is proposed by me (maybe someone else has proposed it but I don't find it in wikipedia)
# $residueDev: standardized deviation. $residueDev = $residueVar / ( $relativeFreq ^ 2)
my ($simi, $residueDev, $linregSimi, $linregResidueDev);

my @venueSimis;

my $simicount;
my $totalcount = 0;
my $progresser = makeProgresser( vars => [ \$i, \$j, \$simicount, \$totalcount ], step => 10 );
my ($count1, $count2);

for($i = 0; $i < $venueGID; $i++){
	# it could be nonexistent. if 0, calcVenueSimi will get 0/0. so skip this venue
	next if ! $venuePubCount{$i};

	for($j = 0; $j < $venueGID; $j++){
		next if $i == $j;
		next if ! $venuePubCount{$j};
		
		($simi, $residueDev, $linregSimi, $linregResidueDev, $count1, $count2) = calcVenueSimi($i, $j, $venue2authors{$i}, $venue2authors{$j});
		if($simi >= $VENUE_SIMI_THRES){
			push @venueSimis, [ $i, $j, $simi, $residueDev, $linregSimi, $linregResidueDev, $count1, $count2 ];
			$simicount++;
		}
		$totalcount++;
	}
	&$progresser();
}
&$progresser(1);

print STDERR "Sorting venue pairs by their similarity...\n";

@venueSimis = sort {
					 # ascending as the index of the first venue. most popular venues first
					 $venueIndices[ $a->[0] ] <=> $venueIndices[ $b->[0] ] 	
					 		 				   ||	
	  								  $b->[2] <=> $a->[2] 	# simi, descending
 							 				   ||
					# ascending as the index of the second venue			   
					 $venueIndices[ $a->[1] ] <=> $venueIndices[ $b->[1] ]	# $j 
				   } @venueSimis;

print STDERR "Done.\n";
print STDERR "Saving similar venue pairs to 'venue-simi.txt'...\n";

my $VENUESIMI;
open_or_die($VENUESIMI, "> venue-simi.txt");

$progresser = makeProgresser( vars => [ \$i ], step => 1000 );

my ($v1, $v2);

for($i = 0; $i < @venueSimis; $i++){
	($v1, $v2, $simi, $residueDev, $linregSimi, $linregResidueDev, $count1, $count2) = @{ $venueSimis[$i] };
	print $VENUESIMI join( "\t", $venues[$v1], $venues[$v2], $simi, $residueDev, $linregSimi, $linregResidueDev, $count1, $count2), "\n";
	&$progresser();
}
progress_end($i);

sub calcVenueSimi
{
	my ($venueID1, $venueID2, $authorList1, $authorList2) = @_;
	
	my $authorID;
	my ($count1, $count2);
	
	$count1 = $venuePubCount{$venueID1};
	$count2 = 0;
	
	my @sharedAuthors;
	#my @ratios;
	my $n = 0;
	my (@xs, @ys);
	
	for $authorID(keys %$authorList1){
		$n++;
		push @xs, $authorList1->{$authorID};
		
		if(exists $authorList2->{$authorID}){
			$count2 += $authorList2->{$authorID};
			#push @ratios, $authorList2->{$authorID} / $authorList1->{$authorID};
			push @ys, $authorList2->{$authorID};
		}
		else{
			push @ys, 0;
		}
	}
	
	my $relativeFreq = $count2 / $count1;

	if($relativeFreq == 0){
		return (0, 0, 0, 0, 0, 0);
	}
		
#	my $stat = Statistics::Descriptive::Sparse->new();
#	$stat->add_data(@ratios);
#	my $linregSimi = $stat->mean();
#	my $linregResidueDev = $stat->standard_deviation();
	
	my ($predCount, $linregPredCount);
	my ($sqrError, $linregSqrError) = (0, 0);
	my ($residueVar, $linregResidueVar);
	my ($residueDev, $linregResidueDev);
	
	my ($Sxx, $Sxy) = (0, 0);
	my $i;
	
	for($i = 0; $i < $n; $i++){
		$Sxx += $xs[$i] ** 2;
		$Sxy += $xs[$i] * $ys[$i];
	}
	
	my $linregSimi = $Sxy / $Sxx;

	for($i = 0; $i < $n; $i++){
		$predCount = $xs[$i] * $relativeFreq;
		$sqrError += ( $ys[$i] - $predCount ) ** 2;

		$linregPredCount = $xs[$i] * $linregSimi;	
		$linregSqrError += ( $ys[$i] - $linregPredCount ) ** 2;
	}
	
	$residueVar = $sqrError / $Sxx;
	$residueVar /= ( $relativeFreq ** 2 );
	$residueDev = sqrt($residueVar);
	
	$linregResidueVar = $linregSqrError / $Sxx;
	$linregResidueVar /= ( $linregSimi ** 2 );
	$linregResidueDev = sqrt($linregResidueVar);
	
	return ($relativeFreq, $residueDev, $linregSimi, $linregResidueDev, $count1, $count2);
}

