use feature qw(switch say);
use strict;
use warnings 'all';
use Getopt::Std;
use List::Util qw(min max sum);
use File::Basename;

my $CLUST_THRES 				= 0.05;
my $UNIGRAM_CLUST_THRES			= 0.2;
# 1 - \theta_p
my $COAUTHOR_ERROR_TOLERANCE	= 0.05;
my $COAUTHOR_SAME_CAT_ODDS_THRES = 1;

use constant{
	OPTIONS 					=> 'c:a:i:1s:b:j:ud:t:p:A:v:',
	namedisDir 					=> "/media/tough/namedis",
	wikipediaDir 				=> "/media/first/wikipedia",
};

use lib namedisDir;
use NLPUtil;
use Distinct;

use lib wikipediaDir;
use ConceptNet;

my $namedisDir = namedisDir;
my $wikipediaDir = wikipediaDir;
#my $DEFAULT_DBLP_FILEPATH 			= "$namedisDir/dblp.extracted.txt",
my $DEFAULT_IC_FILEPATH 			= "$wikipediaDir/ic.txt";
my $DEFAULT_LEMMA_CACHE_FILEPATH 	= "$wikipediaDir/lemma-cache.txt";
my $DEFAULT_ANCESTOR_FILEPATH		= "$wikipediaDir/ancestors.txt";

my %opt;
getopts(OPTIONS, \%opt);

my $iniDBFilename;

if(@ARGV > 0){
	$iniDBFilename = shift @ARGV;
}

my $LEMMA_CACHE_LOAD_FILENAME;
my $LEMMA_CACHE_SAVE_FILENAME;
my $ANCESTORS_LOAD_FILENAME;
my $COAUTHOR_STAT_FILENAME;
my $IC_FILE_NAME;
my $processedOptionCount = 0;

my $ambiguityScale = 1;
#if(exists $opt{'A'}){
#	$ambiguityScale = $opt{'A'};
#	print STDERR "Name ambiguity scaled by $ambiguityScale\n";
#}

if(!exists $opt{'i'}){
    print STDERR "Use default IC file: $DEFAULT_IC_FILEPATH\n";
	$IC_FILE_NAME = $DEFAULT_IC_FILEPATH;
}
else{
	$IC_FILE_NAME = $opt{'i'};
	if(! -e $IC_FILE_NAME){
		die "FATAL  IC file '$IC_FILE_NAME' doesn't exist, please check\n";
	}
	
	print STDERR "Will load IC file '$IC_FILE_NAME'\n";
	$processedOptionCount++;
}

if(!exists $opt{'c'}){
	print STDERR "Use default lemma cache file: $DEFAULT_LEMMA_CACHE_FILEPATH\n";
	$LEMMA_CACHE_LOAD_FILENAME = $DEFAULT_LEMMA_CACHE_FILEPATH;
}
else{
	$LEMMA_CACHE_LOAD_FILENAME = $opt{'c'};
}

if(! -e $LEMMA_CACHE_LOAD_FILENAME){
	die "FATAL  lemma cache file '$LEMMA_CACHE_LOAD_FILENAME' doesn't exist, please check\n";
}
$processedOptionCount++;

my $batchMode = 0;
my $batchFilename;
if(exists $opt{'b'}){
	$batchFilename = $opt{'b'};
	
	if(! -e $batchFilename){
		die "Batch file '$batchFilename' is not found! Abort.\n";
	}
	$batchMode = 1;
	$processedOptionCount++;
}

if(exists $opt{'v'}){
	$NLPUtil::USE_CSLR_VERSION = $opt{'v'};
}

if($NLPUtil::USE_CSLR_VERSION == 1){
	print STDERR "Use old CSLR\n";
}
else{
	print STDERR "Use new CSLR\n";
}

my $clusterByCoauthorOnly = 0;
if(exists $opt{'1'}){
	$clusterByCoauthorOnly = 1;
}
else{
	if(!exists $opt{'a'}){
		print STDERR "Use default ancestor file: $DEFAULT_ANCESTOR_FILEPATH\n";
		$ANCESTORS_LOAD_FILENAME = $DEFAULT_ANCESTOR_FILEPATH;
	}
	else{
		$ANCESTORS_LOAD_FILENAME = $opt{'a'};
	}
	if(! -e $ANCESTORS_LOAD_FILENAME){
		die "FATAL  lemma cache file '$ANCESTORS_LOAD_FILENAME' doesn't exist, please check\n";
	}
	print STDERR "Will load ancestor lists from file '$ANCESTORS_LOAD_FILENAME'\n";
	$processedOptionCount++;
}

# the threshold is specified by $opt{'j'}
my $jaccardThres = 0;
if(exists $opt{'j'}){
	$jaccardThres = $opt{'j'};
	print STDERR "Will use Jaccard similarity\n";
}

my $useUnigram = 0;
if(exists $opt{'u'}){
	$useUnigram = 1;
	print STDERR "Will use unigram to measure title similarity\n";
}

