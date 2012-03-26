# measure the accuracy of ambiguity estimation for sampled author names
# with '-p', it uses the ambiguityPredict() formula to estimate the ambiguity, instead of linear regression
# with '-b', it generates the batch file for clust.pl

use warnings 'all';
use strict;
use lib '.';

use NLPUtil;
use Distinct;

use Statistics::Regression;
use Time::HiRes qw(gettimeofday);
use List::Util qw(max min);
use Getopt::Std;

use constant{
	OPTIONS => 'Pbxp:'
};

my %opt;
getopts(OPTIONS, \%opt);

my $usePredefinedPredictor = 0;
if($opt{'P'}){
	$usePredefinedPredictor = 1;
}
my $generateBatchfile = 0;
my $generateLatexTable = 0;

if($opt{'b'}){
	$generateBatchfile = 1;
}
if($opt{'x'}){
	if(@ARGV == 0){
		die "ambiguity file is needed to output latex table\n";
	}
	$generateLatexTable = 1;
}

my $dirPrefix = "";
if(exists $opt{'p'}){
	$dirPrefix = $opt{'p'};
	if( $dirPrefix !~ /\/$/ ){
		$dirPrefix .= "/";
	}
	print STDERR "Data file path prefix: '$dirPrefix'\n";
}

my %trainset = map { $_ => 1 } @distinctNames;
my @names = (@distinctNames); #, @tjNames);
my %names = map { $_ => 1 } @names;

my $name;			
my $LABELS;

my $line;
my $innerClusterOffset = -1;

my %affiliFreq;
my $affiliation;
my $affiliation2;

my %authorStat;

$authorStat{'total'}{clustCnt} = 0;
$authorStat{'total'}{solo} = 0;
$authorStat{'total'}{pubcount} = 0;
$authorStat{'total'}{affiliCount} = 0;
$authorStat{'total'}{ratio} = 0;
$authorStat{'total'}{dummy} = 1;  

#my $AMBIG_COAUTHOR_CLUST_JOINT_PROB_MIX = 0.3;

my ($s, $usec) = gettimeofday();
srand($usec);

my $reg = Statistics::Regression->new( "Ambiguity Regression", 
			[ 
			#"dummy", 
			"clustCnt", "solo"
			] );

for $name(@names){
	my $labelFilename = "${dirPrefix}$name-labels.txt";
	die "Cannot find '$labelFilename'\n" if !-e $labelFilename;
	open_or_die($LABELS, "< $labelFilename");
	
	$authorStat{$name}{clustCnt} = 0;
	$authorStat{$name}{affiliCount} = 0;
	$authorStat{$name}{solo} = 0;
	$authorStat{$name}{pubcount} = 0;
	
	%affiliFreq = ();
	
	while($line = <$LABELS>){
		trim($line);
		
		if(!$line){
			$innerClusterOffset = -1;
			next;
		}
		
		# Cluster 8, 37 papers:	Australian National University
		if($line =~ /Cluster \d+, \d+ papers:\t(.+)/){
			$affiliation2 = $affiliation = $1;
			trim($affiliation);
			if($affiliation2 ne $affiliation){
				print STDERR "Warn: $labelFilename:$. -- extra space in the affiliation\n";
			}
			if($affiliation =~ m{^N/A}){
				$innerClusterOffset = -1;
				next;
			}
			$affiliFreq{$affiliation}++;
			$authorStat{$name}{clustCnt}++;
			$innerClusterOffset = 0;
			next;
		}
		
		if($innerClusterOffset >= 0){
			$innerClusterOffset++;
			if($innerClusterOffset % 3 == 2){
				if($line !~ /,/){
					$authorStat{$name}{solo}++;
				}
				$authorStat{$name}{pubcount}++;
			}
		}
	}
	
	$authorStat{$name}{clustCnt} -= $authorStat{$name}{solo};
	$authorStat{$name}{affiliCount} = keys %affiliFreq;
	$authorStat{$name}{ratio} = trunc(2, $authorStat{$name}{affiliCount} / $authorStat{$name}{pubcount});
	$authorStat{$name}{clustFrac} = trunc(2, $authorStat{$name}{clustCnt} / $authorStat{$name}{pubcount});
	$authorStat{$name}{soloFrac} =  trunc(2, $authorStat{$name}{solo} / $authorStat{$name}{pubcount});

	$authorStat{$name}{dummy} = 1;
	
#	if( rand(12) <= 12 ){
	if($trainset{$name}){
		$reg->include( $authorStat{$name}{affiliCount}, $authorStat{$name} );
		
		$authorStat{$name}{trained} = 1;
	}
	else{
		$authorStat{$name}{trained} = 0;
	}
	
	close($LABELS);			
}

