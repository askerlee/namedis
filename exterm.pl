use strict;
use warnings 'all';
use Getopt::Std;
#use IO::File;
use List::Util qw(max min);

use lib '.';
use NLPUtil;

use constant{
	OPTIONS 						=> 'km:p:n:d:g:c:C:',
	MAX_LOG_LIST_SIZE 				=> 20,
	
	# this is no longer used, as after partitioning bigrams into two parts, the mem becomes enough
	OPT_BIGRAM_RANDOM_CHOOSE 		=> 0,
	BIGRAM_CHOOSE_PROB 				=> 0.1,
	IAF_LEAST_VALUE					=> 0.5,
};

# COUNTABLE_AUTHOR_LEAST_PUB = 1, it actually means no least pub requirment. 
# (each counted author has already had one paper)
my $COUNTABLE_AUTHOR_LEAST_PUB 		= 1,

# for authors whose pub count are below it, their contribs will be scaled down (both the accumulative 
# author count and the accumulative pub count for certain term)
# if the pub count of author a is >= this number, we regard this pub set as statistically large enough
my $SCALE_DOWN_AUTHOR_CONTRIB_WITH_LESS_PUB_THAN_IT = 3;

my %opt;
getopts(OPTIONS, \%opt);

if(@ARGV == 0){
    die "Please specify the DBLP file to process\n";
}

my $M = INT_MAX;
my $TOP_N = MAX_LOG_LIST_SIZE;
my $IS_ACCOUNTING_ONLY = 0;
my $BIGRAM_RANGE = "a-z";
my $BIGRAM_INC_SYMBOLS = 0;
my $COUNT_UNIGRAM = 0;
my $COUNT_BIGRAM = 0;
my $LEMMA_CACHE_LOAD_FILENAME;
my $LEMMA_CACHE_SAVE_FILENAME;
my $processedOptionCount = 0;

if(exists $opt{'p'}){
	$M = $opt{'p'};
	if($M =~ /[^0-9]/){
		die "FATAL  maximum publication num '$M' is not understood\n";
	}
	print "No more than $M publications will be processed\n";
	$processedOptionCount++;
}

if(exists $opt{'n'}){
	$TOP_N = $opt{'n'};
	if($TOP_N =~ /[^0-9]/){
		die "FATAL  top/bottom data counts '$TOP_N' is not understood\n";
	}
#	if($TOP_N > 10000){
#		print "Warning: Top $TOP_N is too many, truncate to 100\n";
#		$TOP_N = 100;
#	}
	print "No more than $TOP_N top/bottom data will be displayed in the summary\n";
	$processedOptionCount++;
}

if(exists $opt{'g'}){
	if($opt{'g'} =~ /1/){
		$COUNT_UNIGRAM = 1;
	}
	if($opt{'g'} =~ /2(.*)/){
		$COUNT_BIGRAM = 1;
		if(length($1)){
			$BIGRAM_RANGE = $1;
			if($BIGRAM_RANGE !~ /^[a-z\-]+$/){
				die "FATAL  Invalid format of bigram range: '$BIGRAM_RANGE'\n";
			}
			
			if("a" =~ /[$BIGRAM_RANGE]/i){
				$BIGRAM_INC_SYMBOLS = 1;
			}
		}
	}
	$processedOptionCount++;
}
if( ! $COUNT_UNIGRAM && ! $COUNT_BIGRAM ){
	die "FATAL  At least one type of gram (1 or 2) needs to be specified\n";
}
else{
	print "Count ", $COUNT_UNIGRAM ? "uni- " : "", 
					$COUNT_UNIGRAM && $COUNT_BIGRAM ? "and " : "",
					$COUNT_BIGRAM ? "bi-($BIGRAM_RANGE) " : "",
					"grams\n";
}

if(exists $opt{'c'}){
	$LEMMA_CACHE_LOAD_FILENAME = $opt{'c'};
	if(! -e $LEMMA_CACHE_LOAD_FILENAME){
		die "FATAL  lemma cache file '$LEMMA_CACHE_LOAD_FILENAME' doesn't exist, please check\n";
	}
	print "Will load lemma cache from file '$LEMMA_CACHE_LOAD_FILENAME'\n";
	$processedOptionCount++;
}
if(exists $opt{'C'}){
	$LEMMA_CACHE_SAVE_FILENAME = $opt{'C'};
	print "Will save lemma cache to file '$LEMMA_CACHE_SAVE_FILENAME'\n";
	$processedOptionCount++;
}

