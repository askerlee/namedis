use strict;
use warnings 'all';

use Getopt::Std;
#use IO::File;
use List::Util qw(max min);

use lib '.';
use NLPUtil;

use constant{
	OPTIONS => 'p:d:m:uy:',
# sampled from a naming website.
# useless now: 2-char names in DBLP have much higher proportion than this number
#	CNAME_CHAR2_TO_CHAR3 	=> 1800 / 8343,
};

# ambiguity / coauthor_cluster_number. from "wei wang-labels.txt": 222/278 ~= 0.8
#my $AMBI_COAUTHOR_CLUST_RATIO = 0.6;
my $AMBIGUITY_TOTAL_EST_COUNT_DIFF_THRES = 100;
my $AMBIGUITY_ABS_DIFF_SUM_THRES = 500;
my $MAX_ITERATION_COUNT = 20;
# the bigger, the more proportion the coauthor_cluster_number is in the ambiguity estimation
my $AMBIG_COAUTHOR_CLUST_JOINT_PROB_MIX = 0;

# by default, don't load old ambiguity file as seed
my $OLD_AMBIG_FILENAME = ""; #"./ambiguity.csv";

openLogfile();

my %opt;
getopts(OPTIONS, \%opt);

my $M = INT_MAX;
my $processedOptionCount = 0;

#if(exists $opt{'p'}){
#	$M = $opt{'p'};
#	if($M =~ /[^0-9]/){
#		die "FATAL  maximum publications '$M' is not understood\n";
#	}
#	print $tee "No more than $M publications will be processed\n";
#	$processedOptionCount++;
#}

my $dirPrefix = "";

if(exists $opt{'p'}){
	$dirPrefix = $opt{'p'};
	if($dirPrefix !~ /\/$/){
		$dirPrefix .= "/";
	}
}

if(exists $opt{'d'}){
	$AMBIGUITY_TOTAL_EST_COUNT_DIFF_THRES = $opt{'d'};
	if($AMBIGUITY_TOTAL_EST_COUNT_DIFF_THRES =~ /[^0-9]/){
		die "FATAL  Chinese author ambiguity iteration difference threshold " .
			"'$AMBIGUITY_TOTAL_EST_COUNT_DIFF_THRES' is not understood\n";
	}
	$processedOptionCount++;
}
print $tee "Chinese author ambiguity iteration difference threshold: $AMBIGUITY_TOTAL_EST_COUNT_DIFF_THRES\n";

#if(exists $opt{'m'}){
#	$AMBIG_COAUTHOR_CLUST_JOINT_PROB_MIX = $opt{'m'};
#	if($AMBIG_COAUTHOR_CLUST_JOINT_PROB_MIX =~ /[^0-9.]/){
#		die "FATAL  AMBIG_COAUTHOR_CLUST_JOINT_PROB_MIX " .
#			"'$AMBIG_COAUTHOR_CLUST_JOINT_PROB_MIX' is not understood\n";
#	}
#	$processedOptionCount++;
#}
#print $tee "AMBIG_COAUTHOR_CLUST_JOINT_PROB_MIX: $AMBIG_COAUTHOR_CLUST_JOINT_PROB_MIX\n";

if(exists $opt{'m'}){
	$OLD_AMBIG_FILENAME = $opt{'m'};
	if(! -e $OLD_AMBIG_FILENAME){
		die "Old ambiguity file '$OLD_AMBIG_FILENAME' not found\n";
	}
	$processedOptionCount++;
}

my $roundUp = 0;
if(exists $opt{'u'}){
	$roundUp = 1;
	print $tee "Author estimation will be rounded up\n";
}

my $yearThres = 2100;
if(exists $opt{'y'}){
	$yearThres = $opt{'y'};
	print $tee "Only publications with year <= $yearThres will be considered\n";
}

if(grep { OPTIONS !~ /$_/ } keys %opt){
	die "FATAL  Unknown options: ", join(',', keys %opt), "\n";
}

print $tee "\n" if $processedOptionCount;

my $file = shift;

my $title;
my $authorLine;
my @authorNames;
my $year;
my $confName;
my $thisPublication;

my $revChnNameCount = 0;

my %chnNames = ();
my %chnSurnames;
my @chnGivenNames;
my %surnameStat;
my %givennameStat;