if($generateBatchfile){
	print "#Generated batch file for clustering:\n";
	for $name(@names){
		print join("\t", $name, 0.1, $authorStat{$name}{affiliCount}), "\n";
	}
	exit;
}

if($generateLatexTable){
	goto LOAD_AMBIG;
}

$reg->print();
my $regfunc = linearFunction( [ 
								#"dummy", 
								"clustCnt", "solo"
							  ], $reg->theta() );

print join( "\t", "", "", "Pubs", "Clust", "Solo", "Pred", "Affili", "Ratio" ), "\n";

for $name(@names){
	if($authorStat{$name}{trained}){
		printf "%12.12s", "**$name";
	}
	else{
		printf "%12.12s", $name;
	}
	
	if(! $usePredefinedPredictor){
		$authorStat{$name}{predict} = trunc( 2, &$regfunc($authorStat{$name}) );
	}
	else{
		$authorStat{$name}{predict} = ambiguityPredict( $authorStat{$name}{pubcount}, 
														$authorStat{$name}{clustCnt}, 
														$authorStat{$name}{solo} );
	}
	
	print join( "\t", "", $authorStat{$name}{pubcount}, $authorStat{$name}{clustCnt}, 
				$authorStat{$name}{solo}, $authorStat{$name}{predict}, 
				$authorStat{$name}{affiliCount}, $authorStat{$name}{ratio}
			   ), "\n";
				
	$authorStat{'total'}{clustCnt} += $authorStat{$name}{clustCnt};
	$authorStat{'total'}{solo} += $authorStat{$name}{solo};
	$authorStat{'total'}{pubcount} += $authorStat{$name}{pubcount};
	$authorStat{'total'}{affiliCount} += $authorStat{$name}{affiliCount};
}

$authorStat{'total'}{ratio} = $authorStat{'total'}{affiliCount} / $authorStat{'total'}{pubcount};
$authorStat{'total'}{clustFrac} = trunc( 2, $authorStat{'total'}{clustCnt} / $authorStat{'total'}{pubcount});
$authorStat{'total'}{soloFrac}  = trunc( 2, $authorStat{'total'}{solo} / $authorStat{'total'}{pubcount});

if(! $usePredefinedPredictor){
	$authorStat{'total'}{predict} = trunc( 2, &$regfunc($authorStat{'total'}) );
}
else{
	$authorStat{'total'}{predict} = ambiguityPredict( $authorStat{'total'}{pubcount}, 
													$authorStat{'total'}{clustCnt}, 
													$authorStat{'total'}{solo} );
}

printf "%12.12s", "Total";
print join( "\t", "", $authorStat{'total'}{pubcount}, $authorStat{'total'}{clustCnt}, 
				$authorStat{'total'}{solo}, $authorStat{'total'}{predict}, 
				$authorStat{'total'}{affiliCount}, trunc(2, $authorStat{'total'}{ratio}) ), "\n";

if(@ARGV){
	print "\n";
}

LOAD_AMBIG:

