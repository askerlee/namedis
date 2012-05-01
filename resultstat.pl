# find the best & average performance of DISTINCT

use feature qw(switch say);
use strict;
use warnings 'all';
use Getopt::Std;
use List::Util qw(min max sum);
use lib '.';
use NLPUtil;
use Distinct;

use constant{
	OPTIONS => 'ox12ct:p:',
};

my %opt;
getopts(OPTIONS, \%opt);

my $origNameset = 0;
my $myresultOnlyFinal = 0;
my $generateLatexTable = 0;

my @testnames;

if(exists $opt{'o'}){
	print STDERR "Test on the 10 names in the DISTINCT paper only\n";
	$origNameset = 1;
	@testnames = @distinctNames;
}
else{
	print STDERR "Test on all 20 names\n";
	@testnames = (@distinctNames, @tjNames);
}

if(exists $opt{'2'}){
	print STDERR "Only print final (stage 2) result\n\n";
	$myresultOnlyFinal = 1;
}
else{
	print STDERR "Print my final result, as well as the coauthor result\n";
}

my $unifiedDisThres = 1;
if(exists $opt{'c'}){
	$unifiedDisThres = 0;
}

my $onlyStageOne = 0;

if(exists $opt{'1'}){
	if($myresultOnlyFinal){
		die "'1' and '2' cannot be designated at the same time\n";
	}
	print STDERR "Only print the first stage result\n";
	$onlyStageOne = 1;
}

if($opt{'x'}){
	$generateLatexTable = 1;
}

my $selThres = -1;
if($opt{'t'}){
	$selThres = $opt{'t'};
	print STDERR "Summarize at thres $selThres\n";
}

my $distinctResultDir = "distinct-results/";
if(exists $opt{'p'}){
	$distinctResultDir = $opt{'p'};
	if( $distinctResultDir !~ /\/$/ ){
		$distinctResultDir .= "/";
	}
	print STDERR "Distinct result file path: '$distinctResultDir'\n";
}

my @resultFiles = glob("${distinctResultDir}results*.dat");

@resultFiles = schwartzianSort( \@resultFiles, sub{ return $_[0] =~ /(\d+)/; }, 1 );

my $resultFile;
my $RESULT;

my $line;

my %disName2perf;
my %disName2bestPerf;
my %disName2bestAvgPerf;

my ($name, $disPerfRecords, @disPerfRecords, $disPerfRecord);
my ($thres, $accuracy, $precision, $recall, $f1);	# accuracy is useless
my ($k, $v, $n, $maxv, $sumv);
my ($thresholds, @thresholds);
my ($psum, $rsum, $f1sum);
my $namecount;

# DISTINCT results
for $resultFile(@resultFiles){
	print STDERR "Parse '$resultFile'\n";
	open_or_die($RESULT, "< $resultFile");
	
	$thresholds = <$RESULT>;
	trim($thresholds);
	@thresholds = split /\t/, $thresholds;
	shift @thresholds;
	
	($psum, $rsum, $f1sum) = ( 0 ) x 3;
	$namecount = 0;
	
# Wen Gao	1.1	0	NaN	0	|	0.02	0.141667586620196	0.999833045801102	0.141670937980523	|	0.01	0.33203494606699	0.999786319713194	0.332058510428577	|	0.005	0.687815338042381	0.999621910839702	0.687994322438197	|	0.002	0.815719890489599	0.986864578713446	0.824673737333912	|		
	while($line = <$RESULT>){
		trim($line);
		($name, $disPerfRecords) = split /\t/, $line, 2;
		last if !$disPerfRecords;
		
		$name = lc($name);
			
		@disPerfRecords = split /\t\|\t/, $disPerfRecords;
		
		for $disPerfRecord(@disPerfRecords){
			($thres, $accuracy, $precision, $recall) = split /\t/, $disPerfRecord;
			
			# the first record
			if($precision eq "NaN"){
				next;
			}
			# the last empty "record"
			if(! defined($thres) ){
				next;
			}
						
			# useless actually. only 'avg-f1' is used
			$f1 = f1( $precision, $recall );
			
			push @{ $disName2perf{$name}{$thres}{precision} }, $precision;
			push @{ $disName2perf{$name}{$thres}{recall} },    $recall;
			push @{ $disName2perf{$name}{$thres}{f1} },        $f1;
			
			if($thres == $selThres){
				$psum += $precision;
				$rsum += $recall;
				$f1sum += $f1;
				$namecount++;
			}
		}
	}
	
	if($namecount > 0){
		printf "Avg P/R/F: %.2f  %.2f  %.2f\n", $psum * 100 / $namecount, $rsum * 100 / $namecount, 
								$f1sum * 100 / $namecount;
	}
}

