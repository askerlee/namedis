# generate "csmathling.txt"
use feature qw(switch say);

use strict;
use warnings 'all';

use IO::Handle;
use lib '/media/tough/namedis';
use NLPUtil;

use lib '.';
use ConceptNet;

my ($child, $parent);

my @travTree;

my @treeRoots = ("computer science", "computer engineering", "Electromagnetism", "Mathematics", "Linguistics");

openLogfile();
NLPUtil::initialize( lemmaCacheLoadFile => "lemma-cache.txt" );
ConceptNet::iniLists();

my $progresser = makeProgresser(vars => [ \$. ]);
my $conceptNetSize = \$ConceptNet::sizeof{\@conceptNet};

open_or_die(IN, "< catcat.txt");

print STDERR "Reading 'catcat.txt'...\n";

while(<IN>){
	&$progresser();

#	last if $. > 500000;
	trim($_);
	
	($child, $parent) = split /\t/;
	
	addEdge(\@conceptNet, $child, $parent, 0);
}

print STDERR "\r$. lines read\n";
print STDERR "$$conceptNetSize edges between ", $termGID - 1, " words added\n";

my $oldEdgeCount = $$conceptNetSize;
my $redir;

my $xcatFilename;
my $doesOutToXcat = 0;

if(! -e "xcat.txt"){
	$xcatFilename = "extended.txt";
	open_or_die(XCAT2, "> xcat.txt");
	$doesOutToXcat = 1;
}
else{
	$xcatFilename = "xcat.txt";
}

excludeX(@excludedX);
exclude(@excluded);
	
open_or_die(XCAT, "< $xcatFilename");

print STDERR "Reading '$xcatFilename'...\n";

my $isExtended;

while(<XCAT>){
	&$progresser();

	next if /^#/;
	
	trim($_);
	
	($child, $parent, $redir) = split /\t/;
	
	$isExtended = !$redir;
	
	if(getTermID($parent) == -1){
		next;
	}
	
	if(!$redir){
		next if isExcluded($parent) || isExcludedX($parent);
		
		my $spaceCount = $child =~ tr/ / /;
		
		# discard all extended single-word terms. too noisy :(
		next if $spaceCount == 0;
		
		next if $spaceCount == 1 && $child =~ / \d{1,2}$/;
	}
	
	if(addEdge(\@conceptNet, $child, $parent, $isExtended)){
		if($doesOutToXcat){
			print XCAT2 $_, "\n";
		}
	}
}

print STDERR "\r$. lines read\n";
print STDERR $$conceptNetSize - $oldEdgeCount, " edges between ", $termGID - 1, " terms added\n";

close(XCAT);
#close(XCAT2);

setDebug(ConceptNet::DBG_CALC_MATCH_WEIGHT 
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
#		 			|
#		 ConceptNet::DBG_TRAVERSE_NET_LOW_OP								
		);

exclude(@excluded);
exclude4whitelist(\%whitelist);

dumpChildren( rootterms => \@treeRoots, dumpFilename => "csmathling.txt" );

cmdline(rootterms => \@treeRoots, dumpFilename => "csmathling.txt");