if(grep { OPTIONS !~ /$_/ } keys %opt){
	die "FATAL  Unknown options: ", join(',', keys %opt), "\n";
}

print "\n" if $processedOptionCount;

my $file = shift;

my $DB;
open_or_die($DB, "< $file");

my ($logfilenameStem) = $file =~ /(.+?)(\.extracted(-\d+)?)?\.[^.]+$/;
$logfilenameStem = "gram-$opt{'g'}";

openLogfile($logfilenameStem);

our $recordStartLn;
my $title;
my @authorNames;
my $year;
my $booktitle;
my $pubType;
my $thisPublication;

our $gRecordCount = 0;
my $weirdTitleCount = 0;
my $pubCount;
my $authorCount;
my $namesakeCount;

my $bigramFreqSum = 0;
my $unigramFreqSum = 0;

our %gNameParts;
our %gPubnumByName;

our @gAuthors;	# struct namesake
our @gPublications;
our %gPubCountByYear;
our %gAuthorName2ID;	# string -> no.

my %gBigramWeightRange;
my %gUnigramWeightRange;

NLPUtil::initialize( progressDelim => "\t", progressVars => [ \$gRecordCount, \$recordStartLn ], 
				lemmaCacheLoadFile => $LEMMA_CACHE_LOAD_FILENAME,
				lemmaCacheSaveFile => $LEMMA_CACHE_SAVE_FILENAME,
				noLoadGram => 1 );

while(!eof($DB)){
	$thisPublication = parseCleanDBLP($DB);
	
	$title = $thisPublication->title;
#	$title = removePublisher($thisPublication->title);
	@authorNames = @{ $thisPublication->authors };
	$year = $thisPublication->year;
	
	push @gPublications, $title;
	
	if(@authorNames > 3){
		$#authorNames = 2;
	}
	for(@authorNames){
		arriveAuthor($_);
	}
	
	arriveTitle($title, $year, \@authorNames);

	if($gRecordCount >= $M){
		summary();
		print $tee "\nLast line being processed is ", $recordStartLn + 3, "\n";
		die "Exit early.\n";
	}
}

progress2();

summary();

sub arriveAuthor
{
	my $authorName = shift;
	
	$gPubnumByName{$authorName}++;
	
	push @gAuthors, $authorName;
	
	if(!exists $gAuthorName2ID{$authorName}){
		$gAuthorName2ID{$authorName} = scalar @gAuthors;
	}
}

sub arriveUnigram($$$)
{
	my ($authors, $w, $year) = @_;

	if(! $COUNT_UNIGRAM){
		return;
	}
	
	# disable the below. overkill
	# exclude numbers (but include decimals like 802.11)
#	if($w !~ /[^\d]/){
#		return;
#	}
		
#	my $authorCount = scalar @{$authors};
	
	my %authorHitFreq = map { $gAuthorName2ID{$_} => 1 } @{$authors};

	if(exists $gUnigrams{$w}){
		$gUnigrams{$w}->freq($gUnigrams{$w}->freq + 1);
#		if($gUnigrams{$w}->startYear > $year){
#			$gUnigrams{$w}->startYear($year);
#		}
		for(keys %authorHitFreq){
			$gUnigrams{$w}->authorHitFreqDistribution()->{$_}++;
		}
	}
	else{
		$gUnigrams{$w} = keyword->new(word => $w, freq => 1, #startYear => $year,
									authorHitFreq => \%authorHitFreq);
	}
	
	$unigramFreqSum++;
}

sub arriveBigram($$$)
{
	my ($authors, $w, $year) = @_;
#	my $authorCount = scalar @{$authors};

	if(! $COUNT_BIGRAM){
		return;
	}
		
	if($w =~ /^[^a-z]/i && !$BIGRAM_INC_SYMBOLS 
						 ||
	   $w =~ /^[a-z]/i  && $w !~ /^[$BIGRAM_RANGE]/i){
		return;
	}
		
	my %authorHitFreq = map { $gAuthorName2ID{$_} => 1 } @{$authors};
	
	if(exists $gBigrams{$w}){
		$gBigrams{$w}->freq($gBigrams{$w}->freq + 1);
#		if($gBigrams{$w}->startYear > $year){
#			$gBigrams{$w}->startYear($year);
#		}
		for(keys %authorHitFreq){
			$gBigrams{$w}->authorHitFreqDistribution()->{$_}++;
		}
	}
	else{
		if(!OPT_BIGRAM_RANDOM_CHOOSE || rand() <= BIGRAM_CHOOSE_PROB){
			$gBigrams{$w} = keyword->new(word => $w, freq => 1, #startYear => $year,
										authorHitFreq => \%authorHitFreq);
		}
	}
	
	$bigramFreqSum++;
}