# find the best performance for each name and each score (actually useless)
for $name( @testnames ){
	for $thres( keys %{ $disName2perf{$name} } ){
#		for $k( "precision", "recall" ){
		for $k( "precision", "recall", "f1" ){
			$n = @{ $disName2perf{$name}{$thres}{$k} };
			$maxv = max( @{ $disName2perf{$name}{$thres}{$k} } );
			$sumv = sum( @{ $disName2perf{$name}{$thres}{$k} } );
			if( !exists $disName2bestPerf{$name}{$k}{value} || 
					$maxv > $disName2bestPerf{$name}{$k}{value} ){
				$disName2bestPerf{$name}{$k}{value} = $maxv;
				$disName2bestPerf{$name}{$k}{thres} = $thres;
			}
			$disName2perf{$name}{$thres}{"avg-$k"} = $sumv / $n;
			
			if(!exists $disName2bestAvgPerf{$name}{$k}{value} || 
					$sumv / $n > $disName2bestAvgPerf{$name}{$k}{value} ){
				$disName2bestAvgPerf{$name}{$k}{value} = $sumv / $n;
				$disName2bestAvgPerf{$name}{$k}{thres} = $thres;
			}
		}
	}
}

my $N = @testnames;

# best thres for each name respectively. NOT the default mode. 
# The default is to output the best "unified" threshold (in terms of avg f1) for all names
if( ! $unifiedDisThres ){
	
	print "                    Best Thres  Prec     Rec      F1\n";
	
	my %sumv;
	
	for $name(@testnames){
		my $bestThres = $disName2bestAvgPerf{$name}{f1}{thres};
		printf "%20.20s (%.4f)\t", $name, $bestThres;
		
		for $k( "precision", "recall", "f1" ){
			printf "%.2f\t", $disName2perf{$name}{$bestThres}{"avg-$k"};
			$sumv{$k} += $disName2perf{$name}{$bestThres}{"avg-$k"};
		}
		print "\n";	
	}

	print "           Average:             ";
	for $k( "precision", "recall", "f1" ){
		printf "%.3f\t", $sumv{$k} / $N;
	}
	
	print "\n";	
	exit;
}

	# all for DISTINCT
my ($disAvgv, %disMaxAvgv, %disMaxThres, %disAvgvByThres);

for $k( "precision", "recall", "f1", 'micro-f1' ){
	$disMaxAvgv{$k} = 0;
}

# calc the p/r and micro/macro f1 averaged on all names at each threshold
for $thres(@thresholds){
	for $k( "precision", "recall", "f1" ){
		$sumv = 0;
		for $name( @testnames ){
			$sumv += $disName2perf{$name}{$thres}{"avg-$k"};
		}
		$disAvgv = $sumv / $N;
		if( $disAvgv > $disMaxAvgv{$k} ){
			$disMaxAvgv{$k}  = $disAvgv;
			$disMaxThres{$k} = $thres;
		}
		$disAvgvByThres{$thres}{$k} = $disAvgv;
	}
	
	# $disAvgvByThres{$thres}{'avg-f1'} is macro-f1
	
	$disAvgvByThres{$thres}{'micro-f1'} = f1($disAvgvByThres{$thres}{precision}, $disAvgvByThres{$thres}{recall});
	
	if( $disAvgvByThres{$thres}{'micro-f1'} > $disMaxAvgv{'micro-f1'} ){
		$disMaxAvgv{'micro-f1'}  = $disAvgvByThres{$thres}{'micro-f1'};
		$disMaxThres{'micro-f1'} = $thres;
	}
}
	
# best thres for the maximal macro-F1 score
$thres = $disMaxThres{'f1'};

if(! $generateLatexTable){
	print "\nBest thres: $thres\n";
	print "                       Prec     Rec      F1\n";
		
	for $name(@testnames){
		printf "%20.20s   ", $name;
		for $k( "precision", "recall", "f1" ){
			printf "%.2f    ", $disName2perf{$name}{$thres}{"avg-$k"};
		}
	#	print "\n            ";
	#	for $k( "precision", "recall", "f1" ){
	#		printf "%.3f\t", $disName2bestAvgPerf{$name}{$k}{value};
	#	}
	#	print "\n            ";
	#	for $k( "precision", "recall", "f1" ){
	#		printf "%.3f\t", $disName2bestAvgPerf{$name}{$k}{thres};
	#	}
		print "\n";	
	}
	
	print " Average (macro-F1):   ";
	for $k( "precision", "recall", "f1" ){
		printf "%.3f   ", $disAvgvByThres{$thres}{$k};
	}
	print "\n";
	printf "         (micro-F1) \t\t       %.3f\n", $disAvgvByThres{$thres}{'micro-f1'};
}

