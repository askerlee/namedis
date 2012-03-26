use strict;
use lib '.';
use NLPUtil;
use Getopt::Std;

$| = 1;

my $file = "dblp.extracted.txt";

open_or_die(DB, "< $file");

my $thispub;

my %gNames;
my $name;
my @authorNames;
my $match;
my @terms = ("agent", "data mining", "research", "survey", "case study", 
				"svm", "kernel", "prototype", "system", "algorithm",
				"computer", "approach", "method", "optimization", "information");
				
my $termRE = buildOrRE('\b', @terms, '\b');
my $term;
my $M = INT_MAX;

my %opt;
getopts("p:", \%opt);

if(exists $opt{'p'}){
	$M = $opt{'p'};
	if($M =~ /[^0-9]/){
		die "FATAL  maximum publications '$M' is not understood\n";
	}
	print "No more than $M publications will be processed\n";
}

initialize( progressDelim => "\t", progressVars => [ qw($gRecordCount $recordStartLn) ], 
			maxRecords => $M ); 

while(!eof(DB)){
	$thispub = parseCleanDBLP(DB);
#	print $thispub->title, "\n";
	@authorNames = @{$thispub->authors};
	if(@authorNames > 3){
		$#authorNames = 2;
	}
	for $name(@authorNames){
		$gNames{$name}{all}++;
	}
			
	while($thispub->title =~ /($termRE)/ig){
		$match = 1;
		$term = lc($1);
		for $name(@authorNames){
			$gNames{$name}{$term}++;
		}
	}
}

progress2();
summary();

sub summary
{
	print "\n";
	
	my @pubsize;
	my @pubfullsize;
	my $max;
	my $prob;
	
	my $timetag = hhmmss($startTime);
	
	for $term(@terms){
		@pubsize = ();
		$max = 0;
		
		for(keys %gNames){
			if($gNames{$_}{$term} < 3){
				next;
			}
#			$prob = int( 100 * $gNames{$_}{$term} / $gNames{$_}{all} + 0.5 );
#			if($prob == 1000){
#				print STDERR "$term: $_\n";
#			}
			$pubsize[ $gNames{$_}{$term} ]++;
			$pubfullsize[ $gNames{$_}{$term} ] += $gNames{$_}{all};
			if($gNames{$_}{$term} > $max) { $max = $gNames{$_}{$term}; }
		}
		
		my $i;
		open_or_die(DISTRO, "> distro/$term-$timetag.txt");
		print STDERR "Dumping the distro of titles having '$term'...";
		
		for($i = 1; $i <= $max; $i++){
			if($pubsize[$i]){
				$prob = int( 100 * $pubsize[$i] / $pubfullsize[$i] + 0.5 );
				print DISTRO "$i\t$pubsize[$i]\t$prob\n";
			}
		}
		close(DISTRO);
		print STDERR " Done.\n";
	}
}