my %gNameParts;
my @gPublications;
my %gPubCountByYear;
my %gAuthorNames2ID;	# string -> no.

my %nameLen;
my @nameCountsByLen = ( undef, undef, [], [] );
my @estAmbigSums;

NLPUtil::initialize( progressDelim => "\t", progressVars => [ \$gRecordCount, \$recordStartLn ],
						loadChnNameAmbig => $OLD_AMBIG_FILENAME, noLoadGram => 1, noLoadLemmatizer => 1,
						maxRecords => $M );

setDebug( NLPUtil::DBG_WEIRD_CHNNAME );

#open_or_die(REVNAME, "> rev-chnname.txt");

my $name;

my $DB;
my $AUTHORS;

my @chineseAuthors;
my @nonChineseAuthors;
my $authorLineCount = 0;
my $chinesePart;
my $nonChinesePart;

my @authors;
my %author2id;
my $authorGID = 0;

my @authorTuples;
#my %author2tuples;
my %author2clusts;
my %author2cnCoauthors;
my %author2otherCoauthors;

my %authorSoloPubCount;
my %authorPubClusterNum;

if(! -e "${dirPrefix}dblp.authors.txt"){
	print STDERR "Open 'dblp.extracted.txt' to read...\n";
	open_or_die($DB, "< dblp.extracted.txt");

	print STDERR "Open '${dirPrefix}dblp.authors.txt' to write...\n";
	open_or_die($AUTHORS, "> ${dirPrefix}dblp.authors.txt");

	while(!eof($DB)){
		$thisPublication = parseCleanDBLP($DB);

		$title = $thisPublication->title;
		@authorNames = @{ $thisPublication->authors };
		$year = $thisPublication->year;

		if($year > $yearThres){
			next;
		}
		
		push @gPublications, $thisPublication;

		my $isNameReverse = $thisPublication->isNameReverse;
#		if($isNameReverse){
#			$revChnNameCount++;
#			print REVNAME "$recordStartLn: ", join(",", @authorNames), "\n";
#		}

		# some are reverse, and some are not. discard those dirty cases
		if($isNameReverse < 0){
			next;
		}

		@chineseAuthors = ();
		@nonChineseAuthors = ();
		
		for $name(@authorNames){
			if( isChineseName($name) && !isCantoneseName($name, $isNameReverse) ){
				push @chineseAuthors, $name;
			}
			else{
				push @nonChineseAuthors, $name;
			}
		}
		if(@chineseAuthors){
			print $AUTHORS join(",", @chineseAuthors), "\t", join(",", @nonChineseAuthors), "\n";
			$authorLineCount++;

			arriveAuthorTuple(\@chineseAuthors, \@nonChineseAuthors);
		}
	}
	progress2();

	print STDERR "$authorLineCount lines of authors written to 'dblp.authors.txt'\n";
	
	my $pubCount = scalar @gPublications;
	print $tee "$gRecordCount records processed\n";
	print $tee c1000($pubCount), " publications\n";
	print $tee "$revChnNameCount reverse Chinese names\n";
}
else{
	print STDERR "Open '${dirPrefix}dblp.authors.txt' to read...\n";
	open_or_die($AUTHORS, "< ${dirPrefix}dblp.authors.txt");

	my $progresser = makeProgresser( vars => [ \$. ] );

	while($authorLine = <$AUTHORS>){
		trim($authorLine);
		($chinesePart, $nonChinesePart) = split /\t/, $authorLine;
		$nonChinesePart ||= "";

		@chineseAuthors = split /,/, $chinesePart;
		@nonChineseAuthors = split /,/, $nonChinesePart;

		arriveAuthorTuple(\@chineseAuthors, \@nonChineseAuthors);

		&$progresser();
	}
	&$progresser(1);
	print STDERR "$. lines read from 'dblp.authors.txt'\n";
}