if(@ARGV){
	print STDERR "\n================ MY RESULTS ================\n\n";
}

my @name2myperf;
my @myPerfSumByStage;

my $stage;

my $i;

for($i = 0; $i < @ARGV; $i++){
	my $myresultFilename = $ARGV[$i];
	my $MYRESULT;
	print STDERR "Reading '$myresultFilename' to parse...\n";
	open_or_die( $MYRESULT, "< $myresultFilename" );
	
	while($line = <$MYRESULT>){
		if($line =~ /Open groundtruth file '([\w\-\s]+\/)?([\w\s]+)-labels.txt'/){
			$name = $2;
	
			if($myresultOnlyFinal){
				# A small trick:
				# Treat all result lines as in stage 2. If there are results lines both of stage 1 and 2,
				# The result line of stage 2 will overwrite the previous line. 
				# Therefore the statistics are still correct
				$stage = 1;
			}
			else{
				$stage = 0;
			}
			
			next;
		}
		if($line =~ /^Summary:/){
			$line = <$MYRESULT>;
			($precision, $recall, $f1) = $line =~ /Prec: ([\d.]+). Recall: ([\d.]+). F1: ([\d.]+)/;
			
			$name2myperf[$i]{$name}{$stage}{precision} = $precision;
			$name2myperf[$i]{$name}{$stage}{recall} = $recall;
			$name2myperf[$i]{$name}{$stage}{f1} = $f1;
	
			# if $myresultOnlyFinal, then $stage is fixed at 1, which allows overwriting as stated above
			if(! $myresultOnlyFinal){
				$stage++;
			}
		}
	}
	for $name(@testnames){
		for $k( "precision", "recall", "f1" ){
			if(! $myresultOnlyFinal){
				$myPerfSumByStage[0][$i]{$k} += $name2myperf[$i]{$name}{0}{$k};
			}
			$myPerfSumByStage[1][$i]{$k} += $name2myperf[$i]{$name}{1}{$k};
		}
	}
}