my $stepDelta = 0.001;
if(exists $opt{'d'}){
	$stepDelta = $opt{'d'};
	print STDERR "Will choose jaccard similarity step size $stepDelta\n";
}

if(exists $opt{'t'}){
	if($useUnigram){
		$UNIGRAM_CLUST_THRES = $opt{'t'};
	}
	else{
		$CLUST_THRES = $opt{'t'};
	}
	print STDERR "Will use base clustering thershold $opt{'t'}\n";
}

my $dirPrefix = "";
if(exists $opt{'p'}){
	$dirPrefix = $opt{'p'};
	if( $dirPrefix !~ /\/$/ ){
		$dirPrefix .= "/";
	}
	print STDERR "Data file path prefix: '$dirPrefix'\n";
}

my $iniAuthorName;
# if not in batch mode, $ALLLOG is $tee
# if in batch mode: during initialization, $ALLLOG is $tee, i.e. Tee($LOG, STDERR)
# when clustering begins, $ALLLOG is Tee($tee, $CLUSTLOG), i.e. Tee($LOG, STDERR, $CLUSTLOG)
my $ALLLOG;
my $CLUSTLOG;

if($iniDBFilename){
	$iniAuthorName = basename( $iniDBFilename );
	$iniAuthorName =~ s/(-\w+)?\.txt//;
	openLogfile($iniAuthorName);
}
else{
	openLogfile();
}

$CLUSTLOG = $LOG;
$ALLLOG = $tee;

my $DEBUG = ConceptNet::DBG_CALC_MATCH_WEIGHT 
							| 
			ConceptNet::DBG_MATCH_TITLE 
					 		| 
			ConceptNet::DBG_TRACK_ADD_FREQ
					 		|
#			ConceptNet::DBG_ADD_EDGE
#					 		|
			ConceptNet::DBG_CHECK_ROOT_ANCESTOR
					 		|
#			ConceptNet::DBG_TRAVERSE_NET
#					 		|
#			ConceptNet::DBG_LOAD_ANCESTORS			
#					 		|
			ConceptNet::DBG_CHECK_INHERIT_DEPTH_RATIO
					 		|
#			ConceptNet::DBG_LOAD_IC
#							|
			ConceptNet::DBG_CALC_SIMI
							|
			NLPUtil::DBG_EXPAND_SIMI_VENUES
					 		|
			NLPUtil::DBG_PROB_MERGE_BY_COAUTHOR;
			#		 ConceptNet::DBG_TRAVERSE_NET_LOW_OP								
					;
					
if($clusterByCoauthorOnly){
	$LEMMA_CACHE_LOAD_FILENAME = "";
#	$COAUTHOR_STAT_FILENAME = "";
}
$COAUTHOR_STAT_FILENAME = "${dirPrefix}coauthor-stat.txt";

setDebug($DEBUG);

my @treeRoots = ("computer science", "computer engineering", "Electromagnetism", "Mathematics", "Linguistics");

NLPUtil::initialize(	lemmaCacheLoadFile => $LEMMA_CACHE_LOAD_FILENAME, 
						lemmaCacheSaveFile => $LEMMA_CACHE_SAVE_FILENAME,
						loadChnNameAmbig => "${dirPrefix}ambiguity.csv",
						loadNameCoauthors => $COAUTHOR_STAT_FILENAME,
						progressVars => [ \$gRecordCount ], 
			   	   );

my $chnNameCount = 0;
my $revChnNameCount = 0;

my %gNames;
my @gPublications = ("BUG");	# the '0'th publication is a place holder
								# to make the ID starts from 1
my %gPubCountByYear;
my %gAuthorNames2ID;	# string -> no.

my $gIdID;
my @gIdentities;
my %gIdentity2id;
my @gAuthorPubCount;

my $groundtruthLoaded = 0;
my $groundtruthTotalPairCount = 0;

loadSimilarVenues("venue-simi.txt");

if($iniDBFilename){
	if($iniDBFilename =~ /-labels.txt/i){
		loadGroundtruth($iniDBFilename);
	}
	else{
		loadDBLPFile($iniDBFilename);
	}
	if($clusterByCoauthorOnly){
		if(exists $opt{'s'}){
			my $distinctLabelFilename = $opt{'s'};
			my @seedClusterKeys = loadDistinctLabels($distinctLabelFilename);
			clusterAuthor(origName => $iniAuthorName, clusterByCoauthorOnly => 1,
							seedClusterKeys => \@seedClusterKeys, jaccardThres => $jaccardThres );
		}
		else{
			clusterAuthor(origName => $iniAuthorName, clusterByCoauthorOnly => 1, 
							jaccardThres => $jaccardThres, useUnigram => $useUnigram );
		}
		
		exit;
	}
}

