use feature qw(switch say);
use strict;
use warnings 'all';
use Getopt::Std;
use IO::Tee;

use constant{
	OPTIONS 					=> 'y:d2',
	namedisDir 					=> "/media/tough/namedis",
	wikipediaDir 				=> "/media/first/wikipedia",
};

use lib namedisDir;
use NLPUtil;
use Distinct;

use lib wikipediaDir;
use ConceptNet;

use Getopt::Std;

my %opt;
getopts(OPTIONS, \%opt);

my @selClusters;
my @affiliations;

my $minyear = 0;
my $maxyear = 2100;

if(exists $opt{'y'}){
	my $yearThres = $opt{'y'};
	if($yearThres =~ /(\d{4})-(\d{4})/){
		$minyear = $1;
		$maxyear = $2;
		print $tee "Only publications with year between $yearThres will be considered\n";
	}
	else{
		$maxyear = $yearThres;
		print $tee "Only publications with year <= $maxyear will be considered\n";
	}
}

my $outDistinct = 0;
if(exists $opt{'d'}){
	$outDistinct = 1;
}

my $leastSize2 = 0;
if(exists $opt{'2'}){
	$leastSize2 = 1;
}

if(@ARGV < 1){
	die "Usage: $0 my-label-file\n"
}

loadChosenConfs("original/distinct-venues0.txt");
loadGroundtruth($ARGV[0]);
	
sub loadDBLPFile
{
	my ($DBFilename, $selKeys) = @_;
	
	my $pubkey;
	my $pub;
	my $clustNo;
	my $selcount = 0;
	
	print STDERR "Open DBLP data file '$DBFilename' to process...\n";

	my $DB;
	if(! open_or_warn($DB, "< $DBFilename")){
		return;
	}
	
	my $totalPubCount = 0;
	
	while(1){
		$pub = parseCleanDBLP($DB);

		last if !$pub;
		
		$pubkey = lc( $pub->pubkey );
		
		if(exists $selKeys->{$pubkey}){
			$clustNo = $selKeys->{$pubkey};
						
			delete $selKeys->{$pubkey};
			push @{$selClusters[$clustNo]}, $pub;
			
			$selcount++;
		}
		
		$totalPubCount++;
	}

	print STDERR "$totalPubCount publications loaded, $selcount selected, ", 
					scalar keys %$selKeys, " left unmatched\n";

}

sub loadGroundtruth
{
	my ($truthFilename) = @_;
	
	print STDERR "Open groundtruth file '$truthFilename' to process...\n";

	my $DB;
	if(! open_or_warn($DB, "< $truthFilename")){
		return;
	}
	
	my %affiliations;
	my @affiliations;
	
	my $expectClusterHeading = 1;
	my $line;
	my ($clustID, $clustSize, $identity);
	my $authorID;
	
	$clustSize = 0;
	my $readcount = 0;
	
	my $title;
	my $year;
	my $venue;
	my $pubkey;
	my $authorLine;
	my $yearVenueLine;
	my $thisPublication;
	my @authorNames;

	my $totalPubCount = 0;
	my $selcount = 0;
	my @selPubs;
	
	my %clusters;
	
	my $heading;
	my $clustNo = 0;
	my $firstMappedKey;
	
	while(!eof($DB)){
		$line = <$DB>;
		trim($line);
		if(!$line){
			if($readcount != $clustSize){
				print STDERR "$.: Cluster size $clustSize != $readcount (read count)\nStop reading the file.\n";
				return 0;
			}
			$readcount = 0;

			$expectClusterHeading = 1;
			
			if(@selPubs > 0){
				my $clustSN = $affiliations{$identity};
				push @{$selClusters[$clustSN]}, @selPubs;
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
				if($identity =~ m{^N/A}){
					$identity = undef;
				}
				else{
					$identity =~ tr/()/[]/;
					if( ! exists $affiliations{$identity} ){
						$affiliations{$identity} = $clustNo;
						$clustNo++;
						push @affiliations, $identity;
					}
				}
				
				$heading = $line;
				$expectClusterHeading = 0;
				
				@selPubs = ();
				next;
			}
			else{
				print STDERR "$.: Unknown cluster heading:\n$line\nStop reading the file.\n";
				return 0;
			}
		}
		
		$title = $line;
		$authorLine = <$DB>;
		$yearVenueLine = <$DB>;
		
		$totalPubCount++;
		
		trim($authorLine, $yearVenueLine);
		
		$thisPublication = parseDBLPBlock($title, $authorLine, $yearVenueLine);
		
		$readcount++;
		
		$title = $thisPublication->title;
		trimPunc($title);
		
		$year  = $thisPublication->year;
		$venue = $thisPublication->venue;
		
		if($identity && $year <= $maxyear && $year >= $minyear && $chosenConfs2{$venue}){
			push @selPubs, $thisPublication;
			$selcount++;
		}
	}
	
	print STDERR "$totalPubCount publications loaded, $selcount selected\n";

	if($outDistinct){
		print "\n\n\n";
	}else{
		print scalar @selClusters, " clusters.\n\n";
	}
	
	my $outClustSN = 0;
	my $clustSN = 0;
	
	for($clustSN = 0; $clustSN < @selClusters; $clustSN++){
		next if !$selClusters[$clustSN];
		my @selPubs = @{ $selClusters[$clustSN] };
		if(@selPubs == 0){
			next;
		}
		if($leastSize2 && @selPubs < 2){
			next;
		}
		
		$identity = $affiliations[$clustSN];
		
		if($outDistinct){
			print "Cluster $outClustSN, ", scalar @selPubs, " tuples ($identity)\n";
			for $thisPublication(@selPubs){
				dumpPub2( \*STDOUT, $thisPublication, 1 );
			}
		}
		else{
			 # Cluster 0, 16 tuples (University of Delaware)
			print "Cluster $outClustSN, ", scalar @selPubs, " papers:\t$identity\n";
			for $thisPublication(@selPubs){
				dumpPub2( \*STDOUT, $thisPublication );
			}
		}
		print "\n";
		$outClustSN++;
	}

	print STDERR "$outClustSN clusters dumped\n";

}
