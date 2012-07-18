use feature qw(switch say);

package NLPUtil;

use strict;
use warnings 'all';
use Class::Struct;
#use Devel::Size qw(size total_size);
#use Lingua::Stem::Snowball;
use Symbol 'qualify_to_ref';
#use Data::Dumper::Simple;
use IPC::Open2;
use File::Spec;
use File::Basename;
use List::Util qw(min max sum);
use List::MoreUtils qw(first_value);
use IO::Tee;
use Devel::Peek;
use Math::GammaFunction qw/:all/;

#use Win32::Sound;

# reserver 0 - 9 for DBG_* in NLPUtil. Don't add more than 10 flags here
use enum qw(BITMASK:DBG_  WEIRD_CHNNAME  MERGE_HASH_OVERWRITE
							NLPUTIL_LAST EXPAND_SIMI_VENUES PROB_MERGE_BY_COAUTHOR);

# note the last is STOPWORD instead of SUFFIX_STOPWORD
use enum qw(:SUFFIX_  ING ED NONE : STOPWORD);

our $DEBUG = 0;
our $QUIET_EXIT = 1;

use constant{
	MAX_MEMSIZE_TO_CALC 	=> 512*1024*1024,
	MAX_CONSOLE_LIST_SIZE 	=> 50,
	INT_MAX 				=> 2147483647,

	# ';' separates the prog name with params, to facilitate 'open2' later
#	MORPHA_CMDLINE => 'c:/wikipedia/morpha;-u',
	MORPHA_CMDLINE => './morpha;-u',
};

our $KEEP_STOP_WORD_WHEN_N_NONSTOP_TOKENS = 2;
our $USE_CSLR_VERSION = 2;
our $CSLR_VENUE_UNSEEN_REDUCTION_FRAC = 0.3334;
our $CSLR_COAUTHOR_UNSEEN_REDUCTION_FRAC = 0.3334;
our $CAT_PRIOR = 0.5;
our $FILTER_STRONGEVI_COAUTHORS_B4_CSLR = 1;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw( openLogfile setDebug
				  abort progress2 makeProgresser progress progress_end hhmmss
				  trim trimLeading trimTrailing trimPunc restoreXmlEntity
				  decap cap variousCaps
				  capcount wc wc_nostopword buildOrRE chop_or_del
				  stem stemPhrase recoverStem removeStopWords
				  lemmatize0 lemmatize lemmatizePhrase recoverLemma getLemma

				  DBG_NLPUTIL_LAST STOPWORD

				  c1000 size1000 total_size1000 combineWW WWSplit lowerword higherword
				  roundAtLeast1 atLeast1 trunc definedOr0 dieIfNotInteger weightedAverage linearFunction
				  ratio isVeryClose isBetween
				  key2id
				  getAvailName open_or_die open_or_warn
				  topN topBottomN time2hms
				  intersect intersectHash unionArrayToArray unionArrayToHashRef subtractSet 
				  intersectArrayOfArray subtractHash dedup arrayOrFirst hashTopN schwartzianSort
				  copyRefArray quoteArray mergeHash statsByValue dumpSortedHash filterHash
				  bitmap2nums bitmap2desc
				  f1 NChoose2 indexOfMax
				  
				  parseCleanDBLP parseDBLPBlock dumpPub
				  loadPinyin loadPinyins loadGramFile loadGramFiles
				  loadCache saveCache playsound
				  loadPublishers removePublisher

				  isChineseName isCantoneseName testChnNameReverse standardizeChineseName
				  loadChnNameAmbig loadNameCoauthors overestimateAmbig
				  
				  extractTitleGrams extractTitleWords extractTitleTokens

				  jaccard  isSameCategorical isSameCategorical2 loadSimilarVenues expandSimilarVenues
				  factorial combination logFactorial logCombination 
				
				  agglomerative mergeSharingCoauthor seedMergeSharingCoauthor probMergeSharingCoauthor
				  jaccardMergeSharingCoauthor
				  coauthorEvidenceError coauthorEvidenceThresToCnCountThres clusterAuthors dumpPubCluster
					
				  $startTime $timestamp $DEBUG $LOG $tee
				  %stopwords %venueType
				  @lemmaCache %lemmaLookup %invLemmaTable
				  $recordStartLn $gRecordCount
				  %pinyinNames %cantonpinyinNames %gBigrams %gUnigrams
				  INT_MAX %twochar_surname
				  $puncRE $yearRE $pageRE $bindingRE $editorRE $publishersRE %puncs %xmlSymMap
				  $reviewRE1 $reviewRE2
				  %chnNameAmbig %surnameAmbig %givennameAmbig
				  %surnameProb %givennameProb
				  %logSurnameProb %logGivennameProb
				  %cnCoauthorCount $ambigSumTotal
				  $USE_CSLR_VERSION $CSLR_VENUE_UNSEEN_REDUCTION_FRAC $CSLR_COAUTHOR_UNSEEN_REDUCTION_FRAC
				  $CAT_PRIOR
				 );
#				  calcGramEvidence calcWordbagSimi titleSetTermDistro $stemmer %stemCache %invStemTable

$| = 1;

our $homedir;
our $logfilename;
our $LOG = \*STDERR;
our $tee = \*STDERR;
our $LEMMA_CACHE_SAVE_FILENAME;

sub hhmmss($;$)
{
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(shift);
    my $delim = shift || "";
    return sprintf "%02d$delim%02d$delim%02d", $hour, $min, $sec;
}

sub time2hms($)
{
	my $time = shift;
	my ( $sec, $min, $hour, $mday ) = gmtime($time);
	$hour += ($mday - 1) * 24;
	return "${hour}h${min}m${sec}s";
}

our $startTime = time;
our $timestamp = hhmmss($startTime);

our $endTime;

my $MEMSIZE_INTERVAL = 0;
my @progressVars;
our $progressDelim = "\t";
my @memsizeHashes;
my @memsizeArrays;
my $M = INT_MAX;

#our $stemmer = Lingua::Stem::Snowball->new( lang => 'en' );
#our %stemCache;
#our %invStemTable;

our $lemmaGID = 1;
our @lemmaCache;
our %lemmaLookup;
our %lemmaSuffLookup;
our %invLemmaTable;

our $recordStartLn;
our $gRecordCount = 0;

our %pinyinNames;
our %cantonpinyinNames;

our %gBigrams;
our %gUnigrams;

our %nameof = ( \%pinyinNames 			=> '%pinyinNames',
				 \%cantonpinyinNames 	=> '%cantonpinyinNames',
				 \%gBigrams 			=> '%gBigrams',
				 \%gUnigrams 			=> '%gUnigrams',
#				 \%stemCache 			=> '%stemCache',
				 \%lemmaLookup 			=> '%lemmaLookup',
			  );

our %typeof = ( \%gBigrams 		=> 'bigrams',
				\%gUnigrams 	=> 'unigrams',
			  );

our %sizeof = ();

