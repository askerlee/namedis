use strict;
use Lingua::Stem::Snowball;
use IO::Tee;
#use IO::File;
use Devel::Size qw(size total_size);
use List::Util qw(max);

$| = 1;

my $stemmer = Lingua::Stem::Snowball->new( lang => 'en' );
our %stemCache;
our %invStemTable;

my $startTime;
my $endTime;

$startTime = time;

if(@ARGV == 0){
    die "Please specify the DBLP file to process\n";
}

my $file = shift;
my ($origname) = $file =~ /(.+?)(\.extracted(-\d+)?)?\.[^.]+$/;
my $fileSuffix = hhmmss($startTime);
my $invstemfile = "invstem-$origname-$fileSuffix.csv";
my $authorpubfile = "authorpub-$origname-$fileSuffix.csv";

open(DB, "< $file") || die "Cannot open $file to read: $!\n";

print "Processing starts at ", hhmmss($startTime, ':'), "\n";

my %authorPubs;

my $recordStartLn;
my $title;
my $authorLine;
my @authorNames;
my $pubYear;
my $thisPublication;

my @gPublications;

my $gRecordCount = 0;
my $weirdTitleCount = 0;

$SIG{INT} = \&abort;

while(!eof(DB)){
	$recordStartLn = $. + 1;
	$title = <DB>;
	chomp $title;
	$authorLine = <DB>;
	chomp $authorLine;
	@authorNames = split /,/, $authorLine;
	$pubYear = <DB>;
	chomp $pubYear;
	<DB>;
	
	if($gRecordCount % 10000 == 0){
		progress();
	}
	
	push @gPublications, $title;

	arriveTitle($title, $pubYear, \@authorNames);
	
	$gRecordCount++;
}

progress();

dumpInvStem();
dumpAuthorpubs();

END{
	$endTime = time;
	print "\nExit at ", hhmmss($endTime, ':'), ", ", $endTime - $startTime, " secs elapsed\n";
}

sub abort
{
	$SIG{INT} = sub{ exit };
	progress();
	print "\n\nInterrupted by Ctrl-C";
	dumpInvStem();
	dumpAuthorpubs();
	exit;
}

sub progress
{
	print "\r$gRecordCount\t$recordStartLn\r";
}

sub arriveTitle
{
	my ($title, $year, $authorNames) = @_;

	my ($w, $w2);
	while($title =~ /\b([a-zA-Z]+)\b/g){
		$w = $1;
		if($w !~ /[a-z]/){
			next;
		}
		if($w =~ /^[A-Z][a-z]*$/){
			$w = lc(substr($w,0,1)) . substr($w,1);
		}
			
		if(exists $stemCache{$w}){
			$w2 = $stemCache{$w};
		}
		else{
			$w2 = $stemmer->stem($w);
		}
		$invStemTable{$w2}{$w}++;
	}
	
	my $a;
	for $a(@{$authorNames}){
		push @{$authorPubs{$a}}, $gRecordCount;
	}
}

sub dumpInvStem
{
	my @words = sort { $a cmp $b } keys %invStemTable;
	my $stemCount = @words;
	
	print "\n";
	
	print "Dump the inverse stem table of $stemCount words into '$invstemfile'...\n";
	open(INVSTEM, "> $invstemfile") || die "Cannot open '$invstemfile' to write: $!\n";
	my ($w, $w2);
	my @originals;
	
	my $origCount = 0;
	
	$stemCount = 0;
	for $w(@words){
		@originals = sort { $invStemTable{$w}{$b} <=> $invStemTable{$w}{$a} 
												   ||
											    $a cmp $b
						  } keys %{$invStemTable{$w}};
		print INVSTEM $w, ",", join(",", map { "$invStemTable{$w}{$_}-$_" } @originals), "\n";
		$stemCount++;
		$origCount += @originals;
		if($stemCount % 1000 == 0){
			print "\r$stemCount\t$origCount\r";
		}	
	}
	print "\r$stemCount\t$origCount\n";
	print "Done.";
	if($stemCount > 0){
		print " ", trunc(3, $origCount / $stemCount), " originals each word in average";
	}
	print "\n";
}

sub dumpAuthorpubs
{
	my @authors = sort { @{$authorPubs{$b}} <=> @{$authorPubs{$a}} 
											 ||
										  $a cmp $b
						} keys %authorPubs;
	my $authorCount = @authors;
	
	print "\n";
	
	print "Dump the publication of $authorCount authors into '$authorpubfile'...\n";
	open(AUTHORPUB, "> $authorpubfile") || die "Cannot open '$authorpubfile' to write: $!\n";
	
	my $pubCount = 0;
	my $a;
	
	$authorCount = 0;
	my $pubsize;
	for $a(@authors){
		$pubsize = @{$authorPubs{$a}};
		print AUTHORPUB "$a,$pubsize,", join(",", @{$authorPubs{$a}}), "\n";
		$authorCount++;
		$pubCount += $pubsize;
		if($authorCount % 1000 == 0){
			print "\r$authorCount\t$pubCount\r";
		}	
	}
	print "\r$authorCount\t$pubCount\n";
	print "Done.";
	if($authorCount > 0){
		print " ", trunc(3, $pubCount / $authorCount), " publications each author in average";
	}
	print "\n";
}

sub hhmmss
{
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(shift);
    my $delim = shift;
    return sprintf "%d$delim%02d$delim%02d", $hour, $min, $sec;
}

sub trunc
{
	my $prec = shift;
	if(@_ == 1){
		return sprintf("%.${prec}f", $_[0]);
	}
	for(@_){
		$_ = sprintf("%.${prec}f", $_);
	}
}