if(! $generateLatexTable){
	
	for($i = 0; $i < @ARGV; $i++){
		print "\nAverage:\n";
		print "            Precision\tRecall\tF1\n";
		
		if(! $myresultOnlyFinal){
			print "Coauthor    ";
			for $k( "precision", "recall" ){
				printf "%.3f\t", $myPerfSumByStage[0][$i]{$k} / $N;
			}
			printf "%.3f (macro-F1)\n", $myPerfSumByStage[0][$i]{f1} / $N;
			# micro-f1 in a separate line
			print "\t\t\t\t";
			printf "%.3f (micro-F1)", f1( $myPerfSumByStage[0][$i]{precision} / $N, $myPerfSumByStage[0][$i]{recall} / $N );
		}
		
		print "\nTitle,Venue ";
		
		for $k( "precision", "recall" ){
			printf "%.3f\t", $myPerfSumByStage[1][$i]{$k} / $N;
		}
		# macro-f1, i.e. average of the f1's
		printf "%.3f (macro-F1)\n", $myPerfSumByStage[1][$i]{f1} / $N;

		# micro-f1: f1 of average prec & average recall. In a separate line
		print "\t\t\t\t";
		printf "%.3f (micro-F1)", f1( $myPerfSumByStage[1][$i]{precision} / $N, 
								$myPerfSumByStage[1][$i]{recall} / $N );
		
		
		print "\n\n";
		
		for $name(@testnames){
			for $stage(0, 1){
				if($stage == 0){
					printf "%11.11s ", $name;
					
					if($myresultOnlyFinal){
						next;
					}
				}
				else{
					if(! $myresultOnlyFinal){
						print "            ";
					}
				}
				
				$precision 	= $name2myperf[$i]{$name}{$stage}{precision};
				$recall 	= $name2myperf[$i]{$name}{$stage}{recall};
				$f1 		= $name2myperf[$i]{$name}{$stage}{f1};
				
				printf "%.3f\t%.3f\t%.3f\n", $precision, $recall, $f1;
			}
		}
	}
}
else{
	# for each type among "P", "R", "F", the hash value is an array ref which contains perf scores 
	# of all methods. first are baselines; last two are DISTINCT and CSLR+Taxo
	my %perfByType;
	my @fields;
	
	if($onlyStageOne){
		$stage = 0;
	}
	else{
		$stage = 1;
	}

	for $name(@testnames){
		%perfByType = ();
		
		printf "%20.20s\t&\t", cap($name);
		
		# 3 baselines
		for($i = 0; $i < @ARGV - 1; $i++){
			for $k( "precision", "recall", "f1" ){
				push @{ $perfByType{$k} }, sprintf "%.1f", $name2myperf[$i]{$name}{$stage}{$k} * 100;
			}
		}
		
		if(! $onlyStageOne){
			# DISTINCT
			for $k( "precision", "recall", "f1" ){
				push @{ $perfByType{$k} }, sprintf "%.1f", $disName2perf{$name}{$thres}{"avg-$k"} * 100;
			}
		}
		
		# our approaches
		for $k( "precision", "recall", "f1" ){
			push @{ $perfByType{$k} }, sprintf "%.1f", $name2myperf[$i]{$name}{$stage}{$k} * 100;
		}
		
		highlightAndPrint( \%perfByType );
	}
	# finish printing individual scores of each name
	
	%perfByType = ();
	
	printf "%20.20s\t&\t", "Avg. (macro-F1)";

	# print scores of each method
	for($i = 0; $i < @ARGV - 1; $i++){
		for $k( "precision", "recall" ){
			push @{ $perfByType{$k} }, sprintf "%.1f", $myPerfSumByStage[$stage][$i]{$k} / $N * 100;
		}
		
		# macro F1
		push @{ $perfByType{'f1'} }, sprintf "%.1f", $myPerfSumByStage[$stage][$i]{'f1'} / $N * 100;
	}

	if(! $onlyStageOne){
		for $k( "precision", "recall" ){
			push @{ $perfByType{$k} }, sprintf "%.1f", $disAvgvByThres{$thres}{$k} * 100;
		}
		# macro F1
		push @{ $perfByType{'f1'} }, sprintf "%.1f", $disAvgvByThres{$thres}{'f1'} * 100;
	}
	
	# our CSLR + Taxo
	for $k( "precision", "recall" ){
		push @{ $perfByType{$k} }, sprintf "%.1f", $myPerfSumByStage[$stage][$i]{$k} / $N * 100;
	}
	push @{ $perfByType{f1} }, sprintf "%.1f", $myPerfSumByStage[$stage][$i]{'f1'} / $N * 100;
		
	highlightAndPrint( \%perfByType );
	# finish printing the macro-F1 line
	
	%perfByType = ();

	# micro-f1 in a separate line
	printf "%20.20s\t&\t", "Avg. (micro-F1)";
	
	# two blanks (for prec and recall)
	for $k( "precision", "recall" ){
		# for baselines and DISTINCT
		for($i = 0; $i < @ARGV; $i++){
			push @{ $perfByType{$k} }, "";
		}
		# for ours
		if(! $onlyStageOne){
			push @{ $perfByType{$k} }, "";
		}
	}

	# micro F1 of baselines
	for($i = 0; $i < @ARGV - 1; $i++){
		push @{ $perfByType{f1} }, sprintf "%.1f", 100 * 
				f1( $myPerfSumByStage[$stage][$i]{precision} / $N, $myPerfSumByStage[$stage][$i]{recall} / $N );
	}
	
	# micro F1 of DISTINCT
	if(! $onlyStageOne){
		push @{ $perfByType{f1} }, sprintf "%.1f", 100 * $disAvgvByThres{$thres}{'micro-f1'};
	}
	
	# micro F1 of ours
	push @{ $perfByType{f1} }, sprintf "%.1f", 
		100 * f1( $myPerfSumByStage[$stage][$i]{precision} / $N, $myPerfSumByStage[$stage][$i]{recall} / $N );
	
	highlightAndPrint( \%perfByType );
	
}

sub highlightAndPrint
{
	my $perfByType = shift;
	
	my $i;
	for $k( "precision", "recall", "f1" ){
		my $max = max( grep { $_ ne "" } @{ $perfByType->{$k} } );
		
		next if ! $max;
		
		for( @{ $perfByType->{$k} } ){
			if( $_ == $max ){
				$_ = '\textbf{' . $_ . '}';
			}
		}
	}
	
	my @fields = ();
	
	for( $i = 0; $i < @{ $perfByType->{ "precision" } }; $i++ ){
		for $k( "precision", "recall", "f1" ){
			push @fields, $perfByType->{$k}->[$i];
		}
	}
	
	print join("\t&\t", @fields), "\t\\\\ \\hline\n";
}