if(! -e "${dirPrefix}coauthor-stat.txt"){
	my $COAUTHORS;
	open_or_die($COAUTHORS, "> ${dirPrefix}coauthor-stat.txt");
	
	for $name(keys %author2cnCoauthors){
		if(! exists $author2otherCoauthors{$name}){
			$author2otherCoauthors{$name} = {};
		}
	}
	for $name(keys %author2otherCoauthors){
		if(! exists $author2cnCoauthors{$name}){
			$author2cnCoauthors{$name} = {};
		}
	}
		
	my @names = sort { scalar keys %{ $author2cnCoauthors{$b} } <=> scalar keys %{ $author2cnCoauthors{$a} } 
																||
				    scalar keys %{ $author2otherCoauthors{$b} } <=> scalar keys %{ $author2otherCoauthors{$a} } 										
				} keys %author2cnCoauthors;
				
	for $name(@names){
		my @cnCoauthors = sort { $author2cnCoauthors{$name}{$b} <=> $author2cnCoauthors{$name}{$a} } 
							keys %{ $author2cnCoauthors{$name} };
		my @otherCoauthors = sort { $author2otherCoauthors{$name}{$b} <=> $author2otherCoauthors{$name}{$a} } 
							keys %{ $author2otherCoauthors{$name} };
							
		print $COAUTHORS join( "\t", $name, scalar @cnCoauthors, scalar @otherCoauthors, 
								( map { "$_:$author2cnCoauthors{$name}{$_}" } @cnCoauthors ),
								( map { "$_:$author2otherCoauthors{$name}{$_}" } @otherCoauthors )
							 ), "\n";
	}
	close($COAUTHORS);
}

for $name(keys %chnNames){
	if(exists $author2clusts{$name}){
		$authorPubClusterNum{$name} = scalar grep { defined($_) } @{ $author2clusts{$name} };
		if($authorPubClusterNum{$name} == 0){
			die "'$name' has 0 pub cluster\n";
		}
	}
	else{
		$authorPubClusterNum{$name} = 0;
	}
	
	if(!exists $authorSoloPubCount{$name}){
		$authorSoloPubCount{$name} = 0;
	}
}

iterations();

sub getNameLen
{
	my $name = shift;
	my $len = $nameLen{$name};

	if(! $len){
		$len = $nameLen{$name} = isChineseName($name);
		if($len < 2 || $len > 3){
			print STDERR "Error: '$name' has length $len\n";
			return 0;
		}
	}
	return $len;
}

sub ambiguityPredict($$$)
{
	my ($pubCount, $clustCount, $soloCount) = @_;
	
	#return -0.0318 * $pubCount + 0.9780 * $clustCount - 1.1065 * $soloCount;
	
	my $ambig = 0.9 * $clustCount - 1.3 * $soloCount;
		
#	if($clustCount > $soloCount){
#		return -0.03 * $pubCount + 0.95 * $clustCount - 1.1 * $soloCount;
#	}
	if($ambig <= 0){
		if($clustCount > 0){
			$ambig = 0.7 * $clustCount;
		}
		else{
			$ambig = $soloCount * 0.5;
		}
	}
	
	return $ambig * 0.6;
}

sub arriveAuthorTuple
{
	my ($chineseAuthorNames, $nonChineseAuthorNames) = @_;
	
	my ($authorName, $authorName2);
	my @authorIDs;
	my $authorID;
	my $tupleID;

	my @allAuthorNames = ( @$chineseAuthorNames, @$nonChineseAuthorNames );
	
	for $authorName( @allAuthorNames ){
		$authorID = key2id( $authorName, \%author2id, \@authors, $authorGID );
		push @authorIDs, $authorID;
	}

	my %authorTuple = map { $_ => 1 } @authorIDs;
	$tupleID = @authorTuples;
	push @authorTuples, { %authorTuple };

	my $clust;
	my @overlapClusts;
	my ($i, $j);

	for($i = 0; $i < @allAuthorNames; $i++){
		$authorName = $allAuthorNames[$i];
		
		# a trick here: in @allAuthorNames, @$chineseAuthorNames are at the beginning
		# so the same Chinese author in @allAuthorNames & @$chineseAuthorNames has the same index
		# therefore we check if $j == $i to avoid "self-coauthoring"
		for($j = 0; $j < @$chineseAuthorNames; $j++){
			next if $j == $i;
			
			$authorName2 = $chineseAuthorNames->[$j];
			$author2cnCoauthors{$authorName}{$authorName2}++;
		}
		for($j = 0; $j < @$nonChineseAuthorNames; $j++){
			next if $j + @$chineseAuthorNames == $i;
			
			$authorName2 = $nonChineseAuthorNames->[$j];
			$author2otherCoauthors{$authorName}{$authorName2}++;
		}
	}
			
	for $authorName(@$chineseAuthorNames){
		#$author2tuples{$authorName}{$tupleID} = 1;
		if(@allAuthorNames == 1){
			$authorSoloPubCount{$authorName}++;
			arriveChineseName($authorName);
			next;
		}
		
		if(! exists $author2clusts{$authorName}){
			$author2clusts{$authorName} = [ { %authorTuple } ];
			arriveChineseName($authorName);
			next;
		}

		@overlapClusts = ();
		for($i = 0; $i < @{ $author2clusts{$authorName} }; $i++){
			$clust = $author2clusts{$authorName}[$i];
			next if !$clust;

			if( intersectHash(\%authorTuple, $clust) >= 2 ){
				push @overlapClusts, $i;
			}
		}
		if(@overlapClusts == 0){
			push @{ $author2clusts{$authorName} }, { %authorTuple };
		}
		else{
			my $baseCID = shift @overlapClusts;
			my $baseClust = $author2clusts{$authorName}[$baseCID];

			for $i(@overlapClusts){
				$clust = $author2clusts{$authorName}[$i];
				for $authorID(keys %$clust){
					$baseClust->{$authorID} = 1;
				}
				$author2clusts{$authorName}[$i] = undef;
			}

			for $authorID(keys %authorTuple){
				$baseClust->{$authorID} = 1;
			}
		}

		arriveChineseName($authorName);
	}
}

