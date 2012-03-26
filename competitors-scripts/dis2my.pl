use feature qw(switch say);
use strict;
use warnings 'all';
use Getopt::Std;
use IO::Tee;

use constant{
	OPTIONS 					=> 'c:a:i:',
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
getopts("m:", \%opt);

my @selClusters;
my @affiliations;

# datamap.txt
# the map from a distinct file name to my label file name
if(exists $opt{'m'}){
	my $MAP;
	open_or_die($MAP, "< $opt{'m'}");
	
	my $line;
	while($line = <$MAP>){
		trim($line);
		next if !$line;
		
		my @filenames = split /\t/, $line;
		dis2my(@filenames, "original/$filenames[1]");
	}
	exit;
}

if(@ARGV < 3){
	die "Usage: $0 distinct-file my-label-file new-label-file\n"
}

dis2my(@ARGV);

sub dis2my
{
	if(@_ < 3){
		die "Usage: $0 distinct-file my-label-file new-label-file"
	}
	
	@selClusters = ();
	@affiliations = ();
	
	my $distinctFilename = shift @_;
	my $newLabelFilename = pop @_;
	
	my $selKeys = loadDistinctFile($distinctFilename, \@affiliations);
	
	# process groundtruth files first
	for(@_){
		if(/-labels\.txt/){
			loadGroundtruth($_, $selKeys);
		}
	}
	for(@_){
		if(! /-labels\.txt/){
			loadDBLPFile($_, $selKeys);
		}
	}
	
	if(scalar keys %$selKeys){
		print STDERR "Unmatched:\n";
		for( sort { $selKeys->{$a} cmp $selKeys->{$b} } keys %$selKeys ){
			print STDERR "$_\t=>$affiliations[$selKeys->{$_}]\n";
		}
	}
	
	my @nonEmptyClusters = grep { $_ && @$_ > 0 } @selClusters;
	print STDERR scalar @nonEmptyClusters, " clusters.\n";
	
	my $OUT;
	
	print STDERR "Open output file '$newLabelFilename'...\n";
	
	if(! open_or_warn($OUT, "> $newLabelFilename")){
		return;
	}
	
	print $OUT scalar @nonEmptyClusters, " clusters.\n\n";
	
	my $outClustSN = 0;
	my $clustSN = 0;
	
	my $identity;
	my $thisPublication;
	
	for($clustSN = 0; $clustSN < @selClusters; $clustSN++){
		next if !$selClusters[$clustSN];

		my @selPubs = @{ $selClusters[$clustSN] };
		if(@selPubs == 0){
			next;
		}
		
		$identity = $affiliations[$clustSN];
		
			 # Cluster 0, 16 tuples (University of Delaware)
		print $OUT "Cluster $outClustSN, ", scalar @selPubs, " papers:\t$identity\n";
		for $thisPublication(@selPubs){
			dumpPub2( $OUT, $thisPublication );
		}
		print $OUT "\n";
		$outClustSN++;
	}
	
	print STDERR "$outClustSN clusters written to '$newLabelFilename'.\n\n";

}

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
	my ($truthFilename, $selKeys) = @_;
	
	print STDERR "Open groundtruth file '$truthFilename' to process...\n";

	my $DB;
	if(! open_or_warn($DB, "< $truthFilename")){
		return;
	}
			
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
	my $firstMappedClustNo;
	
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
				push @{$selClusters[$clustNo]}, @selPubs;
			}
			
			$firstMappedClustNo = -1;
			$firstMappedKey = "";
			
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
				}
				
				$heading = $line;
				$expectClusterHeading = 0;
				
				$clustNo++;
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
		$pubkey = lc( $thisPublication->pubkey );
		
		if(exists $selKeys->{$pubkey}){
			$clustNo = $selKeys->{$pubkey};
			
			if( $firstMappedClustNo < 0 ){
				$firstMappedClustNo = $clustNo;
				$firstMappedKey = $pubkey;
			}
			else{
				if($firstMappedClustNo != $clustNo){
					die "$firstMappedKey -> '$affiliations[$firstMappedClustNo]', but $pubkey -> '$affiliations[$clustNo]'";
				}
			}
			
			delete $selKeys->{$pubkey};
			push @selPubs, $thisPublication;
			
			$selcount++;
		}
	}
	
	print STDERR "$totalPubCount publications loaded, $selcount selected, ", 
					scalar keys %$selKeys, " left unmatched\n";
	
}