our $puncs = "!\"\$%&\'()*,\-.\/:;<=>?\@\[\\\]^_`{|}~ \r\n\t";
our %puncs = map { $_ => 1 } (split //, $puncs);
our $puncs_nospace = "!\"\$%&\'()*,\-.\/:;<=>?\@\[\\\]^_`{|}~";

our $puncRE = qr/[$puncs]/;
our $puncNoSpaceRE = qr/[$puncs_nospace]/;

our %xmlSymMap = ('&amp;' => '&', '&quot;' => '"', '&apos;' => "'",
					'&lt;' => '<', '&gt;' => '>', '&nbsp;' => ' ',
					'&times;' => '*', '&reg;' => '', '&micro;' => 'mu',
					'&mdash;' => '-', '&lgr;' => 'lambda',
					'&sgr;' => 'sigma',
				);
				
our $yearRE = qr/\b(19[789][0-9]|200[0-9]|201[0-1])\b/;
our $pageRE = qr/\b((pp|pp\.|Pp|Pp\.|p |p\. )\s*([ivxIVX]+\s*\+\s*)?\d+(\s*\+\s*[ivxIVX]+\s*)?|([ivxIVX]+\s*\+\s*)?\d+(\s*\+\s*[ivxIVX]+\s*)?\s*(pp|Pp| p)|\d+\s*(pp|Pp| p|pages|Pages))[^\/\-:\w]/;

our @bindingWords = qw(hardback hardcover hardbound paperback softback softcover);
our $bindingRE = buildOrRE('\b', variousCaps(@bindingWords), '\b');

our $editedByRE = buildOrRE('\b', variousCaps("edited by"), '\b');
our $authorRE = '\s*(([A-Z]\.|[A-Z][a-z]+)(\s*|-)){1,3}[A-Z][a-z]+( Jr\.)?';
our $editorRE = qr/($authorRE, )*$authorRE(,? and $authorRE)?\s*\((Ed|ed|Editor|editor)(s?\.?)\s*\)/;
our $publishersRE;

my @reviewPat1 = ("a book review", "book review", "book reviews");
our $reviewRE1 = buildOrRE( '((?<=[^\w\s])|^)\s*', variousCaps(@reviewPat1), '((?=\s*\W)|$)' );
my @reviewPat2 = ("review of", "a review of", "review:", "erratum to",
					"some comments on", "comments on");
our $reviewRE2 = buildOrRE( '^', variousCaps(@reviewPat2), "(?=[$puncs])" );

our $BIG_AMBIG_EST_BOOST				= 1.5;
our $SMALL_AMBIG_EST_BOOST				= 2.5;

our %similarVenues;

our %chnNameAmbig;
our %surnameAmbig;
our %givennameAmbig;

our $namesakeTotalCount = 0;
our $ambigSumTotal = 0;

our %surnameProb;
our %givennameProb;

our %logSurnameProb;
our %logGivennameProb;

our $chnNameAmbigLoaded = 0;
our $coauthorStatLoaded = 0;

our %cnCoauthorCount;
our %name2coauthors;
#our (%author2id, @authors, $authorGID);

#our $pRecoverStem  = recovererFromInvTable(\%invStemTable);

# sub ref to recover the originals of a lemma
our $pRecoverLemma = recovererFromInvTable(\%invLemmaTable);

=pod
sub new
{
	my $invocant = shift;
	my $class = ref($invocant) || $invocant;

	$startTime = time;
	my $self = { @_ };
	bless($self, $class);
	return $self;
}
=cut

our @stopwords = qw(
a about above across after again against almost alone along also
although always am among an and another any anybody anyone anything
apart are around as  at away be because been before behind being below
besides between beyond both but by can cannot could  did do does doing done
down  during each either else enough etc  ever every everybody
everyone except far few for  from get gets got had  has have having
her here herself him himself his how however if in indeed instead into
is it its itself just kept  maybe might  more most mostly much must
myself  neither  no nobody none nor not nothing  of off often on
only onto or other others ought our ours out  own  please
pp quite rather really said seem  shall she should since so
some somebody somewhat still such than that the their theirs them themselves
then there therefore these they this thorough thoroughly those through thus to
together too toward towards until up upon was we well were what
whatever when whenever where whether which while who whom whose why will with
within would yet your yourself
re d ll m ve t s
);
# very we're, we'd, we'll, i'm, i've, couldn't, it's, self selves 

our @articles = qw( a an the );
our @academicStopwords = qw(via using based concerning);

=pod
my @removedStopwords = qw(adj all over  i p v young without under several plus
						  per outside nowhere next near mine many inward
						  hardly forth even downwards deep aside anywhere
						);
=cut

our %venueType = (article => 0, inproceedings => 1, book => 2, incollection => 3, phdthesis=> 4, mastersthesis => 5);

our %stopwords = map { $_ => 1 } (@stopwords, @academicStopwords);

our %stopwordGapWeight = %stopwords;
$stopwordGapWeight{'and'} = 0.2;
$stopwordGapWeight{@articles} = ( 0.1 ) x scalar @articles;

our @twochar_surname = qw(ouyang shangguan duanmu sima situ zhuge huangpu linghu murong);
our %twochar_surname = map { $_ => 1 } @twochar_surname;

struct( keyword => [ freq => '$', authorNum => '$', authorNumNonForay => '$',
						authorHitFreqDistribution => '%',
						authorPubTotalCount => '$', authorTopicPubEstCount => '$',
						authorPubAvgFraction => '$', authorTopicPubEstFraction => '$',
#						lessUseAuthorFraction => '$',
						#weight => '$', polar => '$', startYear => '$',
					 tf => '$', tfiaf => '$', iaf => '$',
					 #freq_rank => '@', af_rank => '@', tfiaf_rank => '@', iaf_rank => '@'
				   ] );

struct( keyword2 => [ freq => '$', tfiaf => '$' ] );

struct( namePart => [ freq => '$', prob => '$' ] );
struct( author => [ publist => '@' ] );

struct( namesake => [ name => '$', prob => '$', authorlist => '@',
						authorCount => '$', pubCount => '$' ] );

struct( publication => [ title => '$', year => '$', venue => '$', authors => '@', pubkey => '$',
							isNameReverse => '$', type => '$', authorID => '$' ] );
									# only one authorID here. means the author in question (being clustered)

# standardize some venue variants
our %venueMap = ( 'World Wide Web' => 'WWW', 
				  'Congress on Evolutionary Computation' => 'IEEE Congress on Evolutionary Computation',
				);

our ($MORPH_OUT, $MORPH_IN);
our $morphCallCount = 0;
our $morphPID = 0;

sub openLogfile(;$)
{
	my ($logfilenameStem) = @_;
	if(! $logfilenameStem){
		my $progname = $0;
		$progname =~ s/\.pl//i;
		$logfilenameStem = $progname;
	}
	$logfilename = "$logfilenameStem-$timestamp.log";

	print STDERR "Info will be logged into '$logfilename'.\n";

	# if $LOG has been some handle, the handle number will be reused
	# e.g., if $LOG==STDERR, then STDERR is reused as the file handle. 
	# so all printing to STDERR prints to the log file, which is usually not desirable
	# so we undef it first
	$LOG = undef;
	open_or_die($LOG, "> $logfilename");
	$LOG->autoflush(1);

	$tee = new IO::Tee(\*STDERR, $LOG);
}

sub setDebug
{
	$DEBUG = shift;
}

sub initialize(%)
{
	$homedir = dirname( File::Spec->rel2abs(__FILE__) );

	my %args = @_;

	$progressDelim ||= $args{progressDelim};

	if($args{progressVars}){
		@progressVars = @{ $args{progressVars} };
	}
	else{
		@progressVars = ();
	}

	if($args{tee}){
		$tee = $args{tee};
	}

	if($args{memsizeVars}){
		@memsizeHashes = @{ $args{memsizeVars}->[0] };
		@memsizeArrays = @{ $args{memsizeVars}->[1] };
	}
	else{
		@memsizeHashes = ();
		@memsizeArrays = ();
	}

	$MEMSIZE_INTERVAL = $args{memsizeInterval} || 0;

	$M = $args{maxRecords} || INT_MAX;

#	loadPublishers();

	if(! $args{noLoadPinyin}){
		loadPinyins();
	}

	if($args{loadChnNameAmbig}){
		loadChnNameAmbig( $args{loadChnNameAmbig} );
	}
	
	if($args{loadNameCoauthors}){
		loadNameCoauthors( $args{loadNameCoauthors} );
	}

	if(! $args{noLoadGram}){
		loadGramFiles();
	}

	if(! $args{noLoadLemmatizer}){
		# open2 is eerie in that when u provide a complete cmdline, it spawns a shell (cmd.exe)
		# first and return the shell's pid. so separate them to get the real pid
		$morphPID = open2( $MORPH_OUT, $MORPH_IN, (split /;/, MORPHA_CMDLINE));
		# stupid open2, why it changes STDERR's autoflush?
		STDERR->autoflush();

		if($args{lemmaCacheLoadFile}){
			loadCache($args{lemmaCacheLoadFile}, \%lemmaLookup,
						sub{
							my ($x, @y) = @_;
							my $lemmaID;
							# used to incrementally load a lemma-cache file
							# since $x is already cached, do not overwrite the cached 
							# value with the value in the file
							return 0 if exists $lemmaLookup{$x};

							if(@y > 1){
								$lemmaID = $lemmaSuffLookup{"$y[0],$y[1]"};
								if($lemmaID){
									$lemmaLookup{$x} = $lemmaID;
								}
								else{
									$lemmaCache[$lemmaGID] = [ @y ];
									$lemmaLookup{$x} = $lemmaGID;
									$lemmaSuffLookup{"$y[0],$y[1]"} = $lemmaGID;
									$lemmaGID++;
								}
							}
							# older lemma-cache file has no suffix field. this consideration could be removed
							else{
								lemmatize($x);
							}
							return 1;
						}
					 );
		}
		if($args{lemmaCacheSaveFile}){
			$LEMMA_CACHE_SAVE_FILENAME = getAvailName($args{lemmaCacheSaveFile});
			print STDERR "Lemma cache will be saved to '$LEMMA_CACHE_SAVE_FILENAME' at exit\n";
		}

		my $forget = lemmatize0('forgotten');
		if($forget ne 'forget'){
			die "Lemmatizer 'morpha' failed to start up. " .
				"Please check the path to make sure it lies there\n";
		}
		print STDERR "Lemmatizer 'morpha' is up and running happily as process $morphPID\n";
	}

	$QUIET_EXIT = 0;
	
	print $tee "Processing starts at ", hhmmss($startTime, ':'), "\n";
#	$SIG{INT} = \&abort;

}

sub abort
{
	$SIG{INT} = sub{ exit };
	progress2();
	print $tee "\n\nInterrupted by Ctrl-C";

	my $summary = $main::{summary};
	if($summary){
		print STDERR "Do you want to see the summary? (y/N) ";
		my $input = <STDIN>;
		if($input =~ /^y$/i){
			&$summary();
		}
	}

	exit;
}

sub progress2
{
	my $s;
	print STDERR "\r", join("$progressDelim    \b\b",
						map { c1000( $$_ ) } @progressVars
					 ), "\t\r";
}

sub makeProgresser
{
	my %args = @_;

	my @varrefs = @{$args{vars}};
	my $indicator = $varrefs[0];

	my $limit = $args{limit} || 0;
	my $stepsize = $args{step} || 1000;

	if($limit){
		# optimization for one-var case
		if(@varrefs == 1){
			return
			sub
			{
				# &$progresser(1); print with newline, finalize the progresser()
				if($_[0]){
					print STDERR "\r$$indicator    \n";
					return;
				}

				if($$indicator >= $limit){
					if($$indicator % $stepsize == 0){
						print STDERR "\r$$indicator    \n";
					}
					print STDERR "Max units $limit reached, stop\n";
					exit;
				}
				elsif($$indicator % $stepsize == 0){
					print STDERR "\r$$indicator    \r";
				}
			};
		}
		else{
			return
			sub
			{
				# &$progresser(1); print with newline, finalize the progresser()
				if($_[0]){
					print STDERR "\r", join(" ", map { $$_ } @varrefs), "    \n";
					return;
				}

				if($$indicator >= $limit){
					if($$indicator % $stepsize == 0){
						print STDERR "\r", join(" ", map { $$_ } @varrefs), "    \n";
					}
					print STDERR "Max units $limit reached, stop\n";
					exit;
				}
				elsif($$indicator % $stepsize == 0){
					print STDERR "\r", join(" ", map { $$_ } @varrefs), "    \r";
				}
			};
		}
	}
	else{
		if(@varrefs == 1){
			return
			sub
			{
				if($_[0]){
					print STDERR "\r$$indicator    \n";
					return;
				}
				if($$indicator % $stepsize == 0){
					print STDERR "\r$$indicator    \r";
				}
			};
		}
		else{
			return
			sub
			{
				if($_[0]){
					print STDERR "\r", join(" ", map { $$_ } @varrefs), "    \n";
					return;
				}
				if($$indicator % $stepsize == 0){
					print STDERR "\r", join(" ", map { $$_ } @varrefs), "    \r";
				}
			};
		}
	}
}

sub progress
{
	if($_[0] % 1000 == 0){
		print STDERR "\r@_    \r";
	}
}

sub progress_end
{
	print STDERR "\r@_    \n";
}

# returned author names are always lowercased
sub parseDBLPBlock($$$)
{
	my ($title, $authorLine, $yearVenueLine) = @_;

	my @authorNames;
	my $year;
	my $venueType;
	my $confName;
	my $thisPublication;
	my $venueTypeName;
	my $venueName;
	my $pubkey;
	my $authorID;
	
	@authorNames = split /,\s*/, $authorLine;
	my $isNameReverse = testChnNameReverse(@authorNames);

	for(@authorNames){
		$_ = lc;
		s/ \d{4}$//;

		if( $isNameReverse >= 0 && isChineseName($_)
				&& !isCantoneseName($_, $isNameReverse) ){
			$_ = standardizeChineseName($_, $isNameReverse);
		}
	}

	# since "." is followed by " key:", no need to worry about a journal name containing "."
	($yearVenueLine, $pubkey) = split /\. key: /, $yearVenueLine;

	($year, $venueTypeName) = split /\.(?: |$)/, $yearVenueLine, 2;

	$year =~ s/\(([^()]+)\)\s*//;
	$authorID = $1;
	
	$venueTypeName ||= "";

	($venueType, $venueName) = split /: /, $venueTypeName;

	# be compatible with two formats: either 'inproceedings: conf-name' or 'conf-name'
	if(! $venueName){
		$venueName = $venueType || "";
		$venueType = undef;
	}
	else{
		if(exists $venueType{$venueType}){
			$venueType = $venueType{$venueType};
		}
		else{
			$venueType = undef;
		}
	}

	# if venue has multiple sections, keep the first one
	# if venue is like "ACCV (3)", remove the parentheses.
	# An author may publish on different tracks of the same conf
	if($venueName){
		$venueName = (split /,/, $venueName )[0];
		$venueName =~ s/\([^()]+\)//;
	}
	trim($venueName);

	if($venueName && $venueMap{$venueName}){
		$venueName = $venueMap{$venueName};
	}

	$thisPublication = publication->new( title => $title, year => $year, pubkey => $pubkey,
							venue => $venueName, authors => [ @authorNames ], authorID => $authorID,
							type => $venueType, isNameReverse => $isNameReverse );
	return $thisPublication;
}

sub parseCleanDBLP(*)
{
	my $title;
	my $authorLine;
	my $yearVenueLine;
	my $thisPublication;

	my $DB = qualify_to_ref(shift, caller);

	if(!eof($DB)){
		$recordStartLn = $. + 1;

		$title = <$DB>;
		$authorLine = <$DB>;
		$yearVenueLine = <$DB>;
		<$DB>;

		trim($title, $authorLine, $yearVenueLine);

		$thisPublication = parseDBLPBlock($title, $authorLine, $yearVenueLine);

		$gRecordCount++;
		if($gRecordCount % 10000 == 0){
			progress2();
		}

=pod
		if($MEMSIZE_INTERVAL > 0 && $gRecordCount % $MEMSIZE_INTERVAL == 0){
			my $ret = memsize();
			if($ret == 1){
				$MEMSIZE_INTERVAL = 0;
			}
		}
=cut

		if($gRecordCount >= $M){
			my $summary = $main::{summary};
			if($summary){
				&$summary();
			}
			print $tee "\nLast line processed is ", $recordStartLn + 3, "\n";
			die "Exit early.\n";
		}

		return $thisPublication;
	}
	else{
		return undef;
	}
}

sub dumpPub($$;$)
{
	my ($FH, $pub, $gIdentities) = @_;

	print $FH $pub->title, "\n";
	print $FH join( ", ", @{ $pub->authors } ), "\n";
	if($gIdentities && $pub->authorID){
		print $FH "(", $gIdentities->[ $pub->authorID ], ") ";
	}
	if($pub->pubkey){
		print $FH join( ". ", $pub->year, $pub->venue, "key: " . $pub->pubkey ), "\n";
	}
	else{
		print $FH join( ". ", $pub->year, $pub->venue ), "\n";
	}
}

sub trim(@)
{
	for(@_){
		next if !$_;
		$_ =~ s/^\s+|\s+$//g;
	}
}

sub trimLeading(@)
{
	for(@_){
		$_ =~ s/^\s+//g;
	}
}

sub trimTrailing(@)
{
	for(@_){
		$_ =~ s/\s+$//g;
	}
}

sub trimPunc(@)
{
	my ($start, $end);
	for(@_){
		next if !$_;

		$start = 0;
		$end = length($_) - 1;
		while($end >= $start && $puncs{substr($_, $end, 1)}){
			$end--;
		}
		while($end >= $start && $puncs{substr($_, $start, 1)}){
			$start++;
		}
		$_ = substr($_, $start, $end - $start + 1);
	}
}

sub restoreXmlEntity
{
	my @strings = @_;
	
	for(@strings){
		$_ =~ s/(&\w+;)/ if(exists $xmlSymMap{$1}){ $xmlSymMap{$1}; } else{ $1 } /ge; 
	}
	
	return arrayOrFirst(wantarray, \@strings);
}

sub buildOrRE
{
	my $leftbound = shift;
	my $rightbound = pop;

	return "$leftbound(" . join("|", @_) . ")$rightbound";
}

sub decap(@)
{
	my @results;

	for(@_){
		my $w = $_;

		if($w !~ /[a-z]/ && $w =~ /[A-Z]{2}/){
			push @results, $w;
		}
		else{
			$w =~ s/\b([A-Z])(?=[^A-Z]|$)/\L$1/g;
			push @results, $w;
		}
	}
	return arrayOrFirst(wantarray, \@results);
}

sub cap
{
	my @results = map { my $w = $_; $w =~ s/\b(\w)/\U$1/g; $w } @_;
	return arrayOrFirst(wantarray, \@results);
}

# the combination number of "N chooses 2"
sub NChoose2
{
	my $N = shift;
	return $N * ($N - 1) / 2;
}

# calc the F1 from precison & recall
sub f1($$)
{
	my ($precision, $recall) = @_;
	return 2 * $precision * $recall / ( $precision + $recall );
}

sub variousCaps
{
	my @results;
	my $firstcap;
	my $allwordscap;
	my $allcharscap;
	my $nocap;
	for(@_){
		my $w = decap($_);
		$nocap = $w;
		$firstcap = $w;
		$firstcap =~ s/\b(\w)/\U$1/;
		$allwordscap = cap($w);
		$allcharscap = uc($w);
		push @results, ($nocap, $firstcap, $allwordscap, $allcharscap);
	}
	return @results;
}

sub dedup(@)
{
	my @t = ();
	my %set;

	for(@_){
		if(!exists $set{$_}){
			push @t, $_;
			$set{$_} = 1;
		}
	}
	return @t;
}

my @isCap = (0) x 256;
for my $c('A' .. 'Z'){
	$isCap[ ord($c) ] = 1;
}

sub capcount
{
	my $i;
	my @chars = split //, $_[0];

	my $capcount = 0;

	for($i = 0; $i < length($_[0]); $i++){
		if($isCap[ ord( substr($_[0], $i, 1) ) ]){
			$capcount++;
		}
	}
	return $capcount;
}

sub wc(@)
{
	my $wc = 0;
	for(@_){
		while(/\b/g){
			$wc++;
		}
	}
	return $wc / 2;
}

sub wc_nostopword(@)
{
	my $wc = 0;
	for(@_){
		while(/(\w+)/g){
			if(!exists $stopwords{lc($1)}){
				$wc++;
			}
		}
	}
	return $wc / 2;
}

sub c1000(@)
# add a comma every 3 digits
{
	my @vs = @_;
	for (@vs){
		1 while
		s/(\d)(\d{3})($|,)/$1,$2/;
	}
	return arrayOrFirst(wantarray, \@vs);
}

sub roundAtLeast1($)
{
	if($_[0] <= 0){
		return 0;
	}
	if($_[0] < 1){
		return 1;
	}
	return int($_[0] + 0.5);
}

sub atLeast1($$)
{
	my ($n, $doRoundUp) = @_;


	if($doRoundUp){
		if( $n == int($n) ){
			return $n;
		}
		return int($n) + 1;
	}

	if($n < 1){
		return 1;
	}
	return $_[0];
}

# truncate a floating point number to the $prec digits after the decimal point
sub trunc
{
	my $prec = shift;
	my @results;

	for(@_){
		push @results, 0 + sprintf("%.${prec}f", $_);
	}
	return arrayOrFirst(wantarray, \@results);
}

sub definedOr0($;$)
{
	if(defined($_[0])){
		if($_[1]){
			return trunc($_[1], $_[0]);
		}
		else{
			return $_[0];
		}
	}
	else{
		return 0;
	}
}

sub isBetween($$$)
{
	my ($num, $lb, $ub) = @_;
	if( !defined($num) ){
		return 0;
	}
	if($ub < $lb){
		($lb, $ub) = ($ub, $lb);
	}
	return $num <= $ub && $num >= $lb;
}

# if $wantarray, returns @$array
# else $array->[0]
sub arrayOrFirst
{
	my ($wantarray, $array) = @_;
	if($wantarray){
		return @$array;
	}
	return $array->[0];
}

sub indexOfMax
{
	my $arrayRef = shift;
	
	my ($indexMax, $max) = ( -1 );
	
	my $i;
	
	for($i = 0; $i < @$arrayRef; $i++){
		next if ! $arrayRef->[$i];
		
		if( !defined($max) || $max < $arrayRef->[$i] ){
			$max = $arrayRef->[$i];
			$indexMax = $i;
		}
	}
	
	return $indexMax;
}

# return an array of array-refs
sub copyRefArray($)
{
	return map { [ @$_ ] } @{$_[0]};
}

sub quoteArray
{
	return "'" . join("','", @_) . "'";
}

sub round
{
	return int($_[0] + 0.5);
}

sub dieIfNotInteger($;$)
{
	my $n = shift;
	my $info = shift;

	# for very big numbers (converted from floating points), the error could be large
	# like 0.02
	if( abs( round($n) - $n ) > 0.1 ){
		print $tee (caller(1))[3], $info ? " ($info)" : "", ": '$n' is not an integer\n";
		die "\n";
	}
}

sub statsByValue($$$)
{
	my ($stats, $N, $headerMsg) = @_;

	my @valueXFreq;

	print $tee $headerMsg, ":\n";

	my $i;
	for($i = 0; $i < $N; $i++){
		my $x = $stats->{$i} || 0;
		$valueXFreq[ $x ]++;
	}

	for($i = 0; $i < @valueXFreq; $i++){
		next if !$valueXFreq[$i];

		print $tee "$i: $valueXFreq[$i]\n";
	}
}

sub combineWW($$)
{
	return int( $_[0] << 16 | $_[1] );
}

sub WWSplit($)
{
	return ( int( $_[0] >> 16 ), int( $_[0] & 0xffff) );
}

sub lowerword($)
{
	return $_[0] & 0xffff;
}

sub higherword($)
{
	return $_[0] >> 16;
}

# return the ratio of the smaller number / the bigger number, of two numbers
sub ratio($$)
{
	# reject negatives
	if($_[0] <= 0 || $_[1] <= 0){
		return 0;
	}
	my ($bigger, $smaller);
	$bigger = max(@_);
	$smaller = min(@_);
	return $smaller/$bigger;
}

sub isVeryClose($$$)
{
	return abs($_[0] - $_[1]) <= $_[2];
}

# $weight is the weight of $v1. $v2 has weight of (1 - $weight)
sub weightedAverage($$$)
{
	my ($weight, $v1, $v2) = @_;
	if($weight > 1 || $weight < 0){
		die "Illegal weight: $weight\n";
	}
	
	return $v1 * $weight + $v2 * ( 1 - $weight );
}

# return a sub, which is a function f = $theta[0] + $theta[1] * $_[0] + ... + $theta[n] * $_[n - 1]
sub linearFunction
{
	my @thetas = @_;
	if( ref($thetas[0]) eq "ARRAY" ){
		my @argnames = @{ shift @thetas };
		
		return sub{
			my $xhash = shift @_;
			if( ref($xhash) ne "HASH" ){
				die "Hash ref is expected as the only argument, but found ", ref($xhash), "\n";
			}
			my $y = 0;
			my $i;
			for($i = 0; $i < @argnames; $i++){
				if(! exists $xhash->{ $argnames[$i] }){
					die "Input hash has no key '$argnames[$i]'\n";
				}
				$y += $thetas[$i] * $xhash->{ $argnames[$i] };
			}
			return $y;
		};
	}
	
	return sub{
		my @xs = @_;
		if(@xs +1 != @thetas){
			die "Incorrect argument number: ", scalar @xs, " provided (should be ", 
					scalar @thetas - 1, ")\n";
		}
		my $y = shift @thetas;
		my $i;
		for($i = 0; $i < @thetas; $i++){
			$y += $thetas[$i] * $xs[$i];
		}
		return $y;
	};
}

# if $key exists in %$bag, return its ID ($bag->{$key})
# otherwise add $key to %$bag, push $key to @$list, and increase $newID by 1.
# the id of $key is the old value of $newID.
# so if at first $newID == 0, then the first $key has id 0
sub key2id($$$$)
{
	my ($key, $bag, $list, $newID) = @_;

	if(! $key){
		return -1;
	}

	my $id = $bag->{$key};

	if(!defined($id)){
		$bag->{$key} = $newID;
		$id = $newID;
		# update the passed-in variable, instead of the passed-in value
		$_[3]++;
		push @$list, $key;
	}

	return $id;
}

# nums are in ascending order
sub bitmap2nums($$)
{
	my $maxbits = shift;
	my $d = shift;

	my $mask = 1;

	my $i;

	my @nums;

	for $i(0 .. $maxbits - 1){
		if($mask & $d){
			push @nums, $i;
		}
		$mask <<= 1;
	}

	return @nums;
}

sub bitmap2desc($$$)
{
	my ($bitmap, $enumSymNum, $enum2name) = @_;
	my $i;
	my @names;

	my $b;

	for($i = 0, $b = 1; $i < $enumSymNum; $i++){
		if($b & $bitmap){
			push @names, $enum2name->{$b};
		}
		$b <<= 1;
	}

	return join("|", @names);
}

=pod

sub memsize
{
	no strict "refs";

	#my @memsizeHashes = qw(gNameParts gNames gBigrams gUnigrams stemCache invStemTable);
	#my @memsizeArrays = qw(gAuthors gPublications);

	my $v;

	my ($startTime0, $startTime);

	my $allTotalSize = 0;
	my $totalsize;

	print $tee "\nSizes of different vars:\n";
	$startTime0 = time;

	for $v(@memsizeHashes){
		$startTime = time;
		$totalsize = total_size(\%$v);
		$allTotalSize += $totalsize;
		print $tee "\%$v:\t", size1000(\%$v), "\t", c1000($totalsize), "\t(",
				time - $startTime, " secs)\n";
	}
	for $v(@memsizeArrays){
		$startTime = time;
		$totalsize = total_size(\@$v);
		$allTotalSize += $totalsize;
		print $tee "\@$v:\t", size1000(\@$v), "\t", c1000($totalsize), "\t(",
				time - $startTime, " secs)\n";
	}
	print $tee "Sum total: ", c1000($allTotalSize);

	my $disable_memsize = 0;

	if($allTotalSize >= MAX_MEMSIZE_TO_CALC){
		print $tee ", bigger than ", MAX_MEMSIZE_TO_CALC / (1024*1024),
					"M, memory footprinting would be DISABLED\n";
		$disable_memsize = 1;
#		$MEMSIZE_INTERVAL = 0;
	}
	else{
		print $tee "\n";
	}
	print $tee "memsize() used ", time - $startTime0, " secs\n\n";

	return $disable_memsize;
}

=cut

# provide $origname as the template, and return a new name if $origname is used by a file
sub getAvailName($)
{
	my $origname = shift;
	my $append;
	my ($name, $suffix);

	if(! -e $origname){
		return $origname;
	}

	if($origname =~ /^(.+)(\.[^.]+)$/){
		$name = $1;
		$suffix = $2;
	}
	else{
		$name = $origname;
		$suffix = "";
	}

	$append = -1;
	while(-e "$name$append$suffix"){
		$append--;
	}
	return "$name$append$suffix";
}

sub open_or_die(*$)
{
	my $mode;
	if($_[1] =~ />/){
		$mode = "write";
	}
	else{
		$mode = "read";
	}
	my $filepath = $_[1];
	$filepath =~ s/^\s*[<>+]*\s*//;

	if($_[0]){
		my $fh = qualify_to_ref($_[0], caller);
		open($fh, $_[1]) || die "Cannot open '$filepath' to $mode: $!\n";
	}
	else{
		open($_[0], $_[1]) || die "Cannot open '$filepath' to $mode: $!\n";
	}
}

sub open_or_warn(*$)
{
	my $mode;
	if($_[1] =~ />/){
		$mode = "write";
	}
	else{
		$mode = "read";
	}
	my $filepath = $_[1];
	$filepath =~ s/^\s*[<>+]*\s*//;

	my $ret;

	if($_[0]){
		my $fh = qualify_to_ref($_[0], caller);
		$ret = open($fh, $_[1]);
	}
	else{
		$ret = open($_[0], $_[1]);
	}
	if(! $ret){
		 print $tee "Cannot open '$filepath' to $mode: $!\n";
	}
	return $ret;
}

sub loadPinyin(\%$)
{
	my $pinyinNames = shift;
	my $pinyinfile = shift;

	# use 'my' var to avoid future parallel problems, though not a concern now
	my $PINYIN;
	open_or_die($PINYIN, "< $pinyinfile");

	my @pinyins = <$PINYIN>;
	@pinyins = grep { !/^#/ } @pinyins;

	for(@pinyins){
		trim($_);
	}
	my ($i, $j);

	for $i(@pinyins){
		for $j(@pinyins){
			$pinyinNames->{$i.$j} = 2;
		}
	}
	for $i(@pinyins){
		$pinyinNames->{$i} = 1;
		# if a string can match both 2-syllable and 1-syllable, then treat it as
		# 1-syllable
	}

	print $tee (scalar @pinyins), " pinyin loaded into '$nameof{$pinyinNames}' from '$pinyinfile'\n";
}

sub loadGramFile($$$;$)
{
	my ($grambag, $filename, $leastFreq, $isSimpleMode) = @_;

	print $tee "Loading terms from '$filename'...\n";

	my $FH;
	if(! open_or_warn($FH, "< $filename") ){
		return 0;
	}

	# throw away header
	<$FH>;

	my $line = <$FH>;
	trim($line);

	if($line !~ /^ALL_TITLES_AUTHORS,(\d+),(\d+),(\d+)$/){
		print $tee "Unknown format of the second line:\n$line\n";
		return 0;
	}

#	my $authorCount = $1;
#	my $pubCount = $2;

	my ($w, $freq, $authorNum, $authorPubTotalCount, $authorTopicPubEstCount,
			$authorHitFraction, $authorTopicPubEstFraction, $tf, $tfiaf, $iaf);
	my $lastw = "NOTHING LOADED";
	my $lastfreq = 0;

	my $count = 0;

	my $progresser = makeProgresser(vars => [ \$count ]);

	while($line = <$FH>){
		($w, $freq, $authorNum, $authorPubTotalCount, $authorTopicPubEstCount,
			$authorHitFraction, $authorTopicPubEstFraction, $tf, $tfiaf, $iaf) =
						split /,/, $line;

		if($freq < $leastFreq){
			print $tee "Stop at line $.. Last loaded word: $lastw $lastfreq\n";
			last;
		}

		next if $tfiaf == 0 || $stopwords{$w};

		if($isSimpleMode){
			$grambag->{$w} = 1;
		}
		else{
			$grambag->{$w} = keyword2->new(freq => $freq, authorNum => $authorNum, tfiaf => $tfiaf);
		}

		$count++;
		&$progresser();

		$lastw = $w;
		$lastfreq = $freq;
	}

	print STDERR "$count\n";

	print $tee "$count terms loaded into '$nameof{$grambag}' from '$filename'\n";

	return $count;
}

sub loadPinyins
{
	loadPinyin(%pinyinNames, "$homedir/pinyin.txt");
	loadPinyin(%cantonpinyinNames, "$homedir/cantonpinyin.txt");
}

sub loadGramFiles
{
	loadGramFile(\%gUnigrams, "$homedir/unigram.csv", 2);
# tentatively use unigrams only, for the computation of IC of a concept match
#	loadGramFile(%gBigrams, "$homedir\\bigram[a-m].csv");
#	loadGramFile(%gBigrams, "$homedir\\bigram[n-z].csv");
}

=pod
sub calcGramProb($)
{
	my $N = $_[0];
	my $w;
	for $w(keys %gUnigrams){
		$gUnigrams{$w}->prob( $gUnigrams{$w}->freq / $N );
	}
	for $w(keys %gBigrams){
		$gBigrams{$w}->prob( $gBigrams{$w}->freq / $N );
	}
}
=cut

sub loadPublishers
{
	my $PUBS;
	open_or_die($PUBS, "< $homedir\\publishers.txt");

	my $suffixPat = qr/(Press|press|House|Publishing|Publisher|Publishers)$/;

	my @publishers = <$PUBS>;
	my $p2;

	my @publishers2;

	my %publishers = map { trim($_); $_ => 1 } @publishers;

	for(@publishers){
		$p2 = $_;
		$p2 =~ s/$suffixPat//;
		trimPunc($p2);
		if(wc_nostopword($p2) >= 2 && !exists $publishers{$p2}){
			push @publishers2, $p2;
			$publishers{$p2} = 1;
		}
	}

	@publishers = sort { $b cmp $a } keys %publishers;
	$publishersRE = join( "|", @publishers );
	$publishersRE =~ s/\./\\./g;

#	print STDERR $publishersRE, "\n";
	print $tee scalar @publishers, " publishers loaded from 'publishers.txt'\n";
}

sub chop_or_del($$;$)
{
	my $noFollowingPat = $_[2] || "";
	my ($patBegin, $patEnd);

	while($_[0] =~ /$_[1]/){
		$patBegin = $-[0];
		$patEnd = $+[0];

		if($patBegin == 0){
			$_[0] =~ s/$_[1]//;
		}
		else{
			if(!$noFollowingPat || substr($_[0], $patEnd) !~ /^$noFollowingPat/){
				substr($_[0], $patBegin) = '';
			}
			else{
				trimPunc($_[0]);
				return;
			}
		}
		trimPunc($_[0]);
	}
}

sub removePublisher
{
	my $title = shift;
	if($title =~ /(?:[,.;:()]|published by|Published by)\s*($publishersRE)[^\'a-zA-Z0-9)]/){
		$title = substr($title, 0, $-[0]);
	}

	my $oldlen;
	do{
		$oldlen = length($title);
		trimPunc($title);
		$title =~ s/$yearRE$//;
	}while(length($title) < $oldlen);

	if($title =~ /$pageRE/){
		$title = substr($title, 0, $-[0]);
		trimPunc($title);
	}

	chop_or_del($title, $reviewRE2);
	chop_or_del($title, $reviewRE1, ':');
	chop_or_del($title, $bindingRE);
	chop_or_del($title, $editorRE);
	chop_or_del($title, $editedByRE);

	return $title;
}

sub topN($$$$$$)
{
	my ($N, $hash, $sortmsg, $topmsg, $accessor, $transformer) = @_;

	local $| = 1;

	print $tee $sortmsg, "... ";

	if($N == 0){
		print $tee "N == 0, ignore\n\n";
		return;
	}
	if(keys %{$hash} == 0){
		print $tee "Empty hash, ignore\n\n";
		return;
	}

	if($N > keys %{$hash}){
		$N = keys %{$hash};
	}
	$transformer ||= sub { $_[0] };

	my $startTime = time;

	my @list = sort { &$accessor($b) <=> &$accessor($a)
									  ||
								  $a cmp $b
					} keys %{$hash};

	print $tee "Done. (", time() - $startTime, "secs)\n\n";

	my $i = 0;
	my $item;


	print $tee c1000($N), " $topmsg:\n";

	my $tee2 = $tee;
	for($i = 0; $i < $N && $i < @list; $i++){
		if($i == MAX_CONSOLE_LIST_SIZE){
			print STDERR "...... (Truncated at ", MAX_CONSOLE_LIST_SIZE, " lines)\n";

			# now only output to the file. so that the log file gets the full list
			# and in the console only a small part is shown. avoid cluttering the console
			$tee2 = (grep { $_ != \*STDERR } $tee->handles)[0];
		}
		$item = $list[$i];
		print $tee2 "", &$transformer($item), "\t\t", &$accessor($item), "\n";
	}
	print $tee "\n";

	return \@list;
}

sub topBottomN($$$$$$$)
{
	my ($N, $hash, $sortmsg, $topmsg, $botmsg, $accessor, $transformer) = @_;

	local $| = 1;

	print $tee $sortmsg, "... ";

	if($N == 0){
		print $tee "N == 0, ignore\n\n";
		return;
	}
	if(keys %{$hash} == 0){
		print $tee "Empty hash, ignore\n\n";
		return;
	}

	if($N > keys %{$hash}){
		$N = keys %{$hash};
	}
	$transformer ||= sub { $_[0] };

	my $startTime = time;

	my @list = sort { &$accessor($b) <=> &$accessor($a)
									  ||
								  $a cmp $b
					} keys %{$hash};

	print $tee "Done. (", time() - $startTime, "secs)\n\n";

	my $i = 0;
	my $item;

	print $tee c1000($N), " $topmsg:\n";

	my $tee2 = $tee;
	for($i = 0; $i < $N && $i < @list; $i++){
		$item = $list[$i];
		if($i == MAX_CONSOLE_LIST_SIZE){
			print STDERR "...... (Truncated at ", MAX_CONSOLE_LIST_SIZE, " lines)\n";
			$tee2 = (grep { $_ != \*STDERR } $tee->handles)[0];
		}
		print $tee2 "", &$transformer($item), "\t\t", &$accessor($item), "\n";
	}
	print $tee "\n";

	if($N == INT_MAX){
		return;		# all are output, no need of the reverse
	}

	print $tee c1000($N), " $botmsg:\n";

	$tee2 = $tee;

	my $j = 0;

	# skip 0's when printing the smallest N elements
	while(&$accessor($list[$j - 1]) <= 0 && -$j + 2 <= @list){
										 # max(-$j)=@list-1. if -$j+2=@list, after $j--, -$j=@list-1
		$j--;
	}

	for($i = -1; $i >= -$N && -$i - $j <= @list; $i--){
		$item = $list[$i + $j];
		if(-$i - 1 == MAX_CONSOLE_LIST_SIZE){
			print "...... (Truncated at ", MAX_CONSOLE_LIST_SIZE, " lines)\n";
			$tee2 = (grep { $_ != \*STDERR } $tee->handles)[0];
		}
		print $tee2 "", &$transformer($item), "\t\t", &$accessor($item), "\n";
	}
	print $tee "\n";

	return \@list;
}

sub isChineseName
{
	my $charcount = 0;

	my $name = lc(shift);

	my @nameParts = split / /, $name;
	my $namePart;

	return 0 if @nameParts != 2;

	for(@nameParts){
		$namePart = $_;
		$namePart =~ s/-//;
		if(!exists $pinyinNames{$namePart}){
			return 0;
		}
		# treat a two-char surname as one char
		if(exists $twochar_surname{$namePart}){
			$charcount++;
		}
		elsif(exists $pinyinNames{$namePart}){
			$charcount += $pinyinNames{$namePart};
		}
	}

	if($charcount >= 2 && $charcount <= 3){
		return $charcount;
	}
	return 0;
}

sub isCantoneseName
{
	my $charcount = 0;

	my $name = lc(shift);
	$name =~ s/-//;

	my $isReverse = shift;

	die "\$isReverse < 0 in isCantoneseName()\n" if $isReverse < 0;

	my @nameParts = split / /, $name;
	my $namePart;

	return 0 if @nameParts != 2;

	if($isReverse){
		@nameParts = reverse @nameParts;
	}

	my ($firstname, $secondname) = @nameParts;

	if( isBetween( $pinyinNames{$firstname},  1, 2 ) &&
			isBetween( $pinyinNames{$secondname}, 1, 1 ) ){
		return 0;
	}

	if( ( isBetween( $cantonpinyinNames{$firstname},  1, 2 )
			||
		  isBetween( $pinyinNames{$firstname},  1, 2 )
		)   &&
		  isBetween( $cantonpinyinNames{$secondname}, 1, 1 ) ){
		return 1;
	}

	return 0;
}

sub testChnNameReverse
{
	my $sureReversed = 0;
	my $sureNotReversed = 0;
	my $name;
	my ($firstname, $secondname);
	my @nameParts;
	my $chnNameCount = 0;
	my $isCantonese;

	# reverse: family-name given-name
	my $reverseLogLikelihood = 0;
	# forward: given-name  family-name
	my $forwardLogLikelihood = 0;
	my $asymmetric;

	for $name(@_){
		$name =~ s/ \d{4}$//;
		if(!isChineseName($name)){
			next;
		}

		$chnNameCount++;
		
		@nameParts = split / /, lc($name);

		($firstname, $secondname) = @nameParts;
		if($firstname =~ /-/ && $secondname !~ /-/){
			$sureNotReversed = 1;
		}
		if($secondname =~ /-/ && $firstname !~ /-/){
			$sureReversed = 1;
		}
		$firstname =~ s/-//;
		$secondname =~ s/-//;
		if($pinyinNames{$secondname} == 2 && !exists $twochar_surname{$secondname}){
			if(!exists $cantonpinyinNames{$secondname} || $cantonpinyinNames{$secondname} != 1){
				$sureReversed = 1;
			}
		}
		if($pinyinNames{$firstname} == 2 && !exists $twochar_surname{$firstname}){
			if(!exists $cantonpinyinNames{$firstname} || $cantonpinyinNames{$firstname} != 1){
				$sureNotReversed = 1;
			}
		}

		if( $chnNameAmbigLoaded && $pinyinNames{$firstname} == 1 && $pinyinNames{$secondname} == 1 ){
			$asymmetric = 0;

			if( !exists $logSurnameProb{$secondname} || !exists $logGivennameProb{$firstname} ){
				$sureReversed = 1;
				$asymmetric = 1;
			}
			if( !exists $logSurnameProb{$firstname} || !exists $logGivennameProb{$secondname} ){
				$sureNotReversed = 1;
				$asymmetric = 1;
			}

			if(! $asymmetric){
				$forwardLogLikelihood += $logSurnameProb{$secondname} + $logGivennameProb{$firstname};
				$reverseLogLikelihood += $logSurnameProb{$firstname} + $logGivennameProb{$secondname};
			}
		}
	}

	# all non-Chinese names. no problem of reverse
	if($chnNameCount == 0){
		return 0;
	}

	# four pinyin characters (not Chinese), or mixed formats (surname givenname, givenname surname)
	if($sureReversed && $sureNotReversed){
		if($DEBUG & DBG_WEIRD_CHNNAME){
			progress2();
			print $LOG "Suspicious: ", join(", ", @_), "\n";
		}
		return -1;
	}

	if($sureReversed){
		return 1;
	}
	if($sureNotReversed){
		return 0;
	}
	
	# here, $sureReversed == 0 && $sureNotReversed == 0
	# all names are two-char. Decide by the forward & reverse log-likelihoods
	if( $forwardLogLikelihood >= $reverseLogLikelihood ){
		if($chnNameAmbigLoaded && ($DEBUG & DBG_WEIRD_CHNNAME) ){
			print $LOG join(", ", @_), 
					": forward $forwardLogLikelihood >= reverse $reverseLogLikelihood, choose forward.\n";
		}
		return 0;
	}
	
	if( $chnNameAmbigLoaded && ($DEBUG & DBG_WEIRD_CHNNAME) ){
			print $LOG join(", ", @_), 
					": forward $forwardLogLikelihood < reverse $reverseLogLikelihood, choose reverse.\n";
	}
	return 1;
}

# '-' between the two chars of the given name is removed here
sub standardizeChineseName
{
	my $name = lc(shift);
	my $isNameReverse = shift;

	# if $isNameReverse == -1, you shouldn't call standardizeChineseName()
	die "\$isNameReverse = -1, unable to decide whether to reverse name '$name'"
			if $isNameReverse < 0;

	$name =~ s/ \d{4}$//;
	$name =~ s/-//g;

	my @nameParts = split / /, $name;

	die "name '$name' has 1 or > 2 parts" if @nameParts != 2;

	if($isNameReverse > 0){
		return $nameParts[1] . " " . $nameParts[0];
	}
	else{
		return $name;
	}
}

sub loadChnNameAmbig($)
{
	my ($ambigFile) = @_;

	my $AMBIG;

	print $tee "Loading Chinese name ambiguity file '$ambigFile'...\n";
	open_or_die($AMBIG, "< $ambigFile");

	%chnNameAmbig = ();
	%surnameAmbig = ();
	%givennameAmbig = ();

	%surnameProb = ();
	%givennameProb = ();

	%logSurnameProb = ();
	%logGivennameProb = ();

	<$AMBIG>;

	my $line;

	my ($name, $occurs, $ambig_prob, $ambig, $prob);

	my $count = 0;

	my $stage = 0;
	my @stageNames = ("names", "surnames", "given names");

	my $progresser = makeProgresser(vars => [ \$count, \$stage ]);

	while($line = <$AMBIG>){
		# only the final converged ambiguity is used
		($name, $occurs, $ambig_prob) = split /,/, $line;

		if($name =~ /^SURNAMES|GIVEN_NAMES$/){
			print $tee "$count Chinese $stageNames[$stage] loaded\n";
			$count = 0;
			$stage++;
			next;
		}

		# the summary line
		if($name =~ /\*/){
			($_, $namesakeTotalCount, $ambigSumTotal) = split /,/, $line;
			next;
		}
		
		($ambig, $prob) = split / \\ /, $ambig_prob;

		if($stage == 0){
			$chnNameAmbig{$name}    = $ambig;
		}
		elsif($stage == 1){
			$surnameAmbig{$name}    = $ambig;
			$surnameProb{$name}     = $prob;
			$logSurnameProb{$name}  = log($prob);
		}
		elsif($stage == 2){
			$givennameAmbig{$name}    = $ambig;
			$givennameProb{$name}     = $prob;
			$logGivennameProb{$name}  = log($prob);
		}

		$count++;
		&$progresser();
	}

	print $tee "$count Chinese $stageNames[$stage] loaded\n";
	$chnNameAmbigLoaded = 1;
}

sub loadNameCoauthors($)
{
	my ($coauthorFilename) = @_;

	my $COAUTHORS;

	print $tee "Loading name coauthor stat file '$coauthorFilename'...\n";
	open_or_die($COAUTHORS, "< $coauthorFilename");

	%cnCoauthorCount = ();
	%name2coauthors = ();
	
	my $line;

	my ($name, $cnCoauthorCount, $otherCoauthorCount, $coauthors);
	my @coauthors;
	my ($coauthor, $pubcount);
	
	my $nameCount = 0;
	my $coauthorSum = 0;
	
	my $progresser = makeProgresser(vars => [ \$nameCount, \$coauthorSum ]);

	# name \t cn coauthor count \t other coauthor count \t cn coauthors \t other coauthors
	# langis gagnon	2	1	yulong shen:1	yunlong sheng:1	france laliberte:2
	while($line = <$COAUTHORS>){
		# only the final converged ambiguity is used
		($name, $cnCoauthorCount, $otherCoauthorCount, $coauthors) = split /\t/, $line, 4;
		@coauthors = split /\t/, $coauthors;
		
		$cnCoauthorCount{$name} = $cnCoauthorCount;
		
		for $coauthor(@coauthors){
			($coauthor, $pubcount) = split /:/, $coauthor;
			$name2coauthors{$name}{$coauthor} = $pubcount;
		}
		if(scalar @coauthors != $cnCoauthorCount + $otherCoauthorCount){
			die "Actual coauthor count ", scalar @coauthors, " != claimed coauthor count ", 
					$cnCoauthorCount + $otherCoauthorCount, "\n";
		}
		
		$nameCount++;
		$coauthorSum += $cnCoauthorCount + $otherCoauthorCount;
		&$progresser();
	}

	&$progresser(1);
	
	print $tee "$nameCount names' coauthor stats ($coauthorSum total) loaded\n";
	$coauthorStatLoaded = 1;
}

sub removeStopWords
{
	my @words = decap(@{$_[0]});
	return grep { $_ ne "" && !exists $stopwords{$_} } @words;
}

# not a typo: return a recoverer, which recovers the original word of a stemmed/lemmatized form
sub recovererFromInvTable
{
	my $invTable = shift;

	return sub($)
	{
		my $phrase = shift;
		my @words = split / /, $phrase;
		my @originals;
		my $w;
		my @lemmas;

		for $w(@words){
			if(!exists $invTable->{$w}){
				push @originals, "($w)";
				next;
			}
			@lemmas = grep { 			$_ ne $w
											&&
							 lc(substr($_,0,1)).substr($_,1) ne $w
							} @{$invTable->{$w}};
			if(!@lemmas){
				push @originals, "($w)";
			}
			else{
				push @originals, "(" . join(',', @lemmas) . ")";
			}
		}

		# stemmed/lemmatized form "\t" original form
		my $wordstr = $phrase . "\t" . (join "", @originals);

		# also output the number of authors using this term
		if(@words == 2){
			return $wordstr . "\t" . (scalar keys %{$gBigrams{$phrase}->authorFreq});
		}
		else{
			return $wordstr . "\t" . (scalar keys %{$gUnigrams{$phrase}->authorFreq});
		}
	}
}

sub lemmatize0
{
	my @results;
	my $lemma;

	for(@_){
		print $MORPH_IN "$_\n";

		if(eof($MORPH_OUT)){
			warn "'morpha' terminates unexpectedly\n";
			return arrayOrFirst(wantarray, \@_);
		}

		$lemma = <$MORPH_OUT>;
		trim($lemma);
		push @results, $lemma;
		$morphCallCount++;
	}

	return arrayOrFirst(wantarray, \@results);
}

sub lemmatize
{
	my @results;
	my $lemma;
	my $suffix;
	my $decapWord;
	
	for(@_){
		$decapWord = decap($_);

		if(exists $lemmaLookup{$_}){
			push @results, $lemmaLookup{$_};
		}
		elsif(exists $lemmaLookup{$decapWord}){
			push @results, $lemmaLookup{$decapWord};
		}
		else{
			# check in original form
			given($_){
				# contains a digit. uppercase. 3d => 3D. 4gl => 4GL
				when( /[0-9]/ ){
					$lemma = uc($_);
					$suffix = SUFFIX_NONE;
				}
				# doesn't contain letters. doesn't contain digits either. what the hell is it?
				when(! /[A-Za-z]/){
					$lemma = $_;
					$suffix = SUFFIX_NONE;
					print $LOG "Weird word lemmatized: '$_'\n";
				}
				# 'SoC' => 'SOC'
				when( length >= 2 && /^[A-Z]/ && /[A-Z]$/ ){
					$lemma = uc($_);
					$suffix = SUFFIX_NONE;
				}
				# 'ASICs' => 'ASIC', 'SoCs' => 'SOC'
				when( /^([A-Z][A-Za-z]*[A-Z])s$/ ){
					$lemma = uc($1);
					$suffix = SUFFIX_NONE;
				}
				# all capitals or digits (at least one capital), keep untouched
				# GPU => GPU
				when( ! /[a-z]/ && /[A-Z]{2}/ ){
					$lemma = $_;
					$suffix = SUFFIX_NONE;
				}
				# last two letters are capital
				# OpenGL (openGL) => OPENGL, cPU => CPU
				when( /[[A-Z]{2}$/ ){
					$lemma = uc($_);
					$suffix = SUFFIX_NONE;
				}
				
				# if the decapped word is a stop word, no further check is needed
				# if not checked before lemmatize0(), "using" and "based" will become normal words
				when( exists $stopwords{$decapWord}){
					$lemma = $decapWord;
					$suffix = STOPWORD;
				}
				
				default{
					$lemma = lemmatize0($decapWord);
					# if lengths are the same, they should be just different at the case. ignorable
					if(length($lemma) < length($_)){
						if(/((ed|t|n)|(s)|(ing))$/){
							if($2){
								$suffix = SUFFIX_ED;
							}
							# treat the word with "(e)s" as the same as the lemma
							elsif($3){
								$suffix = SUFFIX_NONE;
							}
							else{
								$suffix = SUFFIX_ING;
							}
						}
						else{
							$suffix = SUFFIX_NONE;
						}
					}
					else{
						$suffix = SUFFIX_NONE;
					}
				}
			}

			push @{$invLemmaTable{$lemma}}, $_;
			if($lemmaSuffLookup{"$lemma,$suffix"}){
				my $lemmaID = $lemmaSuffLookup{"$lemma,$suffix"};
				push @results, $lemmaID;
				$lemmaLookup{$_} = $lemmaID;
			}
			else{
				$lemmaCache[$lemmaGID] = [ $lemma, $suffix ];
				$lemmaSuffLookup{"$lemma,$suffix"} = $lemmaGID;
				$lemmaLookup{$_} = $lemmaGID;
				push @results, $lemmaGID;
				$lemmaGID++;
			}
		}
	}

	return arrayOrFirst(wantarray, \@results);
}

sub lemmatizePhrase($;$)
{
	my ( $phrase, $removeStop ) = @_;
	my (@words, @lemmas);
	my @results;

	my @pieces = split /\s*[,;:`\"()?!{}]\s*|--+|\s*-\s+|''|\.\s|\.$|\.\.+/, $phrase;
	my $piece;

	for $piece(@pieces){
		next if $piece eq "";

		if($piece !~ /[A-Za-z0-9]/){
			next;
		}

		my @pieceWords = split
		/\s+\+|^\+|\+?[*\/&%=<>\[\]~\|\@\$]+\+?|\'\s+|\'s\s+|\'s$|\s+\'|^\'|\'$|\$|\\|\s+/,
		$piece;

		push @words, @pieceWords;
	}
	@words = grep { $_ ne "" } @words;

#	@words = $phrase =~ /\b([a-zA-Z0-9]+)\b/g;
	if($removeStop){
		@words = removeStopWords(\@words);
	}
	@lemmas = lemmatize(@words);
	return @lemmas;
}

sub getLemma
{
	my $lemmaID = shift;
	if($lemmaID <= 0 || $lemmaID >= $lemmaGID){
		return "NONEXIST";
	}

	return $lemmaCache[$lemmaID]->[0];
}

sub recoverLemma($)
{
	$pRecoverLemma->($_[0]);
}

sub insIds2phrase($$$)
{
	my ($table, $ids, $phrase) = @_;
	my $uuid = join(",", @$ids);
	if(exists $table->{$uuid}){
		push @{ $table->{$uuid} }, $phrase;
	}
	else{
		$table->{$uuid} = [ $phrase ];
	}
}

sub extractTitleWords($$;$)
{
	my ($title, $results, $keepStop) = @_;

	my @pieces = split /\s*[,;:`\"()?!{}]\s*|--+|\s*-\s+|''|\.\s|\.$|\.\.+/, $title;
	my $piece;

	@$results = ();

	my @wordsInPieces;
	my $wc = 0;

	for $piece(@pieces){
		next if $piece eq "";

		if($piece !~ /[A-Za-z0-9]/){
			next;
		}

		my @words = split
		/\s+\+|^\+|\+?[\-*\/&%=<>\[\]~\|\@\$]+\+?|\'\s+|\'s\s+|\'s$|\s+\'|^\'|\'$|\$|\\|\s+/,
		$piece;

		@words = grep { $_ ne "" } @words;

		push @wordsInPieces, [ @words ];
		$wc += @words;
	}

	my $pWords;
	my @words;

	for $pWords(@wordsInPieces){
		if(! $keepStop){
			@words = removeStopWords($pWords);
		}
		else{
			@words = @$pWords;
		}

		my ($w, $lemmaID);
		my @lemmaIDs = ();

		for $w(@words){
			# convert literal words to lemma IDs
			$lemmaID = lemmatize($w);

			if(! $keepStop && $stopwords{ $lemmaCache[$lemmaID]->[0] } ){
				next;
			}

			push @lemmaIDs, $lemmaID;
		}
	#		@words = map { s/\'s$//; $_ } @words;

		push @$results, \@lemmaIDs;
	}
}

# mainly used by indexer and matcher in ConceptNet.pm
# @$stopwordGapNums stores the number of stop words between two non-stop words
# @$stopwordGapWeights stores the weight sum of the list of stop words between them
# @$stopwordGapNums, @$stopwordGapWeights both have length of "number of non-stop tokens + 1"
# e.g.: "the cat is a dog wonder where who", @$stopwordGapNums is "1,2,0,2"
# @$stopwordGapWeights is "1, 1.2, 0, 2"
sub extractTitleTokens($$$$)
{
	my ( $title, $lemmaIDs, $stopwordGapNums, $stopwordGapWeights ) = @_;

	my @pieces = split /\s*[,;:`\"()?!{}]\s*|--+|\s*-\s+|''|\.\s|\.$|\.\.+/, $title;
	my $piece;

	@$lemmaIDs = ();
	@$stopwordGapNums = ();
	@$stopwordGapWeights = ();
	
	my @wordsInPieces;
	my $wc = 0;

	for $piece(@pieces){
		next if $piece eq "";

		if($piece !~ /[A-Za-z0-9]/){
			next;
		}

		my @words = split
		/\s+\+|^\+|\+?[*\/&%=<>\[\]~\|\@\$]+\+?|\'\s+|\'s\s+|\'s$|\s+\'|^\'|\'$|\$|\\|\s+/,
		$piece;

		@words = grep { $_ ne "" } @words;

		push @wordsInPieces, \@words;
		$wc += @words;
	}

	my $pWords;
	my @words;

	my $stopwordGapNum = 0;
	my $stopwordGapWeight = 0;
	my $doRemoveStopwords = 1;

	for $pWords(@wordsInPieces){

		my @stopwordGapNums = ();
		my @stopwordGapWeights = ();

=pod

03/21/2012 This strategy is DISABLED. A stop word, even if kept, has no TF*IAF score, therefore 
the matching score couldn't be accurately calculated. So always remove them
		# when there are <= $KEEP_STOP_WORD_WHEN_N_NONSTOP_TOKENS nonstop words, stop words are not removed
		@words = removeStopWords($pWords);

		# too few words left after removing stopwords. so keep stopwords
		# for ungrouped case, this loop repeats only once.
		# so we needn't set $doRemoveStopwords back to 0
		if(@words <= $KEEP_STOP_WORD_WHEN_N_NONSTOP_TOKENS){
			$doRemoveStopwords = 0;
		}
		else{
			$doRemoveStopwords = 1;
		}
=cut

		my ($w, $lemmaID);
		my @lemmaIDs = ();
		
		for $w(@$pWords){
			if($w =~ /-/){
				my @parts = split /-/, $w;
				my $part;

				my $i;
				my ($isRe, $isAfterRe, $isAfterRestop);
				$isRe = $isAfterRe = $isAfterRestop = 0;

				for($i = 0; $i < @parts; $i++){
					$part = $parts[$i];
					if( $part =~ /^([Rr]e|[Pp]re)$/ && $i < @parts - 1 ){
						# put $parts[$i+1] before "re"$parts[$i+1]. e.g. "sampling" before "resampling"
						# "re"something is usually a verb followed by an object. so it's closer coupled
						# with the following word. therefore put it as the latter
						$part = $parts[$i+1];
						$parts[$i+1] = "re$parts[$i+1]";
						$isRe = 1;
					}
					else{
						$isRe = 0;
					}

					# change: for a phrase in the form of "aaa-bbbb" (two words, which is mostly the case),
					# always keep the stop word. 
					# Such as: self-regulation (if 'self' is a stop word)
					# for a longer phrase, stop words will still be removed, as if there were no hyphens
					if( @parts > 2 && $stopwords{ lc($part) } ){
						# the gap of the last word in a hyphened phrase will be added
						# to the word next to the hyphened phrase
						if(! $isRe){
							# the stopword gap between $part & $parts[$i+1] now is pointless
							# since $part is a stopword and removed
							$stopwordGapNum++;
							$stopwordGapWeight += $stopwordGapWeight{ lc($part) };
						}
						else{
							# if "re" followed by a stop word (which seems impossible)
							# $stopwordGapNum(Weight) will be kept as the same as the $stopwordGapNum(Weight) before "re"
							# since next part is "re"something, where "re" is a part of it
							$isAfterRestop = 1;
							$isRe = 0;
						}
						next;
					}

					my $lemmaID = lemmatize($part);
					push @lemmaIDs, $lemmaID;

					if($i == 0 || $isAfterRestop){
						push @stopwordGapNums, $stopwordGapNum;
						push @stopwordGapWeights, $stopwordGapWeight;
						$isAfterRestop = 0;
					}
					elsif($isAfterRe){
						# no gap between 'something' & "re"something
						push @stopwordGapNums, 0;
						push @stopwordGapWeights, 0;
						$isAfterRe = 0;
					}
					else{
						# "-1" means this word must be with the preceding word
						push @stopwordGapNums, -1;
						push @stopwordGapWeights, -1;
					}
					$stopwordGapNum = 0;
					$stopwordGapWeight = 0;

					if($isRe){
						$isAfterRe = 1;
					}
				}

				next;
			}

			if( $doRemoveStopwords && $stopwords{ lc($w) } ){
				$stopwordGapNum++;
				$stopwordGapWeight += $stopwordGapWeight{ lc($w) };
				next;
			}

			# convert literal words to lemma IDs
			$lemmaID = lemmatize($w);

			push @lemmaIDs, $lemmaID;
			push @stopwordGapNums, $stopwordGapNum;
			push @stopwordGapWeights, $stopwordGapWeight;
			$stopwordGapNum = 0;
			$stopwordGapWeight = 0;
		}
	#		@words = map { s/\'s$//; $_ } @words;

		push @$lemmaIDs, @lemmaIDs;
		push @$stopwordGapNums, @stopwordGapNums;
		push @$stopwordGapWeights, @stopwordGapWeights;
		# an arbitrary big number to prevent a query astride the piece boundary
		$stopwordGapNum += 10;
		$stopwordGapWeight += 10; 
	}
	# for the last stopword count, record the stop word count at the end of the title.
	# so it need not to be added with the boundary punishment. Thus we subtract the punishment here
	if($stopwordGapNum >= 10){
		$stopwordGapNum -= 10;
		$stopwordGapWeight -= 10;
	}
	push @$stopwordGapNums, $stopwordGapNum;
	push @$stopwordGapWeights, $stopwordGapWeight;
}

sub extractTitleGrams($$$;$)
{
	my ($title, $pUnigrams, $pBigrams, $keepStop) = @_;

	my %unigrams;
	my %bigrams;

	my @wordgroups;

	extractTitleWords($title, \@wordgroups, $keepStop);

	my $wordgroup;
	my @words;
	my $i;

	for $wordgroup(@wordgroups){
		my @words = map { $lemmaCache[$_]->[0] } @{$wordgroup};

		for($i = 0; $i < @words - 1; $i++){
			$unigrams{$words[$i]}++;
			$bigrams{"$words[$i] $words[$i + 1]"}++;
		}
		if($i == @words - 1){
			$unigrams{$words[$i]}++;
		}
	}

	@{$pUnigrams} = keys %unigrams;
	@{$pBigrams} = keys %bigrams;
}

=pod
sub titleSetTermDistro
{
	my ($titles, $unigramDistro, $bigramDistro) = @_;

	my (@unigrams, @bigrams);

	my $title;

	my $N = @{$titles};

	if($N == 0){
		return;
	}

	for $title(@{$titles}){
		extractTitleGrams($title, \@unigrams, \@bigrams);
		map { $unigramDistro->{$_}{q}++ } @unigrams;
		map { $bigramDistro->{$_}{q}++ } @bigrams;
	}

	my $term;

	for $term(keys %{$unigramDistro}){
		if($unigramDistro->{$term}{q} == 1){
			delete $unigramDistro->{$term};
			next;
		}
		$unigramDistro->{$term}{p} = $unigramDistro->{$term}{q} / $N;
	}

	for $term(keys %{$bigramDistro}){
		if($bigramDistro->{$term}{q} == 1){
			delete $bigramDistro->{$term};
			next;
		}
		$bigramDistro->{$term}{p} = $bigramDistro->{$term}{q} / $N;
	}
	$unigramDistro->{TITLE_COUNT} = $N;
	$bigramDistro->{TITLE_COUNT} = $N;
}

sub calcGramEvidence
{
	my ($w, $authorDistro, $globalDistro) = @_;

	my ($m, $mcommon);
	my $N = $authorDistro->{TITLE_COUNT};

	my $pdiff = 1;

	$m = $authorDistro->{$w}{q};
	$mcommon = $m - $N * $globalDistro->{$w}->prob;
	if($mcommon <= 1){
		return 0;
	}
	$authorDistro->{$w}{e} = $mcommon * ($mcommon - 1) / ( $m * ($m - 1) );
	return $authorDistro->{$w}{e};
}

sub calcWordbagSimi
{
	my ($wb1, $wb2, $authorDistro) = @_;

	my $w;
	my $pdiff = 1;

	for	$w(keys %{$wb2}){
		if(!exists $wb1->{$w}){
			next;
		}
		$pdiff *= 1 - $authorDistro->{$w}{e};
	}
	return $pdiff;
}

sub calcTitleSetSimi
{
	my ($context, $c1, $c2) = @_;

	if(!$c1 || !$c2){
		return 100;	# empty set should never be similar to a non-empty set
	}

	my $gramType;
	my %diffByGram;
	my $diff = 1;

	for $gramType("Unigrams", "Bigrams"){
		my $authorDistro = $context->{"au$gramType"};
		my $globalDistro = $context->{"g$gramType"};
		my $wordbags = $context->{"title_$gramType"};

		my (%wb1, %wb2);
		my $titleID;

		for $titleID(@{$c1}){
			map { $wb1{$_}++ } @{$wordbags->[$titleID]};
		}
		for $titleID(@{$c2}){
			map { $wb2{$_}++ } @{$wordbags->[$titleID]};
		}

		$diffByGram{$gramType} = calcWordbagSimi(\%wb1, \%wb2, $authorDistro);
		$diff *= $diffByGram{$gramType};
	}

	return $diff;
}
=cut

sub intersect($$)
{
	my ($s1, $s2) = @_;

	return () if !$s1 || !$s2;

	if(@$s1 < @$s2){
		($s1, $s2) = ($s2, $s1);
	}

	my %set2;
	@set2{@$s2} = ();

	my @joint;

	my $e;
	for $e(@$s1){
		if(exists $set2{$e}){
			push @joint, $e;
		}
	}
	return @joint;
}

sub intersectHash($$)
{
	my @sets = @_;

	my ($s1, $s2);

	# smaller sets first, bigger sets latter
	if( scalar keys %{ $sets[0] } < scalar keys %{ $sets[1] } ){
		($s1, $s2) = @sets;
	}
	else{
		($s2, $s1) = @sets;
	}

	my @joint;

	my $e;

	for $e(keys %$s1){
		if(exists $s2->{$e}){
			push @joint, $e;
		}
	}
	return @joint;
}

# return elems in @$s1 but not in @$s2
sub subtractSet($$)
{
	my ($s1, $s2) = @_;

	my %set2;
	@set2{@$s2} = ();

	my @difference;

	my $e;
	for $e(@$s1){
		if(!exists $set2{$e}){
			push @difference, $e;
		}
	}
	return @difference;
}

sub subtractHash($$)
{
	my ($s1, $s2) = @_;

	if(keys %$s1 > keys %$s2){
		($s2, $s1) = ($s1, $s2);
	}
	
	my %difference;

	my $e;
	for $e(keys %$s1){
		if(!exists $s2->{$e}){
			$difference{$e} = 1;
		}
	}
	return %difference;
}

# Given two sets of array refs. Find if there's a shared array (by their contents) between them
sub intersectArrayOfArray($$)
{
	my ($s1, $s2) = @_;
	
	return () if !$s1 || !$s2;

	# @$s1 is always larger, so the cost of building the hash is lower
	if(@$s1 < @$s2){
		($s1, $s2) = ($s2, $s1);
	}

	my %set2 = map { join(",", @$_) => 1 } @$s2;
	
	my @joint;
	my $ar;
	for $ar(@$s1){
		my $key = join(",", @$ar);
		if(exists $set2{$key}){
			push @joint, $ar;
		}
	}
	return @joint;
}

sub unionArrayToArray
{
	my %set;
	my $s;

	for $s(@_){
		for(@$s){
			$set{$_} = 1;
		}
	}

	return keys %set;
}

# Do a union on all elements in the array refs in @_
# Return a hash ref whose keys are the elements, 
# and the values are the keys' frequency sum in all array elements
sub unionArrayToHashRef
{
	my %set;
	my $s;

	for $s(@_){
		for(@$s){
			$set{$_}++;
		}
	}

	return \%set;
}


sub unionHashToHashRef
{
	my %set;
	my $s;

	for $s(@_){
		for(keys %$s){
			$set{$_} += $s->{$_};
		}
	}

	return \%set;
}

sub mergeHash($$)
{
	my ($pTo, $pFrom) = @_;

	my $k;
	my $warnOnOW = $DEBUG & DBG_MERGE_HASH_OVERWRITE;

	for $k(keys %{$pFrom}){
		if(exists $pTo->{$k} && $warnOnOW){
			warn "'$k' in the hash is overwritten ( $pTo->{$k} => $pFrom->{$k} )\n";
		}
		$pTo->{$k} = $pFrom->{$k};
	}
}

sub dumpSortedHash($$$)
{
	my ($h, $cmp, $formatter) = @_;

	my @keys;

	if(! $cmp){
		@keys = sort { $h->{$b} <=> $h->{$a} } keys %$h;
	}
	else{
		@keys = sort { &$cmp($a, $b) } keys %$h;
	}

	my $s;

	if(! $formatter){
		$s = join( "\t", map { "$_: $h->{$_}" } @keys );
	}
	else{
		$s = join( "\t", map { &$formatter($_) } @keys );
	}
	return $s;
}

sub hashTopN($$$;$)
{
	my ($ph, $N, $accessor, $callback) = @_;
	my @values = values %$ph;

	if(@values <= $N){
		return %$ph;
	}

	@values = sort { &$accessor($b) <=> &$accessor($a) } @values;

	my $cutoff = &$accessor( $values[$N - 1] );

	if($callback){
		my $biggestCutV = &$accessor( $values[$N] );
		my $biggestCutK = first_value { &$accessor( $ph->{$_} ) == $biggestCutV } keys %$ph;
		my $cutoffCount = @values - $N;
		&$callback( $cutoffCount, $biggestCutK, $biggestCutV );
	}

	return map { $_ => $ph->{$_} } grep { &$accessor( $ph->{$_} ) >= $cutoff } keys %$ph;
}

# keep those with &$filter($k, $v) returning 0
sub filterHash($$)
{
	my ($pH, $filter) = @_;
	my %newH;
	
	my ($k, $v);
	my $delCount = 0;
	
	while( ($k, $v) = each %$pH ){
		if( ! &$filter($k, $v) ){
			$newH{$k} = $pH->{$k};
		}
		else{
			$delCount++;
		}
	}
	
	return %newH;
}

sub schwartzianSort($$$)
{
	my ($array, $transformer, $isNum) = @_;
	
	my @array2 = map { [ $_, &$transformer($_) ] } @$array;
	if($isNum){
		@array2 = sort { $a->[1] <=> $b->[1] } @array2;
	}
	else{
		@array2 = sort { $a->[1] cmp $b->[1] } @array2;
	}
	
	return map { $_->[0] } @array2;
}

# return $N * ($N - 1) * ... * ($N - $M + 1), or $N! / ($N - $M)!
# UPDATE: using gamma() to generalize to the real number parameters: gamma($N + 1) / gamma($N - $M + 1)
sub factorial($;$)
{
	my $N = shift;
	my $M = shift;
	if(! defined($M) ){
		$M = $N - 1;
	}
	
	if($N < 0){
		print $tee "factorial(): '$N' < 0\n";
		die "\n";
	}
	
	if($N == 0){
		return 1;
	}

	return gamma($N + 1) / gamma($N - $M + 1);

}

sub combination($$)
{
	my ($N, $M) = @_;
	
	if($N - $M + 1 > $M){
		return factorial($N, $M) / factorial($M);
	}
	
	return factorial($N, $N - $M) / factorial($N - $M);
}

# return \sum_{$i=0}^{$M-1} log( $N - $i ), i.e. log($N) + log($N - 1) + ... + log($N - $M + 1)
# takes real arguments
sub logFactorial($;$)
{
	my $N = shift;
	my $M = shift;
	if(! defined($M) ){
		$M = $N - 1;
	}
	
	if($N < 0){
		print $tee "logFactorial(): '$N' < 0\n";
		die "\n";
	}
	
	if($N == 0){
		return 0;
	}
	
	my $logGammaDiff = log_gamma($N + 1) - log_gamma($N - $M + 1);
	
	return $logGammaDiff;
}

# takes real arguments
sub logCombination($$)
{
	my ($N, $M) = @_;
	
	return logFactorial($N, $M) - logFactorial($M);
}

# consts used in loadSimilarVenues() & expandSimilarVenues()
our $MAX_EXPANDED_VENUE_FREQ			= 1;
our $MAX_EXPANDED_VENUE_FREQ_SUM_TO_ORIGINAL_RATIO = 0.5;
our $SIMI_VENUE_RELATIVE_FREQ_DISCOUNT	= 0.5;
our $SIMI_VENUE_RESIDUE_DEV_THRES	= 2.5;
our $SIMI_VENUE_REL_FREQ_THRES	= 0.2;

our $SIMI_VENUE_LINREG_SIMI_DISCOUNT	 = 0.7;
our $SIMI_VENUE_LINREG_RESIDUE_DEV_THRES = 3;
our $SIMI_VENUE_LINREG_SIMI_THRES		 = 0.1;

sub loadSimilarVenues
{
	my $simiVenueFilename = shift;
	my $VENUESIMI;
	
	print $tee "Open '$simiVenueFilename' to load similar venue pairs\n";
	open_or_die($VENUESIMI, "< $simiVenueFilename");
	
	my $line;
	my ($v1, $v2, $relativeFreq, $residueDev, $linregSimi, $linregResidueDev, $count1, $count2);

	my $paircount = 0;
	
	my $progresser = makeProgresser( vars => [ \$. ] );
	
# ICML	NIPS	0.919745729042511	1.3294391011801	0.868507110806905	1.40663430708046	2517	2315
	while($line = <$VENUESIMI>){
		trim($line);
		($v1, $v2, $relativeFreq, $residueDev, $linregSimi, $linregResidueDev, $count1, $count2) = split /\t/, $line;

#		if($relativeFreq < $SIMI_VENUE_REL_FREQ_THRES || $residueDev > $SIMI_VENUE_RESIDUE_DEV_THRES){
#			next;
#		}

		if($linregSimi < $SIMI_VENUE_LINREG_SIMI_THRES 
								|| 
		   $linregResidueDev > $SIMI_VENUE_LINREG_RESIDUE_DEV_THRES){
			next;
		}

		# arxiv. too general and barely specific.
		if($v2 eq "CoRR"){
			next;
		}
		
#		$similarVenues{$v1}{$v2} = $SIMI_VENUE_RELATIVE_FREQ_DISCOUNT * $relativeFreq;
#		$similarVenues{$v1}{$v2} = $SIMI_VENUE_LINREG_SIMI_DISCOUNT * $linregSimi;

		# UPDATE: remove the discount here, and put the discount in expandSimilarVenues()
		$similarVenues{$v1}{$v2} = $linregSimi;
		
		$paircount++;
		
		&$progresser();
	}
	&$progresser(1);
	
	print $tee "$paircount pairs for ", scalar keys %similarVenues, " venues are loaded\n";
}

my $BASE_SET_EXPANSION_LEAST_SIMI = 0.2;
my $SAMPLED_SET_EXPANSION_LEAST_SIMI = 0.3;

# $vv1: venue vector 1, the vv to be expanded
# $vv2: venue vector 2, the vv that's referred to (only expand venues in $vv2 to $vv1)
# $simiThres: the threshold of similarity between an original venue and an expanded venue
# if $vv1 is the base set, then $simiThres should be smaller
# if $vv1 is the sampled set, then it should be larger
sub expandSimilarVenues($$$)
{
	my ($vv1, $vv2, $simiThres) = @_;
	
	my (%expandedVV, %newVV);
	
	my ($v1, $freq1, $v2, $relativeFreq, $freq2);
	
	my %validSimiVenues;
	# reweight the contributations of one venue to similar venues, to make their sum <= 1
	# otherwise a venue may expand with too many similar venues / venues with too much weights, 
	# which is not reasonable
	my $venueTotalContribReweight;
	
	while( ($v1, $freq1) = each %$vv1 ){
		if(! exists $similarVenues{$v1}){
			next;
		}
		
		# if $v2 already exists in $vv1, use this old freq instead of the predicted freq
		%validSimiVenues = map { $_ => $similarVenues{$v1}{$_} } 
							grep { ! exists $vv1->{$_} && exists $vv2->{$_} 
									&& $similarVenues{$v1}{$_} >= $simiThres } 
								keys %{ $similarVenues{$v1} };
		
		if(keys %validSimiVenues == 0){
			next;
		}
				
		while( ($v2, $relativeFreq) = each %validSimiVenues ){
			# don't totally trust the regressed similarity. give it a discount
			my $expandFreq = $freq1 * $relativeFreq * $SIMI_VENUE_LINREG_SIMI_DISCOUNT;

			# multiple venues' effects (predictions of the same venue) don't add up. just take the max
			if( ! exists $expandedVV{$v2} || $expandFreq > $expandedVV{$v2} ){
				$expandedVV{$v2} = $expandFreq;
			}
		}
	}

	# existing venues always have their old freqs
	%newVV = %$vv1;

	my $expandedVenueCount = keys %expandedVV;
	if($expandedVenueCount == 0){
		if($DEBUG & DBG_EXPAND_SIMI_VENUES){
			print $LOG "0 venues expanded, freq sum: 0\n";
			print $LOG "The expanded venue vector:\n";
			print $LOG dumpSortedHash($vv1, undef, undef), "\n";
		}
		return %newVV;
	}
	
	my @expandedVenues = sort { $vv2->{$b} <=> $vv2->{$a} } keys %expandedVV;
	
	while( ($v1, $freq1) = each %expandedVV ){
		# cap the expanded venue freq to $MAX_EXPANDED_VENUE_FREQ, to avoid expand too many freqs
		if($freq1 > $MAX_EXPANDED_VENUE_FREQ){
			$expandedVV{$v1} = $MAX_EXPANDED_VENUE_FREQ;
		}
	}

	my %realExpandedVV;
	
	my $maxExpandedFreqSum = $MAX_EXPANDED_VENUE_FREQ_SUM_TO_ORIGINAL_RATIO * sum(values %$vv1);
	my $remainedFreqSum = $maxExpandedFreqSum;
	my $expandedVenueFreqSum = 0;
	
	for $v1(@expandedVenues){
		last if $remainedFreqSum <= 0;
		
		$freq1 = $expandedVV{$v1};
		$freq2 = min( $freq1, $remainedFreqSum );
		$newVV{$v1} = $freq2;
		$remainedFreqSum -= $freq2;
		$expandedVenueFreqSum += $freq2;
		
		$realExpandedVV{$v1} = $freq2;
	}
	
	my $expandedVenueFreqSum2OriginalRatio = $expandedVenueFreqSum / sum(values %$vv1);
	
	if($DEBUG & DBG_EXPAND_SIMI_VENUES){
		print $LOG "$expandedVenueCount venues expanded, freq sum: $expandedVenueFreqSum, ratio: $expandedVenueFreqSum2OriginalRatio:\n";
		print $LOG dumpSortedHash(\%realExpandedVV, undef, undef), "\n";
		print $LOG "The old venue vector:\n";
		print $LOG dumpSortedHash($vv1, undef, undef), "\n";
		print $LOG "The new venue vector:\n";
		print $LOG dumpSortedHash(\%newVV, undef, undef), "\n";
	}
	return %newVV;
}

sub expandSimilarVenues2
{
	my $vv = shift;
	
	my %newVV;
	
	my ($v1, $freq1, $v2, $relativeFreq);
	
	my %validSimiVenues;
	# reweight the contributations of one venue to similar venues, to make their sum <= 1
	# otherwise a venue may expand with too many similar venues / venues with too much weights, 
	# which is not reasonable
	my $venueTotalContribReweight;
	
	while( ($v1, $freq1) = each %$vv ){
		if(! exists $similarVenues{$v1}){
			next;
		}
		
		# if $v2 already exists in $vv, use this old freq instead of the predicted freq
		%validSimiVenues = map { $_ => $similarVenues{$v1}{$_} } 
									grep { ! exists $vv->{$_} } keys %{ $similarVenues{$v1} };
		
		if(keys %validSimiVenues == 0){
			next;
		}
		
		$venueTotalContribReweight = sum(values %validSimiVenues);
		
		if( $venueTotalContribReweight < 1 ){
			$venueTotalContribReweight = 1;
		}
		
		while( ($v2, $relativeFreq) = each %validSimiVenues ){
			$relativeFreq /= $venueTotalContribReweight;
			
			# multiple venues' effects (predictions of the same venue) don't add up. just take the max
			if( ! exists $newVV{$v2} || $freq1 * $relativeFreq > $newVV{$v2} ){
				$newVV{$v2} = $freq1 * $relativeFreq;
			}
		}
	}

	my $newVenueCount = keys %newVV;
	my $newVenueFreqSum = sum(values %newVV) || 0;

	while( ($v1, $freq1) = each %newVV ){
		# cap the expanded venue freq to the max counted freq
		if($freq1 > $MAX_EXPANDED_VENUE_FREQ){
			$newVV{$v1} = $MAX_EXPANDED_VENUE_FREQ;
		}
	}
	
	while( ($v1, $freq1) = each %$vv ){
		# existing venues always have their old freqs
		$newVV{$v1} = $freq1;
	}
	
	if($DEBUG & DBG_EXPAND_SIMI_VENUES){
		print $LOG "$newVenueCount venues expanded, freq sum: $newVenueFreqSum\n";
		print $LOG "The old venue vector:\n";
		print $LOG dumpSortedHash($vv, undef, undef), "\n";
		print $LOG "The new venue vector:\n";
		print $LOG dumpSortedHash(\%newVV, undef, undef), "\n";
	}
	return %newVV;
}

sub jaccard($$$$)
{
	my ( $vv1, $vv2, $minSimi, $useFreq ) = @_;
	
	my $similarity;

	my $unionFreqSum = 0;
	my $intersectionFreqSum = 0;
	
	my $unionTypeNum = 0;
	my $intersectionTypeNum = 0;
	
	my $outcome1;
	
	my $tempvv;
	
	# $vv1 is always the bigger one
	if( sum(values %$vv1) < sum(values %$vv2)
		  				  ||
		scalar keys %$vv1 < scalar keys %$vv2			
	 ){
	 	($vv1, $vv2) = ($vv2, $vv1);
	}
		
	# 'UNKNOWN' in %$vv1 are hardly the same as 'UNKNOWN' in %$vv2
	if( $vv1->{'UNKNOWN'} ){
		$unionFreqSum += $vv1->{'UNKNOWN'};
		$unionTypeNum++;
	}
	if( $vv2->{'UNKNOWN'} ){
		$unionFreqSum += $vv2->{'UNKNOWN'};
		$unionTypeNum++;
	}
	
	for $outcome1( keys %$vv1 ){
		if( $outcome1 eq 'UNKNOWN' ){
			next;
		}

		if( exists $vv2->{$outcome1} ){
			$intersectionFreqSum += min ( $vv1->{$outcome1}, $vv2->{$outcome1} );
			$unionFreqSum += max ( $vv1->{$outcome1}, $vv2->{$outcome1} );
			
			$intersectionTypeNum++;
			$unionTypeNum++;
			next;
		}
		$unionFreqSum += $vv1->{$outcome1};
		$unionTypeNum++;
	}

	for $outcome1( keys %$vv2 ){
		if( $outcome1 eq 'UNKNOWN' ){
			next;
		}

		# already counted in the previous loop
		if( exists $vv1->{$outcome1} ){
			next;
		}
		$unionFreqSum += $vv2->{$outcome1};
		$unionTypeNum++;
	}
	
	if($unionFreqSum == 0){
		$similarity = 0;
	}
	elsif($useFreq){
		$similarity = $intersectionFreqSum / $unionFreqSum;
	}
	else{
		$similarity = $intersectionTypeNum / $unionTypeNum;
	}
	
	if($similarity < $minSimi){
		print $LOG "Jaccard similarity $similarity < min $minSimi, raised to $minSimi\n";
		$similarity = $minSimi;
	}
	
	return $similarity;
}

# the obsolete version of CSLR. Just keep it for a complete history
sub  isSameCategorical($$$$$$$$$)
{
	# the priors are similar to the \alpha in Dirichlet distribution
	my ($knownOutcomePrior, $unknownOutcomePrior, $unseenOutcomePrior, $seenCancelUnseenRatio,
			$vv1, $vv2, $outcomeExpander, $minSameMnOddsRatio, $outcomeMaxCountedFreq) = @_;

# $minSameMnOddsRatio:
# if the multinomial odds ratio is smaller than this value, raise to it
	
	my (%multinomial, %sample);
	
	# treat the bigger set as the multinomial template
	if( sum(values %$vv1) < sum(values %$vv2)
		  				  ||
		scalar keys %$vv1 < scalar keys %$vv2			
	 ){
		%multinomial = %$vv2;
		%sample = %$vv1;
	}
	else{
		%multinomial = %$vv1;
		%sample = %$vv2;		
	}
	
	my $outcome1;
	
	# the number of types of unseen outcomes
	my $unseenSamOutcomeCount = 0;
	# the sum of freqs of unseen outcomes 
	my $unseenSamOutcomeFreqSum = 0;
	
	# the number of types of seen outcomes in the sample
	my $seenOutcomeCount = 0;
	# # the number of types of known outcomes in the sample
	my $knownOutcomeCount = 0;
	
	# Sam: sample
	my $knownSamOutcomeFreqSum = 0;
	my $sharedSamOutcomeFreqSum = 0;
	my $knownSamOutcomeFreqSumAfterCancel;
	my $unknownSamOutcomeFreqSum = $sample{'UNKNOWN'} || 0;
	
	if($outcomeExpander){
		%multinomial = &$outcomeExpander(\%multinomial, \%sample, $BASE_SET_EXPANSION_LEAST_SIMI);
		%sample = &$outcomeExpander(\%sample, \%multinomial, $SAMPLED_SET_EXPANSION_LEAST_SIMI);
	}

	for $outcome1(keys %sample){
		next if $outcome1 eq 'UNKNOWN';
		
		$knownSamOutcomeFreqSum += $sample{$outcome1};
		$knownOutcomeCount++;
		
		if(! exists $multinomial{$outcome1}){
#			$unseenVenues{$outcome1} = $sample{$outcome1};
			$unseenSamOutcomeFreqSum += $sample{$outcome1};
			
			# the sum of pubs in unseen outcomes are not so important. 
			# the number of types are a better measure of the strangeness of the sample distribution
			# if one unseen outcome appears, it's quite likely that this outcome appears again 
			# (the author tends to publish on the same outcome). So consider them only once
			$unseenSamOutcomeCount++;
			delete $sample{$outcome1};
		}
		else{
			$seenOutcomeCount++;
			# shared counts are the min of the two values
			$sharedSamOutcomeFreqSum += min( $sample{$outcome1}, $multinomial{$outcome1} );
		}
	}
	
	# unseen: outcome exists but doesn't exist in the base multinomial
	if($unseenSamOutcomeCount > 0){
		$sample{'UNSEEN'} = $unseenSamOutcomeCount;
	}
#	if($unseenSamOutcomeFreqSum > 0){
#		$sample{'UNSEEN'} = $unseenSamOutcomeFreqSum;
#	}

	# unknown: outcome is not given in the database
	if($sample{'UNKNOWN'}){
		# each known outcome occurrence cancels one unknown outcome occurrence
		my $unknownSamOutcomeFreqSumAfterCancel = $sample{'UNKNOWN'} - $knownSamOutcomeFreqSum;
		my $unknownSamOutcomeSumCap;
		if($unknownSamOutcomeFreqSumAfterCancel > 0){
			# why cap to $knownOutcomeCount? I couldn't remember
			$unknownSamOutcomeSumCap = min($unknownSamOutcomeFreqSumAfterCancel, $knownOutcomeCount);
			$unknownSamOutcomeSumCap = max( 1, $unknownSamOutcomeSumCap);
		}
		else{
			$unknownSamOutcomeSumCap = 0;
		}
		$sample{'UNKNOWN'} = $unknownSamOutcomeSumCap;
	}
	
	if($sample{'UNSEEN'}){
		# each seen outcome cancels 1/2 unseen outcome. the resulted freq needs be an integer
		my $unseenSamOutcomeCountAfterCancellation = max( 0, $sample{'UNSEEN'}
													- int($seenOutcomeCount * $seenCancelUnseenRatio) );
		$sample{'UNSEEN'} = $unseenSamOutcomeCountAfterCancellation;
	}
	
	my $knownOutcomeSum = 0;
	for $outcome1(keys %multinomial){
		next if $outcome1 eq 'UNKNOWN';
		
		$multinomial{$outcome1} += $knownOutcomePrior;
		if($multinomial{$outcome1} > $outcomeMaxCountedFreq){
			$multinomial{$outcome1} = $outcomeMaxCountedFreq;
		}
		$knownOutcomeSum += $multinomial{$outcome1};
	}

	if($unseenSamOutcomeCount){
		if( $unknownSamOutcomeFreqSum){
			if( ! $multinomial{'UNKNOWN'} ){
				# 'UNKNOWN' and 'UNSEEN' share the prior of 'UNSEEN'
				# coz in this case 'UNKNOWN' is similar to 'UNSEEN' (the source multinomial
				# had no 'UNKNOWN' generator at first
				$multinomial{'UNKNOWN'} = $unknownOutcomePrior * $unseenOutcomePrior / 
											( $unknownOutcomePrior + $unseenOutcomePrior);
				$multinomial{'UNSEEN'}  = $unseenOutcomePrior  * $unseenOutcomePrior / 
											( $unknownOutcomePrior + $unseenOutcomePrior);
			}
			else{
				$multinomial{'UNKNOWN'} += $unknownOutcomePrior;
				$multinomial{'UNSEEN'} = $unseenOutcomePrior;
			}
		}
		else{
			$multinomial{'UNSEEN'} = $unseenOutcomePrior;
		}
	}
	else{
		if($unknownSamOutcomeFreqSum){
			$multinomial{'UNKNOWN'} += $unknownOutcomePrior;
		}
		$multinomial{'UNSEEN'} = $unseenOutcomePrior;
	}

	# only one 'UNSEEN' is too strict. $sampleSupportElemNum is too small
	# assume there are sqrt(seen_slot_num) unseen slots (at least one).
	# $extraUnseenSlotNum is (Unseen_Slot_Num - 1) (at least 0).
	my $extraUnseenSlotNum = sqrt((scalar keys (%multinomial) - 1)) - 1;
	$extraUnseenSlotNum = 0; #int($extraUnseenSlotNum);
	
	my $s = sum(values %multinomial) + $extraUnseenSlotNum * $multinomial{'UNSEEN'};
	my $freq1;
	
	# the value for each %multinomial key is changed from a single value (freq) to an array ref
	while( ($outcome1, $freq1) = each %multinomial ){
								  # freq, prob
		$multinomial{$outcome1} = [ $freq1, $freq1 / $s ];
	}
	
	my $N = sum(values %sample);
	
	my ($prob, $likelihoodRatio);
	
	# if $N is too big, use log to calc the likelihood ratio
	if($N > 20){
		my $logPolynomialCoeff = logFactorial($N);
		my $logProb = 0;
		
		while( ($outcome1, $freq1) = each %sample){
			$logPolynomialCoeff -= logFactorial($freq1);
			$logProb += log( $multinomial{$outcome1}[1] ) * $freq1;
		}
		$logProb += $logPolynomialCoeff;
		
		my $M = keys %multinomial;
		
		# support of the sample is the set of all possible combinations of the $N sample
		my $logSampleSupportElemNum = logCombination( $M + $extraUnseenSlotNum + $N - 1, $N );
		
		#dieIfNotInteger($sampleSupportElemNum, "$M,$N");
		
		my $logLikelihoodRatio = $logProb + $logSampleSupportElemNum; 
		
		$prob = exp($logProb);
		$likelihoodRatio = exp($logLikelihoodRatio);
	}
	else{
		my $polynomialCoeff = factorial($N);
		$prob = 1;
		
		while( ($outcome1, $freq1) = each %sample){
			$polynomialCoeff /= factorial($freq1);
			$prob *= $multinomial{$outcome1}[1] ** $freq1;
		}
		$prob *= $polynomialCoeff;
		
		#dieIfNotInteger($polynomialCoeff);
		
		my $M = keys %multinomial;
		
		# support of the sample is the set of all possible combinations of the $N sample
		my $sampleSupportElemNum = combination( $M + $extraUnseenSlotNum + $N - 1, $N );
									#factorial( $M + $N - 1, $M - 1 ) / factorial( $M - 1 );
		
		#dieIfNotInteger($sampleSupportElemNum, "$M,$N");
		
		$likelihoodRatio = $prob * $sampleSupportElemNum; 
	}
	
	if($likelihoodRatio < $minSameMnOddsRatio){
		# this small value may be caused by the small sizes of two sets (therefore not enough samples
		# to find their commonness)
		if( $likelihoodRatio * 100 >= $minSameMnOddsRatio ){
			print $LOG "Distro likelihoodRatio $likelihoodRatio < min $minSameMnOddsRatio, raised to $minSameMnOddsRatio\n";
			$likelihoodRatio = $minSameMnOddsRatio;
		}
		# these two sets are statistically significantly disparate (big enough sets)
		# practically there is no chance for them to be merged
		else{
			$minSameMnOddsRatio /= 100;
			print $LOG "Distro likelihoodRatio $likelihoodRatio < min $minSameMnOddsRatio, raised to $minSameMnOddsRatio\n";
			$likelihoodRatio = $minSameMnOddsRatio;
		}
	}
	
	if(wantarray){
		return ($prob, $likelihoodRatio);
	}
	return $likelihoodRatio;
}

# the new (currently used) version of CSLR
# 'UNKNOWN': the venue is not given in DBLP database. It's extremely rare (1677 out of 1.5M)
# and can be safely ignored when understanding the algorithm
# 'UNSEEN': the venue in the sample is given, but not present in the base observation
sub isSameCategorical2($$$$$$$$$)
{
	# the priors are similar to the \alpha in Dirichlet distribution
	my ($knownOutcomePrior, $unknownOutcomePrior, $unseenOutcomePrior, $unseenReductionFraction,
			$vv1, $vv2, $outcomeExpander, $minSameMnOddsRatio, $outcomeMaxCountedFreq) = @_;

# $minSameMnOddsRatio:
# if the multinomial odds ratio is smaller than this value, raise to it

# $unseenReductionFraction: very important parameter. In the sampled set, some count of
# UNSEEN is reduced, by $unseenReductionFraction * the size of the sampled set
# a reasonable choice is 1/3

	my (%multinomial, %sample);
	
	# treat the bigger set as the multinomial template
	if( sum(values %$vv1) < sum(values %$vv2)
		  				  ||
		sum(values %$vv1) == sum(values %$vv2) && 
		scalar keys %$vv1 < scalar keys %$vv2			
	 ){
		%multinomial = %$vv2;
		%sample = %$vv1;
	}
	else{
		%multinomial = %$vv1;
		%sample = %$vv2;		
	}
	
	my $outcome1;
	
	# the number of types of unseen outcomes
	my $unseenSamOutcomeCount = 0;
	# the sum of freqs of unseen outcomes 
	my $unseenSamOutcomeFreqSum = 0;
		
	# Sam: sample
	my $knownSamOutcomeFreqSum = 0;
	my $knownSamOutcomeFreqSumAfterCancel;
	my $unknownSamOutcomeFreqSum = $sample{'UNKNOWN'} || 0;

	for $outcome1(keys %multinomial){
		next if $outcome1 eq 'UNKNOWN';
		
		if($multinomial{$outcome1} > $outcomeMaxCountedFreq){
			$multinomial{$outcome1} = $outcomeMaxCountedFreq;
		}
	}
	
	if($outcomeExpander){
		%multinomial = &$outcomeExpander(\%multinomial, \%sample, $BASE_SET_EXPANSION_LEAST_SIMI);
		%sample = &$outcomeExpander(\%sample, \%multinomial, $SAMPLED_SET_EXPANSION_LEAST_SIMI);
	}

	for $outcome1(keys %sample){
		next if $outcome1 eq 'UNKNOWN';
		
		if(! exists $multinomial{$outcome1}){
			$unseenSamOutcomeFreqSum += $sample{$outcome1};
			$unseenSamOutcomeCount++;
			
			delete $sample{$outcome1};
		}
	}
	
	if($unseenSamOutcomeFreqSum > 0){
		$sample{'UNSEEN'} = $unseenSamOutcomeFreqSum;
	}

	for $outcome1(keys %multinomial){
		next if $outcome1 eq 'UNKNOWN';
		
		$multinomial{$outcome1} += $knownOutcomePrior;
	}

	if($unseenSamOutcomeCount){
		# This case is very rare
		# Usually there's no 'UNKNOWN' either in the sample or in the base observations
		if( $unknownSamOutcomeFreqSum){
			if( ! $multinomial{'UNKNOWN'} ){
				# 'UNKNOWN' and 'UNSEEN' share the prior of 'UNSEEN'
				# coz in this case 'UNKNOWN' is similar to 'UNSEEN' (the source multinomial
				# had no 'UNKNOWN' generator at first
				$multinomial{'UNKNOWN'} = $unknownOutcomePrior * $unseenOutcomePrior / 
											( $unknownOutcomePrior + $unseenOutcomePrior);
				$multinomial{'UNSEEN'}  = $unseenOutcomePrior  * $unseenOutcomePrior / 
											( $unknownOutcomePrior + $unseenOutcomePrior);
			}
			else{
				$multinomial{'UNKNOWN'} += $unknownOutcomePrior;
				$multinomial{'UNSEEN'} = $unseenOutcomePrior;
			}
		}
		else{
			$multinomial{'UNSEEN'} = $unseenOutcomePrior;
		}
	}
	else{
		if($unknownSamOutcomeFreqSum){
			$multinomial{'UNKNOWN'} += $unknownOutcomePrior;
		}
		$multinomial{'UNSEEN'} = $unseenOutcomePrior;
	}

=pod
# $extraUnseenSlotNum is DISABLED
	# only one 'UNSEEN' is too strict. $sampleSupportElemNum is too small
	# assume there are sqrt(seen_slot_num) unseen slots (at least one).
	# $extraUnseenSlotNum is (Unseen_Slot_Num - 1) (at least 0).
	my $extraUnseenSlotNum = sqrt((scalar keys (%multinomial) - 1)) - 1;
	my $extraUnseenSlotNum = 0; #int($extraUnseenSlotNum);
	my $s = sum(values %multinomial) + $extraUnseenSlotNum * $multinomial{'UNSEEN'};
=cut
	
	my $s = sum(values %multinomial);

	my $freq1;
	
	# the value for each %multinomial key is changed from a single value (freq) to an array ref
	while( ($outcome1, $freq1) = each %multinomial ){
								  # freq, prob
		$multinomial{$outcome1} = [ $freq1, $freq1 / $s ];
	}

=pod	
	# the top $topLikelyOutcomeFraction of the outcomes comprise a new sample
	my %sample;	
	
	my $N = sum(values %sample);
	# round up (ceiling)
	my $N = atLeast1( $topLikelyOutcomeFraction * $N, 1 );
	
	if($N == $N){
		%sample = %sample;
	}
	else{
		my @samOutcomes = sort { $multinomial{$b}[1] <=> $multinomial{$a}[1] } keys %sample;
		
		my $countedN = 0;
		for $outcome1(@samOutcomes){
			if( $countedN + $sample{$outcome1} < $N ){
				$sample{$outcome1} = $sample{$outcome1};
				$countedN += $sample{$outcome1};
			}
			else{
				$sample{$outcome1} = $N - $countedN;
				last;
			}
		}
	}
=cut

	my $N = sum(values %sample);
	my $unseenReduction = int( $N * $unseenReductionFraction );
	if( $sample{UNSEEN} ){
		$sample{UNSEEN} -= min( $unseenReduction, $sample{UNSEEN} );
	}
	$N = sum(values %sample);
		
	my ($prob, $likelihoodRatio);
	
	# if $N is too big, use log to calc the likelihood ratio
	if($N > 20){
		my $logPolynomialCoeff = logFactorial($N);
		my $logProb = 0;
		
		while( ($outcome1, $freq1) = each %sample){
			$logPolynomialCoeff -= logFactorial($freq1);
			$logProb += log( $multinomial{$outcome1}[1] ) * $freq1;
		}
		$logProb += $logPolynomialCoeff;
		
		my $M = keys %multinomial;
		
		# support of the sample is the set of all possible combinations of samples of size $N
		#my $logSampleSupportElemNum = logCombination( $M + $extraUnseenSlotNum + $N - 1, $N );
		my $logSampleSupportElemNum = logCombination( $M + $N - 1, $N );
		
		#dieIfNotInteger($sampleSupportElemNum, "$M,$N");
		
		my $logLikelihoodRatio = $logProb + $logSampleSupportElemNum; 
		
		$prob = exp($logProb);
		$likelihoodRatio = exp($logLikelihoodRatio);
	}
	else{
		my $polynomialCoeff = factorial($N);
		$prob = 1;
		
		while( ($outcome1, $freq1) = each %sample){
			$polynomialCoeff /= factorial($freq1);
			$prob *= $multinomial{$outcome1}[1] ** $freq1;
		}
		$prob *= $polynomialCoeff;
		
		#dieIfNotInteger($polynomialCoeff);
		
		my $M = keys %multinomial;
		
		# support of the sample is the set of all possible combinations of samples of size $N
		#my $sampleSupportElemNum = combination( $M + $extraUnseenSlotNum + $N - 1, $N );
		my $sampleSupportElemNum = combination( $M + $N - 1, $N );
		
		$likelihoodRatio = $prob * $sampleSupportElemNum; 
	}
	
	if($likelihoodRatio < $minSameMnOddsRatio){
		# this small value may be caused by the small sizes of two sets (therefore not enough samples
		# to find their commonness)
		if( $likelihoodRatio * 100 >= $minSameMnOddsRatio ){
			print $LOG "Distro likelihoodRatio $likelihoodRatio < min $minSameMnOddsRatio, raised to $minSameMnOddsRatio\n";
			$likelihoodRatio = $minSameMnOddsRatio;
		}
		# these two sets are statistically significantly disparate (big enough sets)
		# practically there is no chance for them to be merged
		else{
			$minSameMnOddsRatio /= 100;
			print $LOG "Distro likelihoodRatio $likelihoodRatio < min $minSameMnOddsRatio, raised to $minSameMnOddsRatio\n";
			$likelihoodRatio = $minSameMnOddsRatio;
		}
	}
	
	if(wantarray){
		return ($prob, $likelihoodRatio);
	}
	return $likelihoodRatio;
}

sub clusterAuthors
{
	die "Coauthor stat file hasn't been loaded\n" if !$coauthorStatLoaded;

	my @authors = @_;
	
	my @clusters = map { [ $_ ] } @authors;
	
	my ($i, $j, $m, $n);
	my ($c1, $c2);
	my ($author1, $author2);
	my $areCollaborators;
	
	for($i = 0; $i < @clusters; $i++){
		$c1 = $clusters[$i];
		next if !$c1;
		
		for($j = 0; $j < @clusters; $j++){
			next if $j == $i;
			$c2 = $clusters[$j];
			next if !$c2;
			
			$areCollaborators = 0;
			
	CHECK_IF_COLLAB:
			for $author1(@$c1){
				for $author2(@$c2){
					if( $name2coauthors{$author1}{$author2} ){
						$areCollaborators = 1;
						last CHECK_IF_COLLAB;
					}
				}
			}
			
			if($areCollaborators){
				push @$c1, @$c2;
				$clusters[$j] = undef;
			}
		}
	}
	
	return @clusters;
}

# agglomerative($K, $clustThres, \%context, \&calcConceptVectorSimi, 
#				\&titleSetToVector, \&dumpTitleset, \&dumpSimiTuple, \@clusters1)
sub agglomerative($$$$$$$$)
{
	my $K = shift;		# number of expected clusters
	my $DT = shift;		# distance threshold for clustering
	my $context = shift;
	my $simiGauge = shift;	# call-back function to calculate the distance of two objects/clusters
	my $vectorizer = shift; # call-back function to vectorize each cluster. the vectors will be cached
							# to avoid repeated computation
	my $clusterDumper = shift; # call-back function to dump the two clusters which are to be merged
	my $simiTupleDumper = shift; # call-back function to dump the simi tuple from two clusters

	my @clusters = copyRefArray( shift );	# deep copy, avoid modifying @_
	my $nextNo = 1;
	my @clustVecs = map { &$vectorizer($context, $nextNo++, $_) } @clusters;
	my @clustNos  = ( 1 .. scalar @clusters );
	my @clusterSizes = map { scalar @$_ } @clusters;

	my $useUnigram = $context->{useUnigram};
	
#	my %obj2cid;
#	my ($c, $c2);

#	my $updateCid = sub($$){
#						my @objs = @{$_[0]};
#						my $cid = $_[1];
#						my $obj;
#						for $obj(@objs){
#							$obj2cid{$obj} = $cid;
#						}
#					};
#
#	my $cid = 1;
#	for $c(@clusters){
#		&$updateCid($c, $cid++);
#	}

	my ($p, $q);

	my $simi;
	my $simiTuple;

	my ($i, $j);
	my $k = @clusters;

	# a big enough number to pass the condition in the first round of the loop below
	my $maxsimi = 1000;
	my $maxSimiTuple;

	my $startTime = time;

	while($maxsimi >= $DT && $k > $K){
		print $tee "K: $k\n";

		$maxsimi = 0;
		for($i = 0; $i < @clusters; $i++){
			for($j = $i + 1; $j < @clusters; $j++){
				print "\r$i $j      \r";

				$simiTuple = &$simiGauge($context, $clustNos[$i], $clustVecs[$i], $clusters[$i],
											$clustNos[$j], $clustVecs[$j], $clusters[$j]);
				$simi = $simiTuple->[0];
				
				# $ICSum < $ICSumThres
				if($simiTuple->[1] < $simiTuple->[2]){
					next;
				}
				
				if($simi > $maxsimi){
					$maxsimi = $simi;
					$maxSimiTuple = $simiTuple;
					($p, $q) = ($i, $j);
				}
			}
		}
		print "\n";

		if($maxsimi >= $DT){
#			&$updateCid($clusters[$q], $p + 1);
			my $no1 = $clustNos[$p];
			my $no2 = $clustNos[$q];
			my $s1 = $clusterSizes[$p];
			my $s2 = $clusterSizes[$q];
			my $s3 = $s1 + $s2;

			$maxsimi = trunc(3, $maxsimi);

			print $tee "Max similar value: $maxsimi. Merge clusters $no1($s1) and $no2($s2) to $nextNo($s3).\n";
			&$clusterDumper($context, $no1, $clusters[$p], $clustVecs[$p]);
			&$clusterDumper($context, $no2, $clusters[$q], $clustVecs[$q]);
			&$simiTupleDumper($maxSimiTuple, $useUnigram);

			push @{$clusters[$p]}, @{$clusters[$q]};

			# update clustVecs & clustNos
			$clustVecs[$p] = &$vectorizer($context, $nextNo, $clusters[$p]);
			$clustNos[$p]  = $nextNo++;
			$clusterSizes[$p] = $s3;
			splice @clusters,  		$q, 1;
			splice @clustVecs, 		$q, 1;
			splice @clustNos,  		$q, 1;
			splice @clusterSizes, 	$q, 1;
			$k--;
		}
	}

	my $usedTime = time - $startTime;
	print $tee "Clustering stops at: ", hhmmss(time, ":"), ". Used time: ", time2hms($usedTime), "\n";

	if( $k > $K && $maxsimi > 0 ){
		my $no1 = $clustNos[$p];
		my $no2 = $clustNos[$q];
		my $s1 = $clusterSizes[$p];
		my $s2 = $clusterSizes[$q];

		$maxsimi = trunc(5, $maxsimi);

		print $tee "Max similar value: $maxsimi. Clusters $no1($s1) and $no2($s2) not merged.\n";
		&$clusterDumper($context, $no1, $clusters[$p], $clustVecs[$p]);
		&$clusterDumper($context, $no2, $clusters[$q], $clustVecs[$q]);
		&$simiTupleDumper($maxSimiTuple, $useUnigram);
	}

	return (\@clusters, \@clustVecs, \@clustNos);
}

sub dumpPubCluster($$$$)
{
	my ($no, $cluster, $pubset, $gIdentities) = @_;
	
	my $size = @$cluster;
	
	print $LOG "Cluster $no: $size\n";
	
	if( @$cluster > 5){
		map { dumpPub($LOG, $pubset->[$_], $gIdentities) } @{ $cluster }[ 0 .. 4 ];
		print $LOG "...... (", scalar @$cluster - 5, " more)\n";
	}
	else{
		map { dumpPub($LOG, $pubset->[$_], $gIdentities) } @$cluster;
	}
	print $LOG "\n";
}

# cluster numbers in $oldclusters are usualy from 1 to n. not the pub ID in the caller script
sub mergeSharingCoauthor($$$)
{
	# $name is not used in this sub
	my ($origClusters, $title_Coauthors, $context) = @_;

	my $name = $context->{focusName};

	my @clusters = copyRefArray($origClusters);	# deep copy, avoid modifying $origClusters
	my @clusterNames = map { unionArrayToHashRef( @$title_Coauthors[@$_] ) } @clusters;
	my @sharedAuthors;

	my ($i, $j);

	print $tee "Merge pubs of '$name' according to same co-authors...\n";

	for($i = 0; $i < @clusters; $i++){
		next if !$clusters[$i];

		for($j = 0; $j < @clusters; $j++){
			next if $i == $j || !$clusters[$j];

			@sharedAuthors = intersectHash($clusterNames[$i], $clusterNames[$j]);
			if(@sharedAuthors >= 2){
				push @{$clusters[$i]}, @{$clusters[$j]};
				$clusters[$j] = undef;
				$clusterNames[$i] = unionHashToHashRef($clusterNames[$i], $clusterNames[$j]);
				$clusterNames[$j] = undef;
				$i--;
				last;
			}
		}
	}
	
	@clusters = grep { defined } @clusters;
	print $tee "Done. Get ", scalar @clusters, " clusters\n";
	
	return @clusters;
}

sub seedMergeSharingCoauthor($$$$)
{
	my ($ionClusters, $seedClusters, $title_Coauthors, $context) = @_;

	my $name = $context->{focusName};
	my $pubset = $context->{pubset};
	my $gIdentities = $context->{gIdentities};
	
	# ion means it's dissociated from any group (seed cluster). so it needs to join a seed cluster
	my @ions 	= copyRefArray($ionClusters);	# deep copy, avoid modifying $ionClusters
	my @seeds	= copyRefArray($seedClusters);	# deep copy, avoid modifying $seedClusters

	my %isPubInSeeds = map { map { $_ => 1 } @$_ } @seeds;
	my $ionCluster;
	my @ionCluster;

	for $ionCluster(@ions){
		@ionCluster = grep { ! exists $isPubInSeeds{$_} } @$ionCluster;
		# some clusters are empty ([]). we couldn't set them to undef now.
		# otherwise @ionNames = ... will go wrong. We set them to undef after getting @ionNames
		$ionCluster = [ @ionCluster ];
	}

	my @ionNames 	= map { unionArrayToHashRef( @$title_Coauthors[@$_] ) } @ions;
	my @seedNames	= map { unionArrayToHashRef( @$title_Coauthors[@$_] ) } @seeds;

	for $ionCluster(@ions){
		# set empty clusters to undef
		if(! @$ionCluster){
			$ionCluster = undef;
		}
	}

	my @sharedAuthors;

	my ($i, $j);

	my $maxsimi;
	my %closestPairs;
	my ($ion, $candSeeds, $seed, $chosenSeed);

	my $mergeCount = 0;

	my $progresser = makeProgresser( vars => [ \$mergeCount, \$maxsimi ], step => 1 );

	print $tee "Seed merge pubs of '$name' according to same co-authors...\n";

	do{
		$maxsimi = 0;
		%closestPairs = ();

		for($i = 0; $i < @ions; $i++){
			next if !$ions[$i] || !@{ $ions[$i] };

			for($j = 0; $j < @seeds; $j++){
				@sharedAuthors = intersectHash($ionNames[$i], $seedNames[$j]);
				if(@sharedAuthors > $maxsimi){
					%closestPairs = ( $i => [ $j ] );
					$maxsimi = @sharedAuthors;
				}
				elsif(@sharedAuthors == $maxsimi){
					push @{ $closestPairs{$i} }, $j;
				}
			}
		}

		if($maxsimi > 1){
			while( ($ion, $candSeeds) = each %closestPairs ){
				# conflict. needs human to tell the program which cluster $ion to join
				if( @$candSeeds > 1 ){
					print STDERR "\n\n";
					print STDERR "Cluster $ion:\n";
					map { dumpPub(\*STDERR, $pubset->[$_], $gIdentities) } @{ $ions[$ion] };
					print STDERR "has $maxsimi shared coauthors with ", scalar @$candSeeds,
									" seed clusters.\n\n";

					for $seed(@$candSeeds){
						@sharedAuthors = intersectHash($ionNames[$ion], $seedNames[$seed]);
						print STDERR "Seed cluster $seed (", join(", ", @sharedAuthors), "):\n";

						if(@{ $seeds[$seed] } > 5){
							map { dumpPub(\*STDERR, $pubset->[$_], $gIdentities) } @{ $seeds[$seed] }[ 0 .. 4 ];
							print STDERR "...... (", scalar @{ $seeds[$seed] } - 5, " more)\n";
						}
						else{
							map { dumpPub(\*STDERR, $pubset->[$_], $gIdentities) } @{ $seeds[$seed] };
						}
						print STDERR "\n";
					}
		CHOOSE_SEED:
					print STDERR "Choose a seed cluster to merge: ";
					$chosenSeed = <STDIN>;
					trim($chosenSeed);
					if($chosenSeed =~ /\D/ || 0 == grep { $_ == $chosenSeed } @$candSeeds){
						goto CHOOSE_SEED;
					}
				}
				else{
					$chosenSeed = $candSeeds->[0];
				}
				last;
			}

			$mergeCount += @{$ions[$ion]};
			push @{ $seeds[$chosenSeed] }, @{$ions[$ion]};
			$ions[$ion] = undef;
			$seedNames[$chosenSeed] = unionHashToHashRef($ionNames[$ion], $seedNames[$chosenSeed]);
			$ionNames[$ion] = undef;
		}

		&$progresser();

	}while($maxsimi > 1);
	print STDERR "\n";

	my $ionCount = sum( map { scalar @$_ } grep { defined } @ions );

	print $tee "$mergeCount ion pubs merged to seeds, $ionCount left\n";
	print $tee "Merge remaining ion pubs without seeds...\n";

	my @clusters = mergeSharingCoauthor($name, [ grep { defined } @ions ], $title_Coauthors);

	@clusters = grep { defined } @clusters;

	print $tee "Done. Get ", scalar @clusters, " clusters\n";

	return (@clusters, @seeds);
}

sub overestimateAmbig($)
{
	my $name = $_[0];
	
	if(! exists $chnNameAmbig{$name}){
		return 0;
	}
	
	my $ambig = $chnNameAmbig{$name};
	
	if($ambig > 200){
		return atLeast1( $ambig, 1 );
	}
	
	if($ambig > 50){
		$ambig *= $BIG_AMBIG_EST_BOOST;
	}
	else{
		$ambig *= $SMALL_AMBIG_EST_BOOST;
	}
	return atLeast1( $ambig, 1 );
}

# the chance that two clusters belong to different authors if they share a coauthor $coauthorName
sub coauthorEvidenceError($$)
{
	my ($authorName, $coauthorName) = @_;
	die "Coauthor stat file hasn't been loaded\n" if !$coauthorStatLoaded;
	
	if( ! exists $chnNameAmbig{$authorName} ){
		return 0;
	}
	
	# if ! exists $cnCoauthorCount{$coauthorName}, $authorName must be a western name.
	# otherwise at least $authorName is $coauthorName's Chinese coauthor
	# actually this condition should never be satisfied, 
	# cuz in clust.pl probMergeSharingCoauthor won't be done on a western focus name
	# Likewise for $authorName
	if( ! exists $cnCoauthorCount{$authorName} || ! exists $cnCoauthorCount{$coauthorName} ){
		return 0;
	}
	
	my ($authorAmbig, $coauthorAmbig);
	my ( $error1, $error2 );
	
	# $authorAmbig / $ambigSumTotal is the prob of drawing a different author with name $authorName
	# in one sampling. we have about $cnCoauthorCount{$coauthorName} samplings, so the prob
	# that $coauthorName having a diff coauthor with $authorName is
	# ... * ... / ... 
	# The following "/2" is that, without extra info (assuming uniform distro), we assume that 
	# when drawing two papers from two authors with $authorName, there's 1/2 prob that the two papers 
	# are still by the same author
	
	$authorAmbig = overestimateAmbig($authorName);
	
	$error1 = ( $cnCoauthorCount{$coauthorName} + 1 ) * $authorAmbig / $ambigSumTotal / 2;

	# if $coauthorName is not Chinese, such as "Philip S. Yu", we assume it has no ambiguity
	# and $error2 = 0
	$coauthorAmbig = overestimateAmbig($coauthorName);

	# the error brought by the ambiguity of the coauthor. Refer to coauthorEvidenceThresToCoauthorAmbiguityThres()
	$error2 = ( $cnCoauthorCount{$authorName} + 1 ) * $coauthorAmbig / $ambigSumTotal / 2;
	
	return max($error1, $error2);
}

# calc the threshold of the count of its Chinese coauthors a shared coauthor need, 
# to be a strong coauthor w.r.t $authorName
sub coauthorEvidenceThresToCnCountThres($$)
{
	my ($authorName, $errorThres) = @_;
	
	my $authorAmbig = overestimateAmbig( $authorName );
	
	# "2" here has the same reason as in coauthorEvidenceError()
	my $cnCoauthorCountThres = $errorThres * 2 * $ambigSumTotal / $authorAmbig - 1;
	return $cnCoauthorCountThres;
}

# it's the "dual" of coauthorEvidenceThresToCnCountThres()
# test how likely $authorName chooses two coauthors with the same name
# Rationale: different coauthors always collaborate with different namesakes
# so the coauthor ambiguity needs to be below certain threshold
# it's motivated by the bad case of "tao peng" (ambiguous coauthor name "wei wang")
sub coauthorEvidenceThresToCoauthorAmbiguityThres($$)
{
	my ($authorName, $errorThres) = @_;

	# this condition should never be met. same reason as in the comment in coauthorEvidenceError()
	if( !$cnCoauthorCount{$authorName} ){
		return 0;
	}
	
	my $focusAuthorCnCoauthorCount = $cnCoauthorCount{$authorName} + 1;
	
	# "2" here has the same reason as in coauthorEvidenceError()
	my $coauthorAmbigThres = $errorThres * 2 * $ambigSumTotal / $focusAuthorCnCoauthorCount;
	return $coauthorAmbigThres;
}

sub probMergeSharingCoauthor($$$$$)
{
	my ($origClusters, $title_Coauthors, $errorTolerance, $sameMnOddsThres, $context) = @_;

	my $name = $context->{focusName};
	my $pubset = $context->{pubset};
	my $gIdentities = $context->{gIdentities};

	my @clusters		= copyRefArray($origClusters);	# deep copy, avoid modifying $origClusters
	my @clusterNames	= map { unionArrayToHashRef( @$title_Coauthors[@$_] ) } @clusters;

	my $clusterName;
	for $clusterName(@clusterNames){
		delete $clusterName->{$name};
	}
	
	my @sharedCoauthors;
	my ($i, $j, $ij);
	my $minError;
	my %errors;
	my @authorClusters;
	my $authorCluster;
	my $mergeable;
	my $mergeReason;
	
	print $tee "Probabilistically merge pubs of '$name' according to same co-authors...\n";
	
	my $cnCoauthorCountThres = coauthorEvidenceThresToCnCountThres($name, $errorTolerance);
	my $coauthorAmbiguityThres = coauthorEvidenceThresToCoauthorAmbiguityThres($name, $errorTolerance);
	( $cnCoauthorCountThres, $coauthorAmbiguityThres ) = trunc(3, $cnCoauthorCountThres, $coauthorAmbiguityThres);
	print $tee "Evidential coauthor's Chinese coauthor count threshold: $cnCoauthorCountThres\n";
	print $tee "Coauthor's ambiguity threshold (for the overestimated ambiguity): $coauthorAmbiguityThres\n";

	# filter less-collaborateive coauthors. Remained coauthors are used for likelihood ratio test
	my $coauthorFilter = sub{ if( ! exists $cnCoauthorCount{$_[0]} ){
								# print STDERR "Warn: '$_[0]' doesn't exist in \%cnCoauthorCount or \%chnNameAmbig\n";
								return 1;
							  }
							  else{
								  return $cnCoauthorCount{$_[0]} <= $cnCoauthorCountThres
								  		   						 &&
								  		overestimateAmbig($_[0]) <= $coauthorAmbiguityThres
								  ;
							  }
						 };
						 
	for($i = 0; $i < @clusters; $i++){
		next if !$clusters[$i];

		for($j = 0; $j < @clusters; $j++){
			next if $i == $j || !$clusters[$j];

			$mergeable = 0;
			
			@sharedCoauthors = intersectHash($clusterNames[$i], $clusterNames[$j]);
			
			# if the shared authors of one author is a subset of (or equals) the other author
			# treat them as the same person
			if( @sharedCoauthors > 0 &&
				( @sharedCoauthors == keys %{$clusterNames[$i]} 
							   	   ||
				  @sharedCoauthors == keys %{$clusterNames[$j]} )
			){
				$mergeable = 1;
				$mergeReason = "Coauthors of one cluster are contained by another cluster";
			}
			else{
				if(@sharedCoauthors >= 1){
					if( 0 < grep { $_ eq "qing li" } @sharedCoauthors ){
						my $debugbreak = 1;
					}
					%errors = map { $_ => coauthorEvidenceError($name, $_) } @sharedCoauthors;
					$minError = min( values %errors );
					if( $minError <= $errorTolerance ){
						$mergeable = 1;
						
						my ($coauthor, $minCoauthor);
						for $coauthor(@sharedCoauthors){
							if($errors{$coauthor} == $minError){
								$minCoauthor = $coauthor;
								last;
							}
						}
						$mergeReason = "Coauthor $minCoauthor has error $minError";
					}
					else{
						my (%clusterNames1, %clusterNames2);
						
						if($FILTER_STRONGEVI_COAUTHORS_B4_CSLR){
							%clusterNames1 = filterHash( $clusterNames[$i], $coauthorFilter );
							%clusterNames2 = filterHash( $clusterNames[$j], $coauthorFilter );
							# if too few coauthors are left, then don't filter strong evidential coauthors
							if(keys %clusterNames1 <= 2){
								%clusterNames1 = %{$clusterNames[$i]};
							}
							if(keys %clusterNames2 <= 2){
								%clusterNames2 = %{$clusterNames[$j]};
							}
						}
						else{
							%clusterNames1 = %{$clusterNames[$i]};
							%clusterNames2 = %{$clusterNames[$j]};
						}
						
						if(keys %clusterNames1 > 1 && keys %clusterNames2 > 1){
							my $odds;
							if( $USE_CSLR_VERSION == 1 ){
								$odds =  isSameCategorical($CAT_PRIOR, 0, $CAT_PRIOR, 0.5, 
											\%clusterNames1, \%clusterNames2, undef, 0, 4);
							}
							else{
								$odds =  isSameCategorical2($CAT_PRIOR, 0, $CAT_PRIOR, $CSLR_COAUTHOR_UNSEEN_REDUCTION_FRAC, 
											\%clusterNames1, \%clusterNames2, undef, 0, 4);
							}
							
							if($odds >= $sameMnOddsThres){
								$mergeable = 1;
								
								my $sizei = @{ $clusters[$i] };
								my $sizej = @{ $clusters[$j] };
								$mergeReason = "Clusters $i($sizei) & $j($sizej): odds ratio $odds";
								print $LOG dumpSortedHash(\%clusterNames1, undef, undef), "\n";
								print $LOG dumpSortedHash(\%clusterNames2, undef, undef), "\n";
							}
						}
					}
				}
			}
#				else{
#					@authorClusters = clusterAuthors(@sharedCoauthors);
#					@authorClusters = grep { defined } @authorClusters;
#					if(@authorClusters > 1){
#						$minError = 1;
#						for $authorCluster(@authorClusters){
#							$minError *= min ( map { $errors{$_} } @$authorCluster );
#						}
#						if( $minError <= $errorTolerance ){
#							push @{$clusters[$i]}, @{$clusters[$j]};
#							$clusters[$j] = undef;
#							$clusterNames[$i] = unionHashToHashRef($clusterNames[$i], $clusterNames[$j]);
#							$clusterNames[$j] = undef;
#							$i--;
#							last;
#						}
#					}
#				}
			if( $mergeable ){
				if($DEBUG & DBG_PROB_MERGE_BY_COAUTHOR){
					print $LOG "$mergeReason\n\n";
					dumpPubCluster( $i, $clusters[$i], $pubset, $gIdentities );
					dumpPubCluster( $j, $clusters[$j], $pubset, $gIdentities );
				}
				
				push @{$clusters[$i]}, @{$clusters[$j]};
				$clusters[$j] = undef;
				$clusterNames[$i] = unionHashToHashRef($clusterNames[$i], $clusterNames[$j]);
				$clusterNames[$j] = undef;
				$i--;
				
				last;
			}
			
		}
	}

	@clusters = grep { defined } @clusters;
	print $tee "Done. Get ", scalar @clusters, " clusters\n";
	
	return @clusters;
}

sub jaccardMergeSharingCoauthor($$$$)
{
	my ($origClusters, $title_Coauthors, $simiThres, $context) = @_;

	my $name = $context->{focusName};
	my $pubset = $context->{pubset};
	my $gIdentities = $context->{gIdentities};

	my @clusters		= copyRefArray($origClusters);	# deep copy, avoid modifying $origClusters
	my @clusterNames	= map { unionArrayToHashRef( @$title_Coauthors[@$_] ) } @clusters;

	my $clusterName;
	
	# delete the focus author from coauthor lists
	for $clusterName(@clusterNames){
		delete $clusterName->{$name};
	}
	
	my @sharedCoauthors;
	my ($i, $j, $ij);
	my $minError;
	my %errors;
	my @authorClusters;
	my $authorCluster;
	my $mergeable;
	my $mergeReason;
	
	print $tee "Merge pubs of '$name' by co-authors using Jaccard similarity, thres $simiThres...\n";
							 
	for($i = 0; $i < @clusters; $i++){
		next if !$clusters[$i];

		for($j = 0; $j < @clusters; $j++){
			next if $i == $j || !$clusters[$j];

			$mergeable = 0;
			
			@sharedCoauthors = intersectHash($clusterNames[$i], $clusterNames[$j]);
			
			if(@sharedCoauthors >= 1){					
				my $simi = jaccard( $clusterNames[$i], $clusterNames[$j], 0.0001, 0 );
				if($simi >= $simiThres){
					$mergeable = 1;
					
					my $sizei = @{ $clusters[$i] };
					my $sizej = @{ $clusters[$j] };
					$mergeReason = "Clusters $i($sizei) & $j($sizej): simi $simi";
					print $LOG dumpSortedHash($clusterNames[$i], undef, undef), "\n";
					print $LOG dumpSortedHash($clusterNames[$j], undef, undef), "\n";
				}
			}
			if( $mergeable ){
				if($DEBUG & DBG_PROB_MERGE_BY_COAUTHOR){
					print $LOG "$mergeReason\n\n";
					dumpPubCluster( $i, $clusters[$i], $pubset, $gIdentities );
					dumpPubCluster( $j, $clusters[$j], $pubset, $gIdentities );
				}
				
				push @{$clusters[$i]}, @{$clusters[$j]};
				$clusters[$j] = undef;
				$clusterNames[$i] = unionHashToHashRef($clusterNames[$i], $clusterNames[$j]);
				$clusterNames[$j] = undef;
				$i--;
				
				last;
			}
		}
	}

	@clusters = grep { defined } @clusters;
	print $tee "Done. Get ", scalar @clusters, " clusters\n";
	
	return @clusters;
}

sub saveCache
{
	my ($filename, $pCache, $valuedumper) = @_;
	my $x;

	my @domain = sort { $a cmp $b } keys %{$pCache};
	if(@domain == 0){
		warn "'$nameof{$pCache}' is empty, no need to save\n";
		return;
	}

	my $FH;
	$filename = getAvailName($filename);
	print $tee "Open '$filename' to save '$nameof{$pCache}'...\n";
	open_or_die($FH, "> $filename");

	for $x(@domain){
		print $FH join("\t", $x, &$valuedumper($pCache->{$x})), "\n";
	}

	close($FH);
	print $tee scalar @domain, " entries saved\n";
}

sub loadCache
{
	my ($filename, $pCache, $loader) = @_;

	print $tee "Open '$filename' to load '$nameof{$pCache}'...\n";

	my $FH;
	if(!open_or_warn($FH, "< $filename")){
		return;
	}

	my $entrycount = 0;

	my $progresser = makeProgresser( vars => [ \$., \$entrycount ] );

	while(<$FH>){
		trim($_);
		next if !$_ || /^#/;

		if( &$loader(split /\t/) ){
			$entrycount++;
		}

		&$progresser();
	}
	print $tee "$entrycount entries in $. lines loaded from '$filename'. ", scalar keys %{$pCache},
			" entries in '$nameof{$pCache}'\n";
}

sub playsound
{
	if($^O eq "MSWin32"){
		Win32::Sound::Play( $_[0] || 'SystemAsterisk');
	}
}

END
{
	if($morphPID){
		print $tee "\n'morpha' called $morphCallCount times\n";

		if(kill(9, $morphPID) == 1){
			print $tee "'morpha' killed\n";
		}
	}

	if($LEMMA_CACHE_SAVE_FILENAME || $morphCallCount > 100000){
		$LEMMA_CACHE_SAVE_FILENAME ||= "lemma-cache.txt";
		saveCache($LEMMA_CACHE_SAVE_FILENAME, \%lemmaLookup, sub{ return @{ $lemmaCache[$_[0]] } });
	}

	if(! $QUIET_EXIT){
		$endTime = time;
		print $tee "\nExit at ", hhmmss($endTime, ':'), ", ", $endTime - $startTime, " secs elapsed\n";
	}
}

1;


=pod

sub stem
{
	my @results;
	my $w2;

	for(@_){
		if(exists $stemCache{$_}){
			push @results, $stemCache{$_};
		}
		else{
			$w2 = $stemmer->stem($_);
			push @{$invStemTable{$w2}}, $_;
			$stemCache{$_} = $w2;
			push @results, $w2;
		}
	}

	return arrayOrFirst(wantarray, \@results);
}

sub stemPhrase
{
	my $w;
	my @ws;
	my @results;

	for(@_){
		@ws = split /\s+/, $_;
		@ws = removeStopWords(\@ws);
		@ws = stem(@ws);
		push @results, join(" ", @ws);
	}

	return arrayOrFirst(wantarray, \@results);
}

sub recoverStem($)
{
	$pRecoverStem->($_[0]);
}

=cut
