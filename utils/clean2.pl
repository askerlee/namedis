use strict;
use warnings 'all';
use lib '.';
use NLPUtil;

open_or_die(DB, "< dblp.extracted.txt");
open_or_die(DB2, "> dblp-e2.txt");

loadPublishers();

our $recordStartLn;
our $gRecordCount = 0;

my ($title, $authorline, $yearline);
my $oldtitle;
my ($matchedLineCount, $unmatchedLineCount);

sub progress
{
	print STDERR "\r$gRecordCount\t$recordStartLn\r";
}

while(!eof(DB)){
	$recordStartLn = $. + 1;
	$title = <DB>;
	$authorline = <DB>;
	$yearline = <DB>;
	<DB>;
	
	$oldtitle = $title;
	$title = removePublisher($title);
	
	print DB2 $title, "\n", $authorline, $yearline, "\n";
	
	if(length($title) + 4 < length($oldtitle)){
		if($oldtitle !~ /\Q$title\E/){
			die "\nmismatch:\n$oldtitle\n$title\n";
		}
		print "<div>";
		if($-[0] > 0){
			print "<span style='color:red'>", substr($oldtitle, 0, $-[0]), "</span>\n";
		}
		print "<span style='color:black'>", $title, "</span>\n";
		if($+[0] < length($oldtitle)){
			print "<span style='color:red'>", substr($oldtitle, $+[0]), "</span>\n";
		}
		print "</div>";
		
		$matchedLineCount++;
	}
	else{
		$unmatchedLineCount++;
		#push @unmatchedLines, $line;
	}

	if($gRecordCount % 10000 == 0){
			progress();
	}
	$gRecordCount++;
}

progress();
print STDERR "\n";
print "$matchedLineCount matched, $unmatchedLineCount unmatched\n";
