# the earlier test data doesn't include journal names. 
# This script is to align the newer unlabeled data with the labeled data
use feature qw(switch say);
use strict;
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

if(@ARGV < 2){
	die "Usage: $0 reference-file labeled-file\n"
}

loadDBFile($ARGV[0]);
loadGroundtruth($ARGV[1]);
	
sub loadGroundtruth
{
	my $truthFilename = shift;
	print $tee "Open groundtruth file '$truthFilename' to process...\n";

	my $DB;
	if(! open_or_warn($DB, "< $truthFilename")){
		return;
	}
	
	my $outFilename;
	
	$outFilename = getAvailName( $truthFilename );
	
	my $OUT;
	
	print $tee "Open output file '$outFilename'...\n";
	
	if(! open_or_warn($OUT, "> $outFilename")){
		return;
	}
	
	my $expectClusterHeading = 1;
	my $line;
	my ($clustID, $clustSize, $identity);
	my $authorID;
	
	my $clustSN = 0;
	
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
			
			print $OUT "\n";
			next;
		}
		
		if($. == 1 && $line =~ /^\d+ clusters\.$/){
			print $OUT $line, "\n";
			next;
		}
		
		if($expectClusterHeading){
			if($line =~ /Cluster (\d+), (\d+) papers:(\s+(.+))?$/){
				$clustID = $1;
				$clustSize = $2;
				$identity = $4;
				
				$expectClusterHeading = 0;
				
				print $OUT $line, "\n";
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
		
		$authorLine = join( ",", @{$thisPublication->authors} );
		
		if($venue && $titleVenue2key{"$year-$title-$venue"}){
			$thisPublication->pubkey( $titleVenue2key{"$year-$title-$venue"}{pubkey} );
			$alignedCount++;
			delete $titleVenue2key{"$year-$title-$venue"};
			
			dumpPub2($OUT, $thisPublication);
		}
		elsif($titleAuthor2venueKey{"$year-$title-$authorLine"}){
			$thisPublication->venue( $titleAuthor2venueKey{"$year-$title-$authorLine"}{venue} );
			$thisPublication->pubkey( $titleAuthor2venueKey{"$year-$title-$authorLine"}{pubkey} );
			$alignedCount++;
			delete $titleAuthor2venueKey{"$year-$title-$authorLine"};
			
			dumpPub2($OUT, $thisPublication);
		}
		else{
			print $tee "Not aligned: $title\n";
			$unalignedCount++;
		}
	}
	
	print $tee "$totalPubCount publications loaded, $alignedCount aligned, $unalignedCount not aligned\n";
	
	if($unalignedCount){
		if(keys %titleAuthor2venueKey == $unalignedCount){
			print $tee scalar keys %titleAuthor2venueKey, " papers in the reference file, but not aligned:\n";
			print $tee join("\n", keys %titleAuthor2venueKey), "\n";
		}
		elsif(keys %titleVenue2key == $unalignedCount){
			print $tee scalar keys %titleVenue2key, " papers in the reference file, but not aligned:\n";
			print $tee join("\n", keys %titleVenue2key), "\n";
		}
		else{
			print $tee "Weird: both \%titleAuthor2venueKey and \%titleVenue2key have some papers deleted\n";
		}
	}
}