sub arriveTitle
{
	my ($title, $year, $authorNames) = @_;

	my (@bigrams, @unigrams);
	
	extractTitleGrams($title, \@unigrams, \@bigrams);

	my $w;
	
	for $w(@unigrams){
		arriveUnigram($authorNames, $w, $year);
	}
	
	for $w(@bigrams){
		arriveBigram($authorNames, $w, $year);
	}
		
	$gPubCountByYear{$year}++;
}

sub summary
{
	$authorCount = scalar @gAuthors;
	$pubCount = scalar @gPublications;
	$namesakeCount = scalar keys %gPubnumByName;

	print $tee "\n\n$gRecordCount records processed\n";
	print $tee "$weirdTitleCount titles are weird\n\n";
	
	print $tee c1000($pubCount), " publications by ", $authorCount, " authors.\n";
	if($pubCount > 0){
		print $tee $authorCount / $pubCount, " authors each publication.\n";
	}

	print $tee "\nPublication breakdown by year:\n";
	my @years = sort { $a <=> $b }keys %gPubCountByYear;
	my $year;
	for $year(@years){
		print $tee "$year:\t", c1000($gPubCountByYear{$year}), "\n";
	}
	print $tee "\n";
	
	print $tee c1000($namesakeCount), " distinct namesakes.";
	if($namesakeCount > 0){
		print $tee " Each occurs ", $authorCount / $namesakeCount, " times\n";
		print $tee $pubCount / $namesakeCount, " publications per namesake\n";
	}
	print $tee "\n";

#	topN($TOP_N, \%gPubnumByName,
#			"Sorting namesakes by their publication size", "top productive authors",
#			sub{ $gPubnumByName{$_[0]}->pubCount });
	
	my $bigramCount = scalar keys %gBigrams;
	my $unigramCount = scalar keys %gUnigrams;
	print $tee c1000($bigramCount), " bigrams, ", c1000($unigramCount), " unigrams\n";

	if($pubCount > 0){
		print $tee $bigramCount / $pubCount, " bigrams, ",
				$unigramCount / $pubCount, " unigrams each publication\n\n";
	}
	else{
		print $tee "\n";
	}

	calc12TFIAF();
	
	my ($list, $list1, $list2);
	
	if($COUNT_BIGRAM){
		
=pod		
		$list = topBottomN($TOP_N, \%gBigrams, 
					"Sorting bigrams by TF", "highest TF bigrams", "lowest TF bigrams", 
					sub{ $gBigrams{$_[0]}->tf }
				   );
	#	rankByList($list, sub{ $gBigrams{$_[0]}->tf }, sub { $gBigrams{$_[0]}->af_rank($_[1]) });
		
		$list = topBottomN($TOP_N, \%gBigrams, 
					"Sorting bigrams by TF*IAF", "highest TF*IAF bigrams", "lowest TF*IAF bigrams", 
					sub{ $gBigrams{$_[0]}->tfiaf }
				   );
	#	rankByList($list, sub{ $gBigrams{$_[0]}->tfiaf }, sub { $gBigrams{$_[0]}->tfiaf_rank($_[1]) });
		
		$list = topBottomN($TOP_N, \%gBigrams, 
					"Sorting bigrams by IAF", "highest IAF bigrams", "lowest IAF bigrams", 
					sub{ $gBigrams{$_[0]}->iaf }
				   );
	#	rankByList($list, sub{ $gBigrams{$_[0]}->iaf }, sub { $gBigrams{$_[0]}->iaf_rank($_[1]) });
=cut

		$list2 = topBottomN($TOP_N, \%gBigrams, 
					"Sorting bigrams by frequency", "most frequent bigrams", "least frequent bigrams",
					sub{ $gBigrams{$_[0]}->freq }, $NLPUtil::recoverLemmaRef
				   );
	#	rankByList($list2, sub{ $gBigrams{$_[0]}->freq }, sub { $gBigrams{$_[0]}->freq_rank($_[1]) });

		my $bigramFilename = "bigram[$BIGRAM_RANGE]-$timestamp.csv";
		dumpKeywords($bigramFilename, \%gBigrams, $bigramFreqSum, $list2);
	}

	if($COUNT_UNIGRAM){
		
=pod		
		$list = topBottomN($TOP_N, \%gUnigrams, 
					"Sorting unigrams by TF", "highest TF unigrams", "lowest TF unigrams", 
					sub{ $gUnigrams{$_[0]}->tf },
				   );
	#	rankByList($list, sub{ $gUnigrams{$_[0]}->tf }, sub { $gUnigrams{$_[0]}->af_rank($_[1]) });
		
		$list = topBottomN($TOP_N, \%gUnigrams, 
					"Sorting unigrams by TF*IAF", "highest TF*IAF unigrams", "lowest TF*IAF unigrams", 
					sub{ $gUnigrams{$_[0]}->tfiaf },
				   ); 
	#	rankByList($list, sub{ $gUnigrams{$_[0]}->tfiaf }, sub { $gUnigrams{$_[0]}->tfiaf_rank($_[1]) });
		
		$list = topBottomN($TOP_N, \%gUnigrams, 
					"Sorting unigrams by IAF", "highest IAF unigrams", "lowest IAF unigrams", 
					sub{ $gUnigrams{$_[0]}->iaf }
				   );
	#	rankByList($list, sub{ $gUnigrams{$_[0]}->iaf }, sub { $gUnigrams{$_[0]}->iaf_rank($_[1]) });
			
=cut

		$list1 = topBottomN($TOP_N, \%gUnigrams, 
					"Sorting unigrams by frequency", "most frequent unigrams", "least frequent unigrams",
					sub{ $gUnigrams{$_[0]}->freq }, $NLPUtil::recoverLemmaRef
				   );
	#	rankByList($list1, sub{ $gUnigrams{$_[0]}->freq }, sub { $gUnigrams{$_[0]}->freq_rank($_[1]) });

		my $unigramFilename = "unigram-$timestamp.csv";
		dumpKeywords($unigramFilename, \%gUnigrams, $unigramFreqSum, $list1);
	}
}