if( ! $clusterByCoauthorOnly && ! $useUnigram ){
	ConceptNet::initialize( taxonomyFile => "$wikipediaDir/csmathling-full.txt", 
							rootterms => \@treeRoots, 
							ancestorsLoadFile => $ANCESTORS_LOAD_FILENAME, 
						   	newTermMode => ConceptNet::NEWTERM_COMPLEX,
						   	doAncestorExpansion => 1,
						  );
	
	loadNetIC(filename => $IC_FILE_NAME);
	
	setICOffset( 3.5 );
	
}

my %name2myperf;

if($batchFilename){
	batchCluster($batchFilename);
	exit;
}
elsif($groundtruthLoaded){
	clusterAuthor( origName => $iniAuthorName, jaccardThres => $jaccardThres, useUnigram => $useUnigram );
}

print STDERR "\n";
cmdline();

my $useTrueK = 0;

sub calcKClustThres($;$)
{
	my ($name, $K) = shift;
	my $clustThres;
	
	my $baseClustThres = $useUnigram? $UNIGRAM_CLUST_THRES : $CLUST_THRES;
	
	if(! $K){
		if(!exists $chnNameAmbig{$name}){
			$K = 2;
			$clustThres = $baseClustThres;
		}
		# $K will be set in clusterAuthor()
		else{
			$K = 0;
			$clustThres = $baseClustThres * max( 1, $chnNameAmbig{$name} * $ambiguityScale / 10 );
		}
	}
	else{
		$clustThres = $baseClustThres * max( 1, $K / 10 );
	}
	
	if(wantarray){
		return ($clustThres, $K);
	}
	else{
		return $clustThres;
	}
}

sub batchCluster
{
	my $batchFilename = shift;
	my $BATCH;
	
	print $ALLLOG "Open batch file '$batchFilename' to process...\n";
	
	open_or_die($BATCH, "< $batchFilename");
	
	print $ALLLOG "\n";
	
	my $line;
	my ($name, $clustThres, $trueK, $K);
	my $labelFilename;
	my $nameCount = 0;
	my @testnames;
	
	%name2myperf = ();
	
	while( $line = <$BATCH> ){
		trim($line);
		next if !$line || $line =~ /^#/;
		
		# each line a name
		$name = $line;
		
#		$clustThres = trunc(2, $clustThres);
#		$clustThres = $CLUST_THRES;
		
		$labelFilename = $dirPrefix . lc($name) . "-labels.txt";
		
		push @testnames, $name;
		
		if( ! $jaccardThres || ! $clusterByCoauthorOnly ){
			openLogfile($name);
			$ALLLOG = new IO::Tee($tee, $CLUSTLOG);
		}
		
		loadGroundtruth($labelFilename);

		$trueK = $gIdID - 1;
		
		# don't use the human-labeled K. This is more fair
		if( ! $useTrueK ){
			($clustThres, $K) = calcKClustThres($name);
		}
		else{
			$K = $trueK;
			$clustThres = calcKClustThres( $name, $K );
		}
		
		print $ALLLOG "Processing author '$name', true K: $trueK, estimated K: ", 
						($chnNameAmbig{$name} || 0 ) * $ambiguityScale, "\n";
		
		clusterAuthor(origName => $name, K => $K, clustThres => $clustThres, quiet => 1,
						jaccardThres => $jaccardThres, clusterByCoauthorOnly => $clusterByCoauthorOnly,
						useUnigram => $useUnigram );
		
		$nameCount++;
	}

	print $ALLLOG "\n$nameCount names are clustered\n";
	
	my (%perfSum1, %perfSum2);
	my $k;
	my $thres;
	
	for $name(@testnames){
		for $thres( keys %{ $name2myperf{$name}{0} } ){
			for $k( "precision", "recall", "f1" ){
				$perfSum1{$thres}{$k} += $name2myperf{$name}{0}{$thres}{$k};
			}
		}
		if( ! $clusterByCoauthorOnly ){
			for $thres( keys %{ $name2myperf{$name}{1} } ){
				for $k( "precision", "recall", "f1" ){
					$perfSum2{$thres}{$k} += $name2myperf{$name}{1}{$thres}{$k};
				}
			}
		}
	}

	print $ALLLOG "\nAverage:\n\n";
	print $ALLLOG "                    Precision\tRecall\tF1\n";
	print $ALLLOG "Coauthor ";
	
	for $thres( sort { $a <=> $b } keys %perfSum1 ){
		print $ALLLOG $thres, "\t\t";
		
		for $k( "precision", "recall", "f1" ){
			printf $ALLLOG "%.3f\t", $perfSum1{$thres}{$k} / $nameCount;
		}
		print $ALLLOG "\n";
	}
	
	if( $clusterByCoauthorOnly ){
		return;
	}
	
	print $ALLLOG "\nTitle,Venue ";
	
	for $thres( sort { $a <=> $b } keys %perfSum2 ){
		print $ALLLOG $thres, "\t\t";

		for $k( "precision", "recall", "f1" ){
			printf $ALLLOG "%.3f\t", $perfSum2{$thres}{$k} / $nameCount;
		}
		print $ALLLOG "\n";
	}
}

