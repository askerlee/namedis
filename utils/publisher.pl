use strict;
use warnings 'all';
use lib '.';
use NLPUtil;

my $DATA;
open_or_die($DATA, "< kluwer.txt");

my @DATA = ("Book Review: Mobile Robotics - A Practical Introduction, 2nd Edition, By Ulrich Nehmzow.");
my $line;
my $term;

my ($matchedLineCount, $unmatchedLineCount);

loadPublishers();

while($line = <$DATA>){
	if($. % 1000 == 0){
		print STDERR "\r$.\r";
	}
	chomp $line;
	
	my $oldline = $line;
	$line = removePublisher($line);
	if(length($line) + 4 < length($oldline)){
		if($oldline !~ /\Q$line\E/){
			die "\nmismatch:\n$oldline\n$line\n";
		}
		print "<div>";
		if($-[0] > 0){
			print "<span style='color:red'>", substr($oldline, 0, $-[0]), "</span>\n";
		}
		print "<span style='color:black'>", $line, "</span>\n";
		if($+[0] < length($oldline)){
			print "<span style='color:red'>", substr($oldline, $+[0]), "</span>\n";
		}
		print "</div>";
		
		$matchedLineCount++;
	}
	else{
		$unmatchedLineCount++;
		#push @unmatchedLines, $line;
	}
}
print STDERR "\r$.\n";

print STDERR "$matchedLineCount matched, $unmatchedLineCount unmatched\n";
