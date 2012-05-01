# check which venues in the labeled file are not chosen by DISTINCT's criterion
use strict;

use Getopt::Std;

use constant{
	OPTIONS 					=> 'p:',
	namedisDir 					=> "/media/tough/namedis",
	wikipediaDir 				=> "/media/first/wikipedia",
};

use lib namedisDir;
use NLPUtil;
use Distinct;

use lib wikipediaDir;
use ConceptNet;

my %opt;
getopts(OPTIONS, \%opt);

my $dirPrefix = "";
if(exists $opt{'p'}){
	$dirPrefix = $opt{'p'};
	if( $dirPrefix !~ /\/$/ ){
		$dirPrefix .= "/";
	}
	print STDERR "Data file path prefix: '$dirPrefix'\n";
}

if(@ARGV != 1){
	die "Usage: $0 labeled-file\n";
}

loadChosenConfs("${dirPrefix}distinct-venues0.txt");
loadGroundtruth($ARGV[0]);

sub loadGroundtruth
{
	my $truthFilename = shift;
	print $tee "Open groundtruth file '$truthFilename' to process...\n";

	my $DB;
	if(! open_or_warn($DB, "< $truthFilename")){
		return;
	}
	
	my $outFilename;
	
	$truthFilename =~ /(.+)-labels\.txt/;
	my $authorName = $1;
	$authorName =~ s/ //g;
	$outFilename = "labels_$authorName.dat";
	
	my $expectClusterHeading = 1;
	my $line;
	my ($clustID, $clustSize, $identity);
	my $authorID;
	
	$clustSize = 0;
	my $readcount = 0;
	
	my $title;
	my $year;
	my $venue;
	my $authorLine;
	my $yearVenueLine;
	my $thisPublication;
	my @authorNames;

	my $alignedCount = 0;
	my $unalignedCount = 0;
	my $totalPubCount = 0;
	my $unidentifiedCount = 0;
	
	my %clusters;
	
	while(!eof($DB)){
		$line = <$DB>;
		trim($line);
		if(!$line){
			if($readcount != $clustSize){
				print $tee "$.: Cluster size $clustSize != $readcount (read count)\nStop reading the file.\n";
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
				if($identity =~ m{^N/A}){
					$identity = undef;
				}
				else{
					$identity =~ tr/()/[]/;
				}
				
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
		
		$totalPubCount++;
		
		trim($authorLine, $yearVenueLine);
		
		$thisPublication = parseDBLPBlock($title, $authorLine, $yearVenueLine);
		
		$readcount++;
		
		$title = $thisPublication->title;
		trimPunc($title);
		
		$year  = $thisPublication->year;
		$venue = $thisPublication->venue;

		$authorLine = join(",", @{$thisPublication->authors} );
		
		if(! $chosenConfs2{$venue}){
			print "$venue\n";
		}
	}
}