sub rankByList
{
	my ($list, $valueaccessor, $rankaccessor) = @_;
	my ($tiebegin, $tieend);
	my ($i, $j);
	my $n = @{$list};
	my $k;
	
	$tiebegin = 0;
	for($i = 0; $i < $n - 1; $i++){
		if(&$valueaccessor($list->[$i]) != &$valueaccessor($list->[$i + 1])){
			$tieend = $i;
			for($j = $tiebegin; $j <= $tieend; $j++){
				&$rankaccessor($list->[$j], [ $tiebegin + 1, $tieend + 1 ]);
			}
			$tiebegin = $i + 1;
		}
	}
	$tieend = $i;
	for($j = $tiebegin; $j <= $tieend; $j++){
		&$rankaccessor($list->[$j], [ $tiebegin + 1, $tieend + 1 ]);
	}
}

sub dumpKeywords
{
	my ($filename, $wordbag, $freqSum, $list) = @_;
	
	my $gramCount = scalar keys %$wordbag;
	print $tee "Dumping $gramCount $NLPUtil::typeof{$wordbag} into '$filename'...";

	my $FH;
	if(! open_or_warn($FH, "> $filename") ){
		return;
	}

	print $FH 	"Keyword,Frequency,",
				# the count of authors whose papers have this keyword
				"Author Count,",
				# the count of all publications by authors using this term
				"Author All Pubs,",
				# estimated total count of topic pubs of the authors
				"Author Topic Pubs Est,", 
				# average fraction of papers with this term in all these authors' papers
				"Author Hit Fract,", 
				# estimated fraction of total count of topic pubs of the authors
				"Author Hit Fract of Topic Pubs,", 
				"TF,",
				"TF*IAF,",
				"IAF\n";

	print $FH "ALL_TITLES_AUTHORS,$freqSum,$namesakeCount,$pubCount\n";
	
	my $k;
	for $k(@{$list}){
		print $FH join(",", $k, $wordbag->{$k}->freq,
					$wordbag->{$k}->authorNum,
					$wordbag->{$k}->authorPubTotalCount,
					$wordbag->{$k}->authorTopicPubEstCount,
					$wordbag->{$k}->authorPubAvgFraction,
					$wordbag->{$k}->authorTopicPubEstFraction,
					$wordbag->{$k}->tf,
					$wordbag->{$k}->tfiaf, 
					$wordbag->{$k}->iaf,
#					weightdiff($wordbag->{$k}->tf, $wordbag->{$k}->tfiaf, $wordbag->{$k}->iaf)
				  ), "\n";
	}
	
	print $tee " Done.\n";
}