sub loadDBLPFile
{
	my $title;
	my $authorLine;
	my @authorNames;
	my $year;
	my $thisPublication;

	my $dblpFilename = shift;
	print $ALLLOG "Open file '$dblpFilename' to process...\n";

	my $DB;
	if(! open_or_warn($DB, "< $dblpFilename")){
		return;
	}
	
	$groundtruthLoaded = 0;
	
	@gPublications = ("BUG");
	%gNames = ();
	
	my $name;
	my $pubID;

	while(!eof($DB)){
		$thisPublication = parseCleanDBLP($DB);
		
		$title = $thisPublication->title;
		@authorNames = @{ $thisPublication->authors };
		$year = $thisPublication->year;
	
		$pubID = @gPublications;
		push @gPublications, $thisPublication;
		
		my $isNameReverse = $thisPublication->isNameReverse;
		if($isNameReverse < 0){
			next;
		}
		
		for $name(@authorNames){
#			if( isChineseName($name) && !isCantoneseName($name, $isNameReverse) ){
				attachPubToAuthor($name, $pubID);
#			}
		}
		
		progress2();
	}
	
	print $ALLLOG "\n";
	print $ALLLOG scalar @gPublications - 1, " publications loaded.\n\n";
}

sub identity2id
{
	my $identity = shift;
	
	# an "N/A" may be followed by comments/reasons
	if($identity =~ m{^N/A}){
		return -1;
	}
	
	return key2id($identity, \%gIdentity2id, \@gIdentities, $gIdID);
}

sub loadGroundtruth
{
	my $truthFilename = shift;
	print $ALLLOG "Open groundtruth file '$truthFilename' to process...\n";

	my $DB;
	if(! open_or_warn($DB, "< $truthFilename")){
		return;
	}
	
	$groundtruthLoaded = 1;
	$groundtruthTotalPairCount = 0;
	
	@gPublications = ("BUG");
	%gNames = ();

	$gIdID = 1;
	@gIdentities = ("BUG");
	%gIdentity2id = ();
	@gAuthorPubCount = ("BUG");
	
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
				print $ALLLOG $DB->input_line_number, ": Cluster size $clustSize != $readcount (read count)\nStop reading the file.\n";
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
				
				$authorID = identity2id($identity);
				
				$expectClusterHeading = 0;
				next;
			}
			else{
				print $ALLLOG "$.: Unknown cluster heading:\n$line\nStop reading the file.\n";
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
		@authorNames = @{ $thisPublication->authors };
	
		$pubID = @gPublications;
		push @gPublications, $thisPublication;
		
		my $isNameReverse = $thisPublication->isNameReverse;
		if($isNameReverse < 0){
			next;
		}
		
		for $name(@authorNames){
#			if( isChineseName($name) && !isCantoneseName($name, $isNameReverse) ){
				attachPubToAuthor($name, $pubID);
#			}
		}
	}
	
	print $ALLLOG scalar @gPublications - 1, " publications of ", $gIdID - 1, " authors loaded\n";
	
	my @authorIndices = sort { $gAuthorPubCount[$b] <=> $gAuthorPubCount[$a] } ( 1 .. $gIdID - 1 );

	print $ALLLOG join(" | ", map { "$gIdentities[$_]: $gAuthorPubCount[$_]" } @authorIndices );
	print $ALLLOG "\n";

	my $i;
	for($i = 1; $i < $gIdID; $i++){
		$groundtruthTotalPairCount += NChoose2( $gAuthorPubCount[$i] );
	}
	print $ALLLOG "Groundtruth total pairs: $groundtruthTotalPairCount\n\n";
}

sub loadDistinctLabels
{
	my $labelFilename = shift;
	my $LABELS;
	open_or_die($LABELS, "< $labelFilename");
	
	# discard the header
	<$LABELS>;<$LABELS>;<$LABELS>;
	
	my $line;
	
	my @seedClusterKeys = ();
	
	while($line = <$LABELS>){
		trim($line);
		next if !$line;
		
		#Cluster 0, 57 tuples (UNC)
		if( $line =~ /^Cluster \d+, \d+ tuples/ ){
			push @seedClusterKeys, [];
		}
		elsif( $line =~ m{,    "([\w/]+)"   } ){
			push @{ $seedClusterKeys[-1] }, $1;
		}
		else{
			die "Unknown format:\n$line\n";
		}
	}
	
	print $ALLLOG scalar @seedClusterKeys, " seed clusters loaded\n";
	return @seedClusterKeys;
}

sub attachPubToAuthor
{
	my ($name, $pubID) = @_;
	
	$name = lc($name);
	
	if(exists $gNames{$name}){
		push @{$gNames{$name}->publist}, $pubID;
	}
	else{
		$gNames{$name} = author->new( publist => [ $pubID ] );
	}
}

