use lib '.';
use NLPUtil;
use warnings;
use strict;

die "Specify a label file please\n" if @ARGV == 0;
loadGroundtruth($ARGV[0]);

sub loadGroundtruth
{
	my $truthFilename = shift;
	print STDERR "Open groundtruth file '$truthFilename' to process...\n";
	my $iniAuthorName = $truthFilename;
	$iniAuthorName =~ s/(-\w+)?\.txt//;
	$iniAuthorName = lc($iniAuthorName);
	
	my $DB;
	if(! open($DB, "< $truthFilename")){
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
	my $readClustCount = 0;
	
	my %coauthors = ();
	
	while(!eof($DB)){
		$line = <$DB>;
		trim($line);
		if(!$line){
			if($readcount != $clustSize){
				print "$.: Cluster size $clustSize != $readcount (read count)\nStop reading the file.\n";
				return 0;
			}
			$readcount = 0;

			$expectClusterHeading = 1;
			
			my @coauthors = sort { $coauthors{$b} <=> $coauthors{$a} } keys %coauthors;
			
			if($readClustCount > 1){
				print join "\t", map { "$_: $coauthors{$_}" } @coauthors;
				print "\n";
			}
			
			$readClustCount++;
			
			%coauthors = ();
			next;
		}
		
		if($. == 1 && $line =~ /^\d+ clusters\.$/){
#			print $OUT $line, "\n";
			next;
		}
		
		if($expectClusterHeading){
			if($line =~ /Cluster (\d+), (\d+) papers:(\s+(.+))?$/){
				$clustID = $1;
				$clustSize = $2;
				$identity = $4;
				
				$expectClusterHeading = 0;
				
#				print $line, "\n";
				next;
			}
			else{
				print "$.: Unknown cluster heading:\n$line\nStop reading the file.\n";
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
		for(@{$thisPublication->authors}){
			next if $_ eq $iniAuthorName;
			$coauthors{$_}++;
		}
	}
	
	print STDERR "$readClustCount clusters read\n";
}

