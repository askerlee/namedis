use strict;
use Class::Struct;

my $startTime;
my $endTime;

$| = 1;

$startTime = time;

if(@ARGV == 0){
    die "Please specify the DBLP file to process\n";
}

my $file = shift;

open(DB, "< $file") || die "Cannot open $file to read: $!\n";

my $pubfile = "pub-by-author-" . hhmmss($startTime) . ".txt";
print "Publications will be saved into '$pubfile'\n";

struct( author => [ publist => '@', pubsize => '$' ] );

my $recordStartLn;
my $title;
my $authorLine;
my @authorNames;
my $pubYear;
my $thisPublication;

my $gRecordCount = 0;
my $gAuthorCount = 0;

our %gAuthors;
our @gPublications;

my @authorSlot;

my $author;

my $i;

while(!eof(DB)){
	$recordStartLn = $. + 1;
	$title = <DB>;
	chomp $title;
	$authorLine = <DB>;
	chomp $authorLine;
	@authorNames = split /,/, $authorLine;
	$pubYear = <DB>;
	($pubYear) = split /\./, $pubYear;
	<DB>;
	
	if($gRecordCount % 10000 == 0){
		progress();
	}
	
	for($i = 1; $i <= @authorNames; $i++){
		$author = $authorNames[$i - 1];
		if(!exists $gAuthors{$author}){
			$gAuthors{$author} = author->new( 
				publist => [ "$pubYear,$i,$gRecordCount" ], pubsize => 1 );
		}
		else{	
			push @{$gAuthors{$author}->publist}, "$pubYear,$i,$gRecordCount";
			$gAuthors{$author}->pubsize( $gAuthors{$author}->pubsize + 1 );
		}	
	}
	
	$gRecordCount++;

	push @gPublications, $title;
}

my $pubsize = scalar @gPublications;
$gAuthorCount = scalar keys %gAuthors;

die "\$gRecordCount != publication count $pubsize" if $gRecordCount != $pubsize;

progress();
	
dumpPubs();

END{
	$endTime = time;
	print "\nExit at ", hhmmss($endTime, ':'), ", ", $endTime - $startTime, " secs elapsed\n";
}

sub abort
{
	$SIG{INT} = sub{ exit };
	progress();
	print "\n\nInterrupted by Ctrl-C";
	dumpPubs();
	exit;
}

sub progress
{
	print "\r$gRecordCount\t$recordStartLn\r";
}

sub dumpPubs
{
	print "\n\n";
	
	print "$gAuthorCount author-names\n";
	
	print "Separating author-names by their prolificacy... ";
	
	my $author;
	my $pubsize;
	my $maxpubsize = 0;
	
	for $author(keys %gAuthors){
		$pubsize = $gAuthors{$author}->pubsize;
		if($maxpubsize < $pubsize){
			$maxpubsize = $pubsize;
		}
		push @{$authorSlot[$pubsize]}, $author;
	}
	print "Done.\n";
	
	print "Sorting each author-names slot...\n";

	my $i;
	
	for($i = $maxpubsize; $i--; $i > 0){
		next if !$authorSlot[$i];
		
		print "\r$i\r";
		
		@{$authorSlot[$i]} = sort @{$authorSlot[$i]};
	}
	
	print "\nDone.\n";
								
	my $publist;
	my $pub;
	my ($authorOrder, $year, $pubID);
	my ($ai, $pi);
	my @pubs;
	
	print "Dumping $gAuthorCount authors into '$pubfile'...\n";

	open(PUBLIST, "> $pubfile") || die "Cannot open '$pubfile' to write: $!\n";
	
	$ai = 0;
	$pi = 0;
	
	for($i = $maxpubsize; $i > 0; $i--){
		next if !$authorSlot[$i];

		for $author(@{$authorSlot[$i]}){
			$publist = $gAuthors{$author}->publist;
			$ai++;
#			if($ai % 1000 == 0){
#				print "\r$i\t$ai\t$pi\r";
#			}
				
			print PUBLIST "$author: ", scalar @{$publist}, "\n";
			@pubs = ();
			for $pub(@{$publist}){
				($year, $authorOrder, $pubID) = split /,/, $pub;
				push @pubs, "$year, $authorOrder, $gPublications[$pubID]\n";
				$pi++;
			}
			@pubs = sort @pubs;
			
			print PUBLIST @pubs;
			print PUBLIST "\n";
		}
#		if($i <= 10){
			print "\r$i\t$ai\t$pi\n";
#		}
	}
		
	print "Done.\n";
}
	
sub hhmmss
{
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(shift);
    my $delim = shift;
    return sprintf "%d$delim%02d$delim%02d", $hour, $min, $sec;
}
