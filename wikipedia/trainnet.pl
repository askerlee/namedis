use feature qw(switch say);

use strict;
use warnings 'all';
#use lib '/media/tough/namedis';
#use lib 'c:/lsh/namedis';

use lib '.';
use ConceptNet;

use Getopt::Std;

use constant{
	OPTIONS => 'c:C:a:A:Um:i:',
	namedisPath => '/media/tough/namedis'
};

use lib namedisPath;
use NLPUtil;

my $LEMMA_CACHE_LOAD_FILENAME;
my $LEMMA_CACHE_SAVE_FILENAME;
my $ANCESTORS_LOAD_FILENAME;
my $ANCESTORS_SAVE_FILENAME;
my $IC_FILE_NAME;
my $USE_FREQ_PASSUP_ATTENUATION = 1;
my $MAX_LOAD_EDGE_COUNT;
my $processedOptionCount = 0;

my %opt;
getopts(OPTIONS, \%opt);

openLogfile();

if(exists $opt{'c'}){
	$LEMMA_CACHE_LOAD_FILENAME = $opt{'c'};
	if(! -e $LEMMA_CACHE_LOAD_FILENAME){
		die "FATAL  lemma cache file '$LEMMA_CACHE_LOAD_FILENAME' doesn't exist, please check\n";
	}
	print $tee "Will load lemma cache from file '$LEMMA_CACHE_LOAD_FILENAME'\n";
	$processedOptionCount++;
}
if(exists $opt{'C'}){
	$LEMMA_CACHE_SAVE_FILENAME = $opt{'C'};
	print $tee "Will save lemma cache to file '$LEMMA_CACHE_SAVE_FILENAME'\n";
	$processedOptionCount++;
}
if(exists $opt{'a'}){
	$ANCESTORS_LOAD_FILENAME = $opt{'a'};
	if(! -e $ANCESTORS_LOAD_FILENAME){
		die "FATAL  lemma cache file '$ANCESTORS_LOAD_FILENAME' doesn't exist, please check\n";
	}
	print $tee "Will load ancestor lists from file '$ANCESTORS_LOAD_FILENAME'\n";
	$processedOptionCount++;
}
if(exists $opt{'A'}){
	$ANCESTORS_SAVE_FILENAME = $opt{'A'};
	print $tee "Will save ancestor lists into file '$ANCESTORS_SAVE_FILENAME'\n";
	$processedOptionCount++;
}
if(exists $opt{'U'}){
	$USE_FREQ_PASSUP_ATTENUATION = 0;
	print $tee "Frequency passup attenuation is disabled\n";
}
if(exists $opt{'m'}){
	$MAX_LOAD_EDGE_COUNT = $opt{'u'};
	
	if($MAX_LOAD_EDGE_COUNT){
		print $tee "<= $MAX_LOAD_EDGE_COUNT edges will be read from the ontology file\n";
	}
}
if(exists $opt{'i'}){
	$IC_FILE_NAME = $opt{'i'};
	if(! -e $IC_FILE_NAME){
		die "FATAL  IC file '$IC_FILE_NAME' doesn't exist, please check\n";
	}
	print $tee "Will load IC file '$IC_FILE_NAME'\n";
	$processedOptionCount++;
}

NLPUtil::initialize(lemmaCacheLoadFile => $LEMMA_CACHE_LOAD_FILENAME, 
					   lemmaCacheSaveFile => $LEMMA_CACHE_SAVE_FILENAME
				   );

my $DEBUG = ConceptNet::DBG_CALC_MATCH_WEIGHT 
								| 
					 ConceptNet::DBG_MATCH_TITLE 
					 			| 
					 ConceptNet::DBG_TRACK_ADD_FREQ
					 			|
					 ConceptNet::DBG_ADD_EDGE
					 			|
					 ConceptNet::DBG_CHECK_ROOT_ANCESTOR
					 			|
					 ConceptNet::DBG_TRAVERSE_NET
					 			|
					 ConceptNet::DBG_LOAD_ANCESTORS		
					 			|
					 ConceptNet::DBG_CHECK_INHERIT_DEPTH_RATIO
					 			|
					 ConceptNet::DBG_LOAD_IC
					 			|
					 ConceptNet::DBG_CALC_SIMI		
					 			|
					 ConceptNet::DBG_BUILD_INDEX												
			#		 			|
			#		 ConceptNet::DBG_TRAVERSE_NET_LOW_OP								
					;

ConceptNet::setDebug($DEBUG, $LOG, $tee);

my @treeRoots = ("computer science", "computer engineering", "Electromagnetism", "Mathematics", "Linguistics");

ConceptNet::initialize( taxonomyFile => "./csmathling-full.txt",
						M => $MAX_LOAD_EDGE_COUNT, 
						#taxonomyFile => "c:/wikipedia/csmathling-full.txt", 
						rootterms => \@treeRoots, 
						ancestorsLoadFile => $ANCESTORS_LOAD_FILENAME, 
					   	ancestorsSaveFile => $ANCESTORS_SAVE_FILENAME,
					   	newTermMode => ConceptNet::NEWTERM_COMPLEX,
					   	doAncestorExpansion => 1,
					   	useFreqPassupAttenuation => $USE_FREQ_PASSUP_ATTENUATION,
					  );

initPostingCache();

if(! $IC_FILE_NAME){
	trainDBLPFile(namedisPath . "/dblp.extracted.txt", 0.3);
	saveNetIC(filename => "ic.txt");
}
else{
	loadNetIC(filename => $IC_FILE_NAME);
}

cmdline( rootterms => \@treeRoots, dumpFilename => "csmathling-full.txt" );