sub saveClusters($$$$$$)
{
	my ( $clustFilename, $pClusters, $pClusterVecs, $pClusterNos, $pubset, $useUnigram ) = @_;

	$clustFilename = getAvailName($clustFilename);
	
	my $CLUST;
	
	print $ALLLOG "Clusters are saved into '$clustFilename'\n";
	open_or_die($CLUST, "> $clustFilename");
	
	my $CC = @$pClusters;
	
	print $CLUST "$CC clusters.\n\n";
	
	my $c;
	my $N;
	my $no;
	my @titleIDs;
	my $titleID;
	my ($i, $index);
	my $pub;
	
	my @clustIndices = sort { scalar @{$pClusters->[$b]} <=> scalar @{$pClusters->[$a]} } (0 .. $CC - 1);
	
	for($i = 0; $i < @clustIndices; $i++){
		$index = $clustIndices[$i];
		$c = $pClusters->[$index];
		if($pClusterNos){
			$no = $pClusterNos->[$index];
		}
		else{
			$no = $i + 1;
		}
		$N = @{$c};
		print $CLUST "Cluster $no, $N papers:\n";
		
		@titleIDs = sort { $pubset->[$a]->year <=> $pubset->[$b]->year } @$c;
		for $titleID(@titleIDs){
			$pub = $pubset->[ $titleID ];
			dumpPub($CLUST, $pub, \@gIdentities);
		}
		
		if($pClusterVecs){
			print $CLUST "Concept Vec: ";
			dumpConceptVenueVec($CLUST, $pClusterVecs->[$index], $useUnigram);
		}
			
		print $CLUST "\n";
	}
}

sub calcPerf($$$$$$;$)
{
	if(! $groundtruthLoaded){
		return;
	}
	
	my ( $pClusters, $pClusterNos, $pubset, $batchMode, $focusName, $stage, $thres ) = @_;
	
	my $CC = @$pClusters;
	my $i;
	my $pub;
	
	for($i = 1; $i < @$pubset; $i++){
		$pub = $pubset->[$i];

		if(! $pub->authorID){
			print $ALLLOG "Author ID of publication $i is not assigned:\n";
			dumpPub($ALLLOG, $pub);
			print $ALLLOG "You forgot to load the groundtruth file?\n";

			$groundtruthLoaded = 0;
			return 0;
		}
	}
	
	print $ALLLOG "$CC clusters. Should be ", $gIdID - 1, ".\n\n";
	
	my $c;
	my $N;
	my $no;
	my $titleID;
	
	my @clustIndices = sort { scalar @{$pClusters->[$b]} <=> scalar @{$pClusters->[$a]} } (0.. $CC - 1);
	
	my $totalRightPairCount = 0;
	my $totalWrongPairCount = 0;
	my $clustRightPairCount;
	my $clustWrongPairCount;
	
	my $actualTotalPairCount = 0;
	my $clustPairCount;
	
	my @clustAuthorPubCount;
	
	for $i(@clustIndices){
		$c = $pClusters->[$i];
		if($pClusterNos){
			$no = $pClusterNos->[$i];
		}
		else{
			$no = $i + 1;
		}
		
		$N = @{$c};
		$clustPairCount = NChoose2($N);
		$actualTotalPairCount += $clustPairCount;

		print $ALLLOG "Cluster $no: $N papers, $clustPairCount pairs.\n";
		
		@clustAuthorPubCount = $gIdID x (0);
		
		for $titleID(@{$c}){
			$pub = $pubset->[ $titleID ];
			$clustAuthorPubCount[ $pub->authorID ]++;
		}
		
		my @authorIndices = sort { $clustAuthorPubCount[$b] <=> $clustAuthorPubCount[$a] }
								grep { defined( $clustAuthorPubCount[$_] ) } ( 1 .. $gIdID - 1 );

		print $ALLLOG join(" | ", map { "$gIdentities[$_]: $clustAuthorPubCount[$_]" } @authorIndices );
		print $ALLLOG "\n";
		
		$clustRightPairCount = 0;
		$clustWrongPairCount = 0;
		
		my $authorID;
		for $authorID(@authorIndices){
			my $s = $clustAuthorPubCount[$authorID];
			$clustRightPairCount += NChoose2($s);
			$clustWrongPairCount += $s * ($N - $s);
		}
		# repetition: {author A's pubs} -> {author B's pubs}, {author B's pubs} -> {author A's pubs}
		$clustWrongPairCount /= 2;
		
		if($clustRightPairCount + $clustWrongPairCount != $clustPairCount){
			die;
		}

		print $ALLLOG "$clustRightPairCount right pairs, $clustWrongPairCount wrong\n";
		print $ALLLOG "\n";
					
		$totalRightPairCount += $clustRightPairCount;
		$totalWrongPairCount += $clustWrongPairCount;
	}
	
	my $precision = $totalRightPairCount / $actualTotalPairCount;
	my $recall    = $totalRightPairCount / $groundtruthTotalPairCount;
	my $f1        = f1($precision, $recall);

	($precision, $recall, $f1) = trunc(4, $precision, $recall, $f1);

	print $ALLLOG "Summary:\n";
	print $ALLLOG "Prec: $precision. Recall: $recall. F1: $f1\n\n";
	
	if($batchMode){		
		$name2myperf{$focusName}{$stage}{$thres}{precision} = $precision;
		$name2myperf{$focusName}{$stage}{$thres}{recall} = $recall;
		$name2myperf{$focusName}{$stage}{$thres}{f1} = $f1;
	}
}
	