sub rangeDiff
{
	my ($r1, $r2) = @_;
	my ($d1, $d2);
	if($r1->[1] < $r2->[0]){
		return $r2->[0] - $r1->[1];
	}
	elsif($r1->[0] > $r2->[1]){
		return $r1->[0] - $r2->[1];
	}
	return 0;
}
	
sub rankdiff
{
	my ($tf, $tfiaf, $iaf) = @_;
	return max( rangeDiff($tf, $tfiaf), rangeDiff($tf, $iaf), rangeDiff($tfiaf, $iaf) );
}

sub weightdiff
{
	my ($tf, $tfiaf, $iaf) = @_;
	return max( abs($tf - $tfiaf), abs($tf - $iaf), abs($tfiaf - $iaf) );
}

sub estTopicPub
{
	my $totalPubCount = shift;
	die "totalPubCount < 0 for estTopicPub()" if $totalPubCount <= 0;
	
	# Assume the topic number is $totalPubCount ^ 1/3, 
	# so the number of pubs on one topic is $totalPubCount ^ 2/3
	return $totalPubCount ** 0.666;
}

sub calcTFIAF
{
	my $wordbag = shift;
	
	my $bagname = $NLPUtil::typeof{$wordbag};
	
	my ($k, $a);
	my ($authorNumNonForay, $authorHitFreqSum, $authorPubTotalCount, $authorTopicPubEstCount, 
			$authorPubAvgFraction, $authorTopicPubEstFraction, $tf, $tfiaf, $iaf);
	
	print $tee "\nCalculating TF, TF*IAF and IAF of $bagname... \n";
	
	my $wordcount = keys %{$wordbag};
	my $counter = 0;
	my $freq;
	my $maxAuthorHitFreqSum = 0;
	my $mostAuthorFreqWord = "PLACE_HOLDER";
	my $maxAuthorNum = 0;
	my $mostAuthorNumWord = "PLACE_HOLDER";
	my $authorName;
	my $authorHitFreqDistribution;
	my $authorHitFreq;
	my $authorPubCount;
	
	print $tee "First pass: find the word(s) with max authors and max sum-of-author-frequencies\n";
	
	for $k(keys %{$wordbag}){
		if($counter % 1000 == 0){
			print "\r$counter / $wordcount\r";
		}
		$counter++;
		
		$authorNumNonForay = 0;
		$authorHitFreqSum = 0;
		$authorPubTotalCount = 0;
		$authorTopicPubEstCount = 0;
		
		$authorHitFreqDistribution = $wordbag->{$k}->authorHitFreqDistribution;
		$wordbag->{$k}->authorHitFreqDistribution( {} );
		$wordbag->{$k}->authorNum( scalar keys %$authorHitFreqDistribution );
		
		for $a( keys %$authorHitFreqDistribution ){
			$authorName = $gAuthors[$a - 1];
			if($gPubnumByName{$authorName} < $COUNTABLE_AUTHOR_LEAST_PUB){
				next;
			}
			
			# there are many authors who just publish one pub in DBLP, and this pub mentions $k.
			# these pubs are the long tail of the pub distribution, and the counts are guessed to 
			# add up to the dominating chunk among all pubs mentioning $k. so we scale down them, equivalently 
			# give more weights to the authors who publish more than one, coz the latter kind of authors
			# are statistically more significant
			# (if pub num >= $SCALE_DOWN_AUTHOR_CONTRIB_WITH_LESS_PUB_THAN_IT, no scale-down is applied).
			# since scaling down is applied to both the accumulative author count and the accumulative
			# pub count, if there are much fewer authors whose pub set are statistically large than 
			# authors with few pubs, the two scaling downs cancel with each other, and the resulting 
			# ratios are nearly the same to the ratios without scaling down.
			my $scaledown = min( $gPubnumByName{$authorName}, $SCALE_DOWN_AUTHOR_CONTRIB_WITH_LESS_PUB_THAN_IT) 
								/ $SCALE_DOWN_AUTHOR_CONTRIB_WITH_LESS_PUB_THAN_IT;
								
			$authorPubCount = $gPubnumByName{$authorName};
			$authorHitFreq = $authorHitFreqDistribution->{$a};
			
			$authorPubTotalCount += $authorPubCount * $scaledown;
			$authorTopicPubEstCount += max( $authorHitFreq, estTopicPub($authorPubCount) )  * $scaledown;
			
			# if an author only publishes 1 paper on certain topic,
			# think of him as touching on this topic, so don't count him in
			#### DISABLED #### to save some rare words from being assigned with weight 0
#			if($wordbag->{$k}->authorHitFreqDistribution->{$a} == 1){
#				next;
#			}
			
			$authorHitFreqSum += $authorHitFreq * $scaledown;
			$authorNumNonForay +=  $scaledown;
		}
		
		if($authorPubTotalCount > 0){
			$authorPubAvgFraction = $authorHitFreqSum / $authorPubTotalCount;
			$authorTopicPubEstFraction = $authorHitFreqSum / $authorTopicPubEstCount;
		}
		else{
			$authorPubAvgFraction = 0;
		}
		
		( $authorPubAvgFraction, $authorTopicPubEstFraction ) = 
					trunc( 6, $authorPubAvgFraction, $authorTopicPubEstFraction );
		
		$wordbag->{$k}->authorNumNonForay($authorNumNonForay);
		$wordbag->{$k}->authorPubTotalCount($authorPubTotalCount);
		$wordbag->{$k}->authorTopicPubEstCount($authorTopicPubEstCount);
		$wordbag->{$k}->authorPubAvgFraction($authorPubAvgFraction);
		$wordbag->{$k}->authorTopicPubEstFraction($authorTopicPubEstFraction);
		
		if($authorHitFreqSum > $maxAuthorHitFreqSum){
			$maxAuthorHitFreqSum = $authorHitFreqSum;
			$mostAuthorFreqWord = $k;
		}
		if($authorNumNonForay > $maxAuthorNum){
			$maxAuthorNum = $authorNumNonForay;
			$mostAuthorNumWord = $k;
		}
	}
	print $tee "$counter / $wordcount   Done.\n";
	
	if($mostAuthorFreqWord eq $mostAuthorNumWord){
		print $tee "\n'$mostAuthorFreqWord' has most authors ", 
						$wordbag->{$mostAuthorFreqWord}->authorNumNonForay, " and ",
					"max sum of author-frequencies $maxAuthorHitFreqSum\n";
	}
	else{
		print $tee "\n'$mostAuthorFreqWord' has ", 
						$wordbag->{$mostAuthorFreqWord}->authorNumNonForay, 
						" authors and max sum of author-frequencies $maxAuthorHitFreqSum\n";
		print $tee "'$mostAuthorNumWord' has most authors $maxAuthorNum\n";
					 # "and sum of author-frequencies $wordInfo{$mostAuthorNumWord}{authorHitFreqSum}\n";
	}

	my %weightRange = ('tf.min' => 10000, 'tfiaf.min' => 10000, 'iaf.min' => 10000,
					   'tf.max' => 0, 'tfiaf.max' => 0, 'iaf.max' => 0
					  );
				
	$counter = 0;
	
	print $tee "Second pass: calcuate TF, TF*IAF and IAF\n";

	for $k(keys %{$wordbag}){
		if($counter % 1000 == 0){
			print "\r$counter / $wordcount\r";
		}
		$counter++;
		
		$freq = $wordbag->{$k}->freq;
		$authorNumNonForay = $wordbag->{$k}->authorNumNonForay;
		$authorPubAvgFraction = $wordbag->{$k}->authorPubAvgFraction;
		$authorTopicPubEstFraction = $wordbag->{$k}->authorTopicPubEstFraction;
		
		if($freq == 1 || $authorNumNonForay == 0){
			$tf = 0;
			$tfiaf = 0;
			$iaf = 0;
		}
		else{	
			#$tf = $authorHitFreqSum / $authorNum;
			#$tfiaf = ($authorHitFreqSum / $authorNum) * 
			#								(log($maxAuthorHitFreqSum / $authorHitFreqSum) + 1);

			$tf = $authorTopicPubEstFraction;
			$iaf = log($maxAuthorNum / $authorNumNonForay) + IAF_LEAST_VALUE;
			$tfiaf = $tf * $iaf;
		}

		#$tfiaf = $authorHitFreqSum == 1 ? 0 : ($authorHitFreqSum / $authorNum) * log($gRecordCount / $authorHitFreqSum);
		#$iaf = $authorHitFreqSum == 1 ? 0 : log($gRecordCount / $authorNum);
		
		($tf, $tfiaf, $iaf) = trunc(3, $tf, $tfiaf, $iaf);
		
		if($tf > 0 && $weightRange{'tf.min'} > $tf){
			$weightRange{'tf.min'} = $tf;
		}
		if($tf > 0 && $weightRange{'tf.max'} < $tf){
			$weightRange{'tf.max'} = $tf;
			$weightRange{'tf.max.word'} = $k;
		}
		if($tfiaf > 0 && $weightRange{'tfiaf.min'} > $tfiaf){
			$weightRange{'tfiaf.min'} = $tfiaf;
		}
		if($tfiaf > 0 && $weightRange{'tfiaf.max'} < $tfiaf){
			$weightRange{'tfiaf.max'} = $tfiaf;
			$weightRange{'tfiaf.max.word'} = $k;
		}
		if($iaf > 0 && $weightRange{'iaf.min'} > $iaf){
			$weightRange{'iaf.min'} = $iaf;
		}
		if($iaf > 0 && $weightRange{'iaf.max'} < $iaf){
			$weightRange{'iaf.max'} = $iaf;
			$weightRange{'iaf.max.word'} = $k;
		}
		
		$wordbag->{$k}->tf($tf);
		$wordbag->{$k}->tfiaf($tfiaf);
		$wordbag->{$k}->iaf($iaf);
	}
	print $tee "$counter / $wordcount   Done.\n";
	
	print $tee "TF     is in [ $weightRange{'tf.min'}, $weightRange{'tf.max'} ] " . 
				"(max word \'$weightRange{'tf.max.word'}\')\n";
	print $tee "TF*IAF is in [ $weightRange{'tfiaf.min'}, $weightRange{'tfiaf.max'} ] " . 
				"(max word \'$weightRange{'tfiaf.max.word'}\')\n";
	print $tee "IAF    is in [ $weightRange{'iaf.min'}, $weightRange{'iaf.max'} ] " . 
				"(max word \'$weightRange{'iaf.max.word'}\')\n";
	
=pod	
	$counter = 0;
	
	print $tee "Third pass: scale TF, TF*IAF and IAF into [ ". WEIGHT_LOWER . ", " . WEIGHT_UPPER . " ]\n";

	my ($AFscaler, $TFIAFscaler, $IAFscaler);
	$AFscaler    = makeScaler($weightRange{'tf.min'}, $weightRange{'tf.max'}, "TF");
	$TFIAFscaler = makeScaler($weightRange{'tfiaf.min'}, $weightRange{'tfiaf.max'}, "TF*IAF");
	$IAFscaler   = makeScaler($weightRange{'iaf.min'}, $weightRange{'iaf.max'}, "IAF");
	
	for $k(keys %{$wordbag}){
		if($counter % 1000 == 0){
			print "\r$counter / $wordcount\r";
		}
		$counter++;
		
		$wordbag->{$k}->tf( &$AFscaler($wordbag->{$k}->tf) );
		$wordbag->{$k}->tfiaf( &$TFIAFscaler($wordbag->{$k}->tfiaf) );
		$wordbag->{$k}->iaf( &$IAFscaler($wordbag->{$k}->iaf) );
	}
	print $tee "$counter / $wordcount   Done.\n";
=cut

	return %weightRange;
}

sub calc12TFIAF
{
	if($COUNT_BIGRAM){
		%gBigramWeightRange  = calcTFIAF(\%gBigrams);
	}
	if($COUNT_UNIGRAM){	
		%gUnigramWeightRange = calcTFIAF(\%gUnigrams);
	}	
}

=pod
sub makeScaler
{
	my ($min, $max, $weightName) = @_;
	my $scale;
	my $scaler;
	
	if($max == $min){
		print $tee "max $weightName == min $weightName, which shouldn't happen. Leave $weightName untouched\n";
		$scaler = sub { $_[0] };
	}
	else{
		$scale = (WEIGHT_UPPER - WEIGHT_LOWER) / ($max - $min);
		$scaler = sub { return $_[0] if $_[0] <= 0; ($_[0] - $min) * $scale + WEIGHT_LOWER };
	}
}
=cut
