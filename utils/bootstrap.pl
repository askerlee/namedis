use strict;
use warnings 'all';
use lib '.';
use NLPUtil;

if(@ARGV != 2){
	die "Usage: $0 data_file test_file...\n";
}

my ($file, $testfile) = @ARGV[0 .. 1];

my @illegalPress = ("White House", "the House", "News Publishing");

map { $stopwords{$_} = 1 } @illegalPress;

delete $stopwords{the};
delete $stopwords{of};
my $stoppat = "\\b(" . join("|", sort keys %stopwords) . ")\\b";

my @pats = (qr/(?:published by) ([^,;:()\d]+?)([,;()\d]| - |ISBN)/i,
				 qr/[,;:()]\s*((\w+\s)+(Press|press|House|Publishing|Publisher|Publishers))\b/
			); #@ARGV[ 2 .. $#ARGV ];

my $DATA;
open_or_die($DATA, "< $file");

my $line;
my %terms;
my $term;
my $pat;

while($line = <$DATA>){
	if($. % 1000 == 0){
		print STDERR "\r$.\r";
	}
		
	for $pat(@pats){
		if($line =~ /$pat/){
			$term = $1;
			if($term =~ /$stoppat/i){
				next;
			}
			trimPunc($term);
			$terms{$term}++;
			last;
		}
	}
}
print STDERR "\r$.\n";

my @terms = sort keys %terms;
print scalar @terms, " terms found:\n";
print join("\n", @terms), "\n";

my @userTerms = ("Elsevier");

unshift @terms, @userTerms;
print "User terms:\n", join(", ", @userTerms), "\n\n";

#my $allmatchlc = 0;
#map { $allmatchlc += $terms{$_} } keys %terms;
#
#print "$allmatchlc line matches\n";
#
#for $term(sort { $terms{$b} <=> $terms{$a} } keys %terms){
#	print "$term => $terms{$term}\n";
#}
#print "\n";

close($DATA);

open_or_die($DATA, "< $testfile");

my $matched;
my $matchedLineCount = 0;

my @unmatchedLines;
my @multimatchedLines;

my %matchCount;

my $jointpat = join("|", reverse @terms);

while($line = <$DATA>){
	if($. % 1000 == 0){
		print STDERR "\r$.\r";
	}
	
	$matched = 0;
	
	if($line =~ /(?:[,.;]|published by|Published by)\s*($jointpat)/){
		print substr($line, $-[1]);
		print "\n";
		$matched++;
		$matchCount{$1}++;
	}
	
	if($matched == 0){
		push @unmatchedLines, $line;
		next;
	}
	$matchedLineCount++;
	if($matched > 1){
		push @multimatchedLines, $line;
	}
}
print STDERR "\r$.\n";

print STDERR "$matchedLineCount lines are matched\n\n";

for $term(sort { $matchCount{$b} <=> $matchCount{$a} } keys %matchCount){
	print "$term => $matchCount{$term}\n";
}
#print STDERR "\n";

if(@multimatchedLines > 0){
	print STDERR scalar @unmatchedLines, " multi-matched lines.\n";
#	print join("", @multimatchedLines);
}

if(@unmatchedLines > 0){
	print STDERR scalar @unmatchedLines, " unmatched lines.\n";
#	print join("", @unmatchedLines);
}