sub clusterAuthor
{
	my %args = @_;
	
	my $origName = $args{origName};
	if(!$origName){
		print $ALLLOG "The author name to cluster is not given, abort\n";
		return;
	}
	my $name = lc($origName);
	if($nameReplaceList{$name}){
		$name = $nameReplaceList{$name};
	}
	
	if(!exists $gNames{$name}){
		print $ALLLOG "'$origName' doesn't appear in the loaded DBLP file. Abort\n";
		return;
	}

	my $isChineseName = 1;
	
	if(!exists $chnNameAmbig{$name}){
		$isChineseName = 0;
		print $ALLLOG "Warn: '$origName' doesn't look like a Chinese name\n";
	}
	
#	my @coauthorBlacklist;
#	my %coauthorBlacklist;
#	if($args{coauthorBlacklist}){
#		@coauthorBlacklist = split /,\s*/, $args{coauthorBlacklist};
#		%coauthorBlacklist = map { $_ => 1 } @coauthorBlacklist;
#		print $tee "Coauthors '", join("', '", @coauthorBlacklist), "' are ignored as evidences\n";
#	}

	my $thres;
	my $jaccardThres = $args{jaccardThres};
	my ( $coauthorJacThres, $venueJacThres, $minCoauthorJacThres, $maxCoauthorJacThres,
			$minVenueJacThres, $maxVenueJacThres );
			
	if($jaccardThres){
		($coauthorJacThres, $venueJacThres) = split /,/, $jaccardThres;
		if($coauthorJacThres){
			($minCoauthorJacThres, $maxCoauthorJacThres) = split /-/, $coauthorJacThres;
			if(! $maxCoauthorJacThres){
				$maxCoauthorJacThres = $minCoauthorJacThres;
			}
			print $ALLLOG "Using Jaccard simi for coauthors. Thres: $minCoauthorJacThres - $maxCoauthorJacThres\n";
		}
		if($venueJacThres){
			($minVenueJacThres, $maxVenueJacThres) = split /-/, $venueJacThres;
			if(! $maxVenueJacThres){
				$maxVenueJacThres = $minVenueJacThres;
			}
			print $ALLLOG "Using Jaccard simi for venues. Thres: $minVenueJacThres - $maxVenueJacThres\n";
		}
	}
		
	my @pubIDs = @{$gNames{$name}->publist};
	my @pubset = map { $gPublications[$_] } @pubIDs;
	my @years  = map { $_->year }  @pubset;
	my @titles = map { $_->title } @pubset;
	my @identities;

	if(! $args{clusterByCoauthorOnly}){
		@identities = map { $gIdentities[ $_->authorID ] } @pubset;
	}
	
	my $titleCount = @titles;

	# align @titles with pubsn's, @title_Coauthors & @title_ConceptVectors
	unshift @titles, "BUG";
	unshift @identities, "BUG";
	unshift @pubset, "BUG";
	unshift @years, "BUG";

	my (@clusters, @clusters1);

	my $pubsn;
	# pubsn is 1~$titleCount (all the papers by this author), 
	# different from pubID (whose range is determined by the DB file loaded
	my %pubkey2sn;
	
	for $pubsn(1 .. $titleCount){
		push @clusters, [ $pubsn ];
		$pubkey2sn{ lc( $pubset[$pubsn]->pubkey ) } = $pubsn;
	}

	my @title_Coauthors = ("BUG");	# place holder, catch bug if accessed
	push @title_Coauthors, map { [ @{ $gPublications[$_]->authors } ] } @pubIDs;

	my %context = (	 
					 focusName => $name,
					 titles =>	\@titles,
					 identities => \@identities,
					 years => \@years,
					 pubset => \@pubset,
					 gIdentities => \@gIdentities
				  );

	my $useUnigram = $args{useUnigram};
	my $seedClusterKeys = $args{seedClusterKeys};
	my $seedClusterKey;
	my @seedClusters;
	my @unknownKeys;

	print $ALLLOG "Try to merge $titleCount papers of '$origName' by coauthorship\n";
	
	# seeds are to assist in building the ground truth file.
	# they are not used in the testing. otherwise it's cheating
	if($seedClusterKeys){
		for $seedClusterKey(@$seedClusterKeys){
			@unknownKeys = grep { ! exists $pubkey2sn{$_} } @$seedClusterKey;
			if(@unknownKeys){
				print $ALLLOG "Unknown pubkeys:\n", join(", ", @unknownKeys), "\n";
				exit;
			}
			push @seedClusters, [ map { $pubkey2sn{$_} } @$seedClusterKey ];
		}
		@clusters1 = seedMergeSharingCoauthor( \@clusters, \@seedClusters,
						\@title_Coauthors, \%context );
	}
	else{
		#@clusters1 = mergeSharingCoauthor($name, \@clusters, \@title_Coauthors);
		if( $isChineseName ){
			if( ! $minCoauthorJacThres ){
				@clusters1 = probMergeSharingCoauthor( \@clusters, \@title_Coauthors, 
													$COAUTHOR_ERROR_TOLERANCE, $COAUTHOR_SAME_CAT_ODDS_THRES,
													\%context );
				#    ( $pClusters, $pClusterNos, $pubset, $batchMode, $focusName, $stage, $thres )									
				calcPerf( \@clusters1, undef, \@pubset, $batchMode, $name, 0, 0 );
				saveClusters("$origName-c1.txt", \@clusters1, undef, undef, \@pubset, $useUnigram);							
			}
			else{
				for($thres = $minCoauthorJacThres; $thres <= $maxCoauthorJacThres; $thres += $stepDelta){
					@clusters1 = jaccardMergeSharingCoauthor( \@clusters, \@title_Coauthors, 
																$thres, \%context );
					calcPerf( \@clusters1, undef, \@pubset, 1, $name, 0, $thres );
					saveClusters("$origName-c1.txt", \@clusters1, undef, undef, \@pubset, $useUnigram);
				}
			}
		}
		else{
			# non-Chinese names, merge by coauthors directly, no threshold.
			@clusters1 = mergeSharingCoauthor( \@clusters, \@title_Coauthors, \%context );
			
			if($minCoauthorJacThres){
				# fill in the slots of all thres values. for the convenience of summarization
				my $thres;
				for($thres = $minCoauthorJacThres; $thres <= $maxCoauthorJacThres; $thres += $stepDelta){
					calcPerf( \@clusters1, undef, \@pubset, 1, $name, 0, $thres );
				}
			}
			else{
				calcPerf( \@clusters1, undef, \@pubset, $batchMode, $name, 0, 0 );
			}
			
			if( ! $batchMode || ! $coauthorJacThres ){
				saveClusters("$origName-c1.txt", \@clusters1, undef, undef, \@pubset, $useUnigram);
			}
		}
	}
		
	if($args{clusterByCoauthorOnly}){
		return;
	}

	my $K = $args{K};
	
	if(! $isChineseName){
		if(! $K){
			print $ALLLOG "'$origName' doesn't appear to be a Chinese name, K is set to 2\n";
			$K = 2;
		}
	}
	elsif(! $K){
		$K = $chnNameAmbig{$name} * $ambiguityScale;
		
		# at least try to merge once, if the similarity is big enough
		$K = min( @clusters1 - 1, $K );
	}
	
	# westerners aren't provided with clustThres. Since all their estimated ambiguities are set to 2, 
	# the threshold is just $CLUST_THRES
	my $clustThres 	= $args{clustThres} || $CLUST_THRES;
	
	print $ALLLOG "Try to cluster $titleCount papers of '$origName' into $K clusters. Thres: $clustThres\n";
	
	if($useUnigram){
		print $ALLLOG "Use unigram to calc title simi.\n"
	}
	else{
		print $ALLLOG "\n";
	}
	
	my @title_ConceptVectors = ("BUG");
	
	my %matchTerms;
	
	print $ALLLOG "Extract concept vectors from titles:\n";
	
	for($pubsn = 1; $pubsn < @titles; $pubsn++){
		print STDERR "\r$pubsn\r";
		
		if($useUnigram){
			%matchTerms = unigramMatchTitle( $pubsn, $titles[$pubsn] );
		}
		else{
			%matchTerms = matchTitle( \@ancestorTree, $pubsn, $titles[$pubsn], 0.3, 0 );
		}
		
		push @title_ConceptVectors, { %matchTerms };
	}
	print $ALLLOG "Concept vectors of $pubsn papers extracted\n";
	
	$context{title_Coauthors} = \@title_Coauthors;
	$context{title_ConceptVectors} = \@title_ConceptVectors;
	$context{ancestorTree} = \@ancestorTree;
	$context{emptyConceptVecSimiPrior} = $clustThres / 2;
	$context{useUnigram} = $useUnigram;
	
	$context{ambig} = max( $K, 2 );
	
	emptyConceptVecSimiCache();

	if($minVenueJacThres){
		for($thres = $minVenueJacThres; $thres <= $maxVenueJacThres; $thres += $stepDelta){
			$context{venueJacThres} = $thres;

			if($venueJacThres){
				print $ALLLOG "venueJacThres: $thres.\n";
			}
			
			my ($pClusters, $pClusterVecs, $pClusterNos) = agglomerative($K, $clustThres, \%context, \&calcConceptVectorSimi, 
										\&titleSetToVector, \&dumpTitleset, \&dumpSimiTuple, \@clusters1);
			emptyConceptVecSimiCache();
			
			if( ! $batchMode ){
				saveClusters("$origName-c2.txt", $pClusters, $pClusterVecs, $pClusterNos, \@pubset, $useUnigram);
			}
			
			calcPerf($pClusters, $pClusterNos, \@pubset, $batchMode, $name, 1, $thres);
			
		}
	}
	else{
		my ($pClusters, $pClusterVecs, $pClusterNos) = agglomerative($K, $clustThres, \%context, \&calcConceptVectorSimi, 
									\&titleSetToVector, \&dumpTitleset, \&dumpSimiTuple, \@clusters1);
		
		emptyConceptVecSimiCache();
		
		saveClusters("$origName-c2.txt", $pClusters, $pClusterVecs, $pClusterNos, \@pubset, $useUnigram);
		
		calcPerf($pClusters, $pClusterNos, \@pubset, $batchMode, $name, 1, 0);
	}
}