sub arriveChineseName
{
	my $authorName = shift;
	my @nameParts = split / /, $authorName;

	my ($givenname, $surname) = @nameParts;

#	if( $givenname eq "wang" ){
#		my $debugbreak = 1;
#	}

	my $nameLen = getNameLen($authorName);

	if(!exists $chnNames{"$givenname $surname"}){
		$chnSurnames{$surname}[$nameLen]{$givenname}{q}++;
		$chnGivenNames[$nameLen]{$givenname}{$surname}{q}++;
		$nameCountsByLen[$nameLen][0] += 1;
	}
	$chnNames{"$givenname $surname"}{q}++;
}

sub rationalRound($$)
{
	my ($name, $v) = @_;
	
	$v = atLeast1( $v, $roundUp );
	if( $v > $authorPubClusterNum{$name} + $authorSoloPubCount{$name} ){
		$v = $authorPubClusterNum{$name} + $authorSoloPubCount{$name};
	}
	return $v;	
}

sub iterations
{
	my $authorCount = scalar keys %chnNames;
	print STDERR "$authorCount Chinese authors found.\n";

#	topN($TOP_N, \%gNames,
#			"Sorting namesakes by their publication size", "top productive authors",
#			sub{ $gNames{$_[0]}->pubCount });

	my $fh;

########## Calculate Chinese Name Ambiguity and Write to a csv File ##########
	print $tee "2-char names: $nameCountsByLen[2][0], 3-char names: $nameCountsByLen[3][0]\n";

	my $chnNameCount = $nameCountsByLen[3][0] + $nameCountsByLen[2][0];

	print $tee "Total: $chnNameCount Chinese names\n";

	if(keys %chnNames != $chnNameCount){
		die "Name count mismatch: ", scalar keys %chnNames, 
				"(\%chnNames) != $chnNameCount\n";
	}
	
	print $tee "\nChinese name ambiguity calculation:\n";
	
	my $authorAmbiPredSum = 0;
	my @authorAmbiPredSum = (0) x 4;
	my $name;
	my $namelen;
#	if(keys %authorPubClusterNum != $chnNameCount){
#		die "Name count mismatch: ", scalar keys %authorPubClusterNum, 
#				"(\%authorPubClusterNum) != $chnNameCount\n";
#	}

	for $name(keys %chnNames){
		$namelen = getNameLen($name);

		if($namelen == 2){
			$chnNames{$name}{m}[0] = atLeast1(
										ambiguityPredict( $chnNames{$name}{q}, $authorPubClusterNum{$name}, 
															$authorSoloPubCount{$name} ), 0 );
										#atLeast1( $authorPubClusterNum{$name} * 
										#			$AMBI_COAUTHOR_CLUST_RATIO, $roundUp );
		}
		else{
			
			if($OLD_AMBIG_FILENAME){
									# use the ambiguity loaded from the ambiguity file as the seed
				$chnNames{$name}{m}[0] = rationalRound( $name, $chnNameAmbig{$name} );
			}
			else{
				$chnNames{$name}{m}[0] = 1;
			}
		}
		$authorAmbiPredSum[$namelen] += $chnNames{$name}{m}[0];	
		$authorAmbiPredSum += $chnNames{$name}{m}[0];
	}
	print $tee "2-char name estimation: $authorAmbiPredSum[2], 3-char names: $authorAmbiPredSum[3]\n";
		
	push @estAmbigSums, $authorAmbiPredSum;

	my ($ambigAbsDiffSum, $estAmbigSum, $estAmbigSumDiff);
	my $round = 0;
	do{
		print $tee "Estimated name count: $estAmbigSums[0].";
		$round++;
		if($round > 1){
			print $tee " Diff: $estAmbigSumDiff.\n";
		}
		else{
			print $tee "\n";
		}
		print $tee "Round $round...\n";
		( $ambigAbsDiffSum, $estAmbigSum ) = calcChnNameAmbig($round, $estAmbigSums[0]);
		unshift @estAmbigSums, $estAmbigSum;
		print $tee "Done\n";
		$estAmbigSumDiff = $estAmbigSums[0] - $estAmbigSums[1];
	}while( $ambigAbsDiffSum >= $AMBIGUITY_ABS_DIFF_SUM_THRES && $round < $MAX_ITERATION_COUNT );

	print $tee "Estimated name count: $estAmbigSums[0]. ";
	print $tee "Diff: $estAmbigSumDiff. Stop\n\n";

	print $tee "Dump $chnNameCount Chinese names into ${dirPrefix}ambiguity-$timestamp.csv...";
	open_or_die($fh, "> ${dirPrefix}ambiguity-$timestamp.csv");

	my @chnnames = sort { $chnNames{$b}{m}[0] <=> $chnNames{$a}{m}[0] } keys %chnNames;
	print $fh "Name,Occurrence";
	my $i;
	for($i = $round; $i >= 0; $i--){
		print $fh ",Ambig $i";
	}
	print $fh "\n";

	for $name(@chnnames){
		print $fh "$name,$chnNames{$name}{q},",
					join(",", @{$chnNames{$name}{m}}), "\n";
	}

	my @surnames = sort { $surnameStat{$b}{q}[0] <=> $surnameStat{$a}{q}[0] }
								keys %surnameStat;

	print $fh "SURNAMES,", scalar keys %surnameStat, ",-\n";
	for $name(@surnames){
		print $fh "$name,-";
		for($i = 0; $i < @{$surnameStat{$name}{p}}; $i++){
			print $fh ",$surnameStat{$name}{q}->[$i] \\ $surnameStat{$name}{p}->[$i]";
		}
		print $fh "\n";
	}

	my @givennames = sort { $givennameStat{$b}{q}[0] <=> $givennameStat{$a}{q}[0] }
								keys %givennameStat;

	print $fh "GIVEN_NAMES,", scalar keys %givennameStat, ",-\n";
	for $name(@givennames){
		print $fh "$name,-";
		for($i = 0; $i < @{$givennameStat{$name}{p}}; $i++){
			print $fh ",$givennameStat{$name}{q}->[$i] \\ $givennameStat{$name}{p}->[$i]";
		}
		print $fh "\n";
	}

	print $fh "\*,$chnNameCount,", join(",", @estAmbigSums[0 .. $#estAmbigSums - 1]), "\n";

	close($fh);
	print $tee " Done.\n";
########## End of Chinese Name Ambiguity ##########

}

# {p} is the estimated prob, {q} is the rounded estimated ambiguity, {m} is unrounded ambiguity
sub calcChnNameAmbig
{
	my ($round, $newNameCount) = @_;

	my ($surname, $givenname);
#	my ($name2est, $name3est);
#	$name2est = $nameCountsByLen[2][0];
#	$name3est = $nameCountsByLen[3][0];

	for $surname(keys %chnSurnames){
		if($round == 1){
#			$surnameStat{$surname}{q}[0] = keys %{$chnSurnames{$surname}[2]};
#			$surnameStat{$surname}{q}[0] += keys %{$chnSurnames{$surname}[3]};
			unshift @{$surnameStat{$surname}{q}}, 0;
			for $givenname( keys %{ $chnSurnames{$surname}[2] } ){
				$surnameStat{$surname}{q}[0] += $chnNames{"$givenname $surname"}{m}[0];
				#atLeast1(
				#	$authorPubClusterNum{"$givenname $surname"} * $AMBI_COAUTHOR_CLUST_RATIO, $roundUp );
			}

			for $givenname(keys %{ $chnSurnames{$surname}[3] }){
				$surnameStat{$surname}{q}[0] += $chnNames{"$givenname $surname"}{m}[0];
				#atLeast1(
				#	$authorPubClusterNum{"$givenname $surname"} * $AMBI_COAUTHOR_CLUST_RATIO, $roundUp );
			}
		}
		else{
			# latest q & p are at the beginning of the array
			unshift @{$surnameStat{$surname}{q}}, 0;
			for $givenname( keys %{ $chnSurnames{$surname}[2] } ){
				$surnameStat{$surname}{q}[0] += rationalRound( "$givenname $surname", 
													$chnSurnames{$surname}[2]{$givenname}{m} );
			}

			for $givenname(keys %{ $chnSurnames{$surname}[3] }){
				$surnameStat{$surname}{q}[0] += rationalRound( "$givenname $surname", 
													$chnSurnames{$surname}[3]{$givenname}{m} );
			}
		}
		unshift @{$surnameStat{$surname}{p}},
					$surnameStat{$surname}{q}[0] / $newNameCount;
	}

	if($round > 1){
		for $givenname( keys %givennameStat ){
			unshift @{$givennameStat{$givenname}{q}}, 0;
		}
	}

	for $givenname( keys %{ $chnGivenNames[2] } ){
		if($round == 1){
			#$givennameStat{$givenname}{q}[0] = keys %{$chnGivenNames[2]{$givenname}};
			unshift @{$givennameStat{$givenname}{q}}, 0;
			for $surname( keys %{ $chnGivenNames[2]{$givenname} } ){
				$givennameStat{$givenname}{q}[0] += $chnNames{"$givenname $surname"}{m}[0];
				#atLeast1(
				#	$authorPubClusterNum{"$givenname $surname"} * $AMBI_COAUTHOR_CLUST_RATIO, $roundUp );
			}
		}
		else{
			for $surname(keys %{$chnGivenNames[2]{$givenname}}){
				$givennameStat{$givenname}{q}[0] += rationalRound( "$givenname $surname", 
														$chnGivenNames[2]{$givenname}{$surname}{m} );
			}
		}
		unshift @{$givennameStat{$givenname}{p}},
				$givennameStat{$givenname}{q}[0] / $newNameCount;
	}
	for $givenname( keys %{ $chnGivenNames[3] } ){
		if($round == 1){
#			if($givennameStat{$givenname}{q}[0] != 0){
#				my $debugbreak = 1;
#			}
#			$givennameStat{$givenname}{q}[0] = keys %{$chnGivenNames[3]{$givenname}};
			unshift @{$givennameStat{$givenname}{q}}, 0;
			for $surname( keys %{ $chnGivenNames[3]{$givenname} } ){
				$givennameStat{$givenname}{q}[0] += $chnNames{"$givenname $surname"}{m}[0];
				#atLeast1(
				#	$authorPubClusterNum{"$givenname $surname"} * $AMBI_COAUTHOR_CLUST_RATIO, $roundUp );
			}
		}
		else{
			for $surname(keys %{$chnGivenNames[3]{$givenname}}){
				$givennameStat{$givenname}{q}[0] += rationalRound( "$givenname $surname", 
														$chnGivenNames[3]{$givenname}{$surname}{m} );
			}
		}
		unshift @{$givennameStat{$givenname}{p}},
				$givennameStat{$givenname}{q}[0] / $newNameCount;
	}

	# sanity check
	my $cs = 0;
	my $ps = 0;
	for $surname(keys %surnameStat){
		$cs += $surnameStat{$surname}{q}[0];
		$ps += $surnameStat{$surname}{p}[0];
	}
	my $cg = 0;
	my $pg = 0;
	for $givenname(keys %givennameStat){
		$cg += $givennameStat{$givenname}{q}[0];
		$pg += $givennameStat{$givenname}{p}[0];
	}
	if(! isVeryClose($cs, $cg, 1) ){
		die "Chinese name count by surname/givenname mismatch: $cs != $cg\n";
	}
	if(! isVeryClose($cg, $newNameCount, 1) ){
		die "Chinese name count by givenname mismatch: $cg != $newNameCount";
	}
	# end of check

	my $nameCount = $newNameCount;
	$newNameCount = 0;

	my $name;
	my $ambig;
	my $avgAmbig;
	
	print $LOG "\n";

	unshift @{ $nameCountsByLen[2] }, 0;
	unshift @{ $nameCountsByLen[3] }, 0;

	my $nameLen;

	my $totalP = 0;

	my $ambigAbsDiffSum = 0;
	
	for $name(keys %chnNames){
		$nameLen = getNameLen($name);

		($givenname, $surname) = split / /, $name;
		$ambig = $surnameStat{$surname}{p}[0] * $givennameStat{$givenname}{p}[0] * $nameCount;

		$totalP += $surnameStat{$surname}{p}[0] * $givennameStat{$givenname}{p}[0];
	}
	$totalP = trunc(4, $totalP);
	print $tee "Sum of prob: $totalP\n";

	my $probBoost = 1.22; #sqrt($totalP);
		
	for $name(keys %chnNames){
		$nameLen = getNameLen($name);

		($givenname, $surname) = split / /, $name;
		$ambig = $surnameStat{$surname}{p}[0] * $givennameStat{$givenname}{p}[0] * $probBoost * $nameCount;

#		if($round == 1){
#			# $chnNames{$name}{m} is still an empty array now. i.e., no $chnNames{$name}{m}[0]
#			$avgAmbig = $ambig;
#		}
#		else{
#			# when CHN_AUTHOR_AMBIG_EST_OLD_NEW_MIX == 1, the last value of 'm' has no effect on
#			# the new $avgAmbig
#			$avgAmbig = $chnNames{$name}{m}[0] * (1 - CHN_AUTHOR_AMBIG_EST_OLD_NEW_MIX) + $ambig * CHN_AUTHOR_AMBIG_EST_OLD_NEW_MIX;
#		}
#		unshift @{$chnNames{$name}{m}}, $ambig;
#		$chnGivenNames{$givenname}{$surname}{m} = $ambig;
#		$chnSurnames{$surname}{$givenname}{m} = $ambig;
#		$newNameCount += round1($ambig);

#		$ambig = min( $ambig, $chnNames{$name}{q} );

		# the pure iteration policy (the coauthor_cluster_number is used only as a seed, 
		# no longer considered after interation begins)
		
		if( $round >= 1 && $ambig < $chnNames{$name}{m}[0] ){
			$avgAmbig = $chnNames{$name}{m}[0];
		}
		else{
			$avgAmbig = $ambig;
		}
		
		# the mixed iteration policy
#		$avgAmbig = weightedAverage($AMBIG_COAUTHOR_CLUST_JOINT_PROB_MIX, 
#										$chnNames{$name}{m}[-1], $ambig);

		unshift @{$chnNames{$name}{m}}, $avgAmbig;
		$chnGivenNames[$nameLen]{$givenname}{$surname}{m} = $avgAmbig;
		$chnSurnames{$surname}[$nameLen]{$givenname}{m} = $avgAmbig;

		$nameCountsByLen[$nameLen][0] += rationalRound( $name, $avgAmbig );

		$ambigAbsDiffSum += abs( rationalRound( $name, $chnNames{$name}{m}[0] ) - 
								 rationalRound( $name, $chnNames{$name}{m}[1] ) );
		
#		if($givenname eq "li"){
#			print $hlog "$surname: $ambig, $avgAmbig\n";
#		}
	}

	$newNameCount = roundAtLeast1( $nameCountsByLen[3][0] + $nameCountsByLen[2][0] );
	
	print $tee "2-char names: $nameCountsByLen[2][0], 3-char names: $nameCountsByLen[3][0], total: $newNameCount\n";
	print $tee "Absolute ambiguity diff sum: ", trunc(2, $ambigAbsDiffSum), "\n";
	print $tee "Ambiguity sum diff: ", $newNameCount - $estAmbigSums[0], "\n";
	return ( $ambigAbsDiffSum, $newNameCount );
}