my $ambigFilename;
my $AMBIG;
for $ambigFilename(@ARGV){
	if(! -e $ambigFilename){
		print "Cannot find ambiguity file '$ambigFilename'. Skip\n";
		next;
	}
	if( !open_or_warn($AMBIG, "< $ambigFilename")){
		next;
	}
	
	if( !$generateLatexTable ){
		print "Grep '$ambigFilename'...\n";
	}
	
	my $foundNameCount = 0;
	
	my $reg2 = Statistics::Regression->new( "Ambiguity Regression", 
				[ 
					#"dummy", 
					"clustCnt", "solo", "ambigEst"
				] );

	while($line = <$AMBIG>){
		trim($line);
		my @tuple = split /,/, $line;
		my $N = min(scalar @tuple - 2, 5);
		my $name = $tuple[0];
		
		if( $names{$name} ){
			if( !$generateLatexTable ){
				printf "%12.12s\t", $name;
				print join( "\t", trunc(2, $tuple[2]), trunc(2, @tuple[ $#tuple - $N .. $#tuple ]), 
							$authorStat{$name}{affiliCount} ), "\n";
			}
						
			$authorStat{$name}{ambigEst} = $tuple[2];
			$reg2->include( $authorStat{$name}{affiliCount}, $authorStat{$name} );

			$foundNameCount++;
			if($foundNameCount == @names){
				last;
			}
		}
	}

	if($generateLatexTable){
		for $name(@names){
			printf "  %20.20s\t&\t", cap($name);
			print join( "\t&\t", $authorStat{$name}{pubcount}, $authorStat{$name}{affiliCount}, 
						trunc(2, $authorStat{$name}{ambigEst} || 0) || "n/a" ), "\t\\\\ \\hline\n";
		}
		exit;	
	}

	$reg2->print();
	my $regfunc2 = linearFunction( [ 
										#"dummy", 
									 "clustCnt", "solo", "ambigEst"
								   ], $reg2->theta() );
	
	print join( "\t", "", "", "Pubs", "Clust", "Solo", "amEst", "Pred", "Affili" ), "\n";
	
	$authorStat{'total'}{clustCnt} = 0;
	$authorStat{'total'}{solo} = 0;
	$authorStat{'total'}{pubcount} = 0;
	$authorStat{'total'}{affiliCount} = 0;
	$authorStat{'total'}{ratio} = 0;
	$authorStat{'total'}{dummy} = 1;  
	$authorStat{'total'}{ambigEst} = 0;
	
	for $name(@names){
		if(! $authorStat{$name}{ambigEst}){
			$authorStat{$name}{ambigEst} = 0;
		}
		
		printf "%12.12s", $name;
		print join( "\t", "", $authorStat{$name}{pubcount}, $authorStat{$name}{clustCnt}, 
					$authorStat{$name}{solo}, trunc(2, $authorStat{$name}{ambigEst}), 
					trunc(2, &$regfunc2($authorStat{$name}) ), 
					$authorStat{$name}{affiliCount}, 
					#$authorStat{$name}{ratio}
				   ), "\n";
					
		$authorStat{'total'}{clustCnt} += $authorStat{$name}{clustCnt};
		$authorStat{'total'}{solo} += $authorStat{$name}{solo};
		$authorStat{'total'}{pubcount} += $authorStat{$name}{pubcount};
		$authorStat{'total'}{affiliCount} += $authorStat{$name}{affiliCount};
		$authorStat{'total'}{ambigEst} += $authorStat{$name}{ambigEst};
	}
	
	$authorStat{'total'}{ratio} = $authorStat{'total'}{affiliCount} / $authorStat{'total'}{pubcount};
	
	printf "%12.12s", "Total";
	print join( "\t", "", $authorStat{'total'}{pubcount}, $authorStat{'total'}{clustCnt}, 
					$authorStat{'total'}{solo}, trunc(2, $authorStat{'total'}{ambigEst}), 
					trunc(2, &$regfunc2($authorStat{'total'}) ), 
					$authorStat{'total'}{affiliCount}, 
					#$authorStat{'total'}{ratio} 
				), "\n";
					
	print "\n";
	close($AMBIG);
}

sub ambiguityPredict
{
	my ($pubCount, $clustCount, $soloCount) = @_;
	
	#return -0.0318 * $pubCount + 0.9780 * $clustCount - 1.1065 * $soloCount;
	
	my $ambig = 0.9 * $clustCount - 1.3 * $soloCount;
		
#	if($clustCount > $soloCount){
#		return -0.03 * $pubCount + 0.95 * $clustCount - 1.1 * $soloCount;
#	}
	if($ambig <= 0){
		if($clustCount > 0){
			$ambig = 0.7 * $clustCount;
		}
		else{
			$ambig = $soloCount * 0.5;
		}
	}
	
	return $ambig;
}