sub cmdline
{
	my ($cmd, $cparam, $jparam, $param1, $param2, $excludes);
	my $jaccardThres;
	my ( $K, $name, $clustThres );
	my $input;
	
	my $terminal = Term::ReadLine->new('clust');
	my $prompt = "CMD>";

	while(1){
		$input = $terminal->readline($prompt);
		trim($input);
		if($input =~ /^(c([\d.]+)?|j([\d.,\-]+)?|off|raw|load|m|coauthor|b|uni)\s+(\d+ )?(.+)$/){
			#         $cmd $cparam   $jparam                   				     $param1 $param2
			$cmd = $1;
			$cparam = $2;
			$jparam = $3;
			$param1 = $4;
			$param2 = $5;
			
			$cmd =~ s/[\d.,\-]+$//;
			trim($param1, $param2);

			given($cmd){
				when(/^c$/){
					$clustThres = $cparam;
					$K = $param1;
					$name = $param2;
					clusterAuthor(origName => $name, K => $K, clustThres => $clustThres,
									useUnigram => $useUnigram
								 );
				}
				when(/^j$/){
					$jaccardThres = $jparam;
					$K = $param1;
					$name = $param2;
					# if $K is not provided, designate it in calcKClustThres()
					($clustThres, $K) = calcKClustThres($name, $K); 
					clusterAuthor(origName => $param2, K => $param1, clustThres => $clustThres,
									jaccardThres => $jaccardThres, useUnigram => $useUnigram
								 );
				}
				when(/^b$/){
					batchCluster($param2);
				}
				when(/^coauthor$/){
					clusterAuthor(origName => $param2, clusterByCoauthorOnly => 1, useUnigram => $useUnigram);
				}
				when(/^load$/){
					if(!$param2){
						print STDERR "DB/Groudtruth File name is not given\n";
						break;
					}
					
					$param2 =~ s/[\"\']//g;
					
					if($param2 =~ /-labels.txt/i){
						loadGroundtruth($param2);
					}
					else{
						loadDBLPFile($param2);
					}
				}
				when(/^off$/){
					if(!$param2){
						print STDERR "IC Offset is not given\n";
						break;
					}
					setICOffset($param2);
				}
				when(/^raw$/){
					if(!$param2){
						print STDERR "Code snippet is not given.\n";
						break;
					}
					eval $param2;
					if($@){
						print $ALLLOG "$@\n";
					}
					else{
						print $ALLLOG "\n";
					}
				}
				when(/^m$/){
					my $title = $param2;
					if(! $title){
						print STDERR "Title is not given.\n";
						break;
					}
					my (@lemmaIDs, @stopwordGapNums, @stopwordGapWeights);
					extractTitleTokens($title, \@lemmaIDs, \@stopwordGapNums, \@stopwordGapWeights);
					if(!@lemmaIDs){
						print STDERR "Title doesn't contain any valid word.\n";
						break;
					}
					print $ALLLOG "Keywords: ",
								quoteArray(map { $lemmaCache[$_]->[0] } @lemmaIDs), "\n\n";
	
					my %maxMatchFreqs = matchTitle(\@ancestorTree, 1, $title, 0.3, 0);
					my @postings = sort { $maxMatchFreqs{$b}->[0]
												<=>
										  $maxMatchFreqs{$a}->[0]
										} keys %maxMatchFreqs;
					my $posting;
					for $posting(@postings){
						print $ALLLOG "$terms[$posting], $maxMatchFreqs{$posting}->[0]: ",
							quoteArray( map { $lemmaCache[ $lemmaIDs[$_] ]->[0] } 
											@{ $maxMatchFreqs{$posting}->[1] } ),
									"\n";
					}
				}
				when(/^uni$/){
					$useUnigram = ! $useUnigram;
					if($useUnigram){
						print $ALLLOG "Unigram on.\n";
					}
					else{
						print $ALLLOG "Unigram off.\n";
					}
				}
			}
		}
		elsif($input){
			print STDERR "Invalid command.\n";
			next;
		}
		else{
			print STDERR "Are you sure you want to exit? (y/N) ";
			$input = <STDIN>;
			if($input =~ /^y$/i){
				last;
			}
		}
	}	
}
