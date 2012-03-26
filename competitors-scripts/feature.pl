use List::Util qw(min max sum);

open(MODEL, "< svmtrain.dat") || die "Cannot open 'svmtrain.dat': $!\n";

my @posCount;
my @negCount;
my @posSum = 0;
my @negSum = 0;
my $v;
my $featureNo;
my $nonzeroCount;
my $nullSampCount = 0;

my $neg;

while(<MODEL>){
	$nonzeroCount = 0;
	if(m/^-/){	
		$neg = 1;
	}
	else{
		$neg = 0;
	}
	
	while(m/(\d+):([\d.]+)/g){
		$featureNo = $1;
		$v = $2;
		next if($v == 0);
		
		$nonzeroCount++;
		if($neg){
			$negSum[$featureNo] += $v;
			$negCount[$featureNo]++;
		}
		else{
			$posSum[$featureNo] += $v;
			$posCount[$featureNo]++;
		}
	}
	if($nonzeroCount == 0){
		$nullSampCount[$neg]++;
	}
}

print "$nullSampCount[0] +null samples, $nullSampCount[1] -null samples\n";

for $featureNo(1..14){
	if($posCount[$featureNo] || $negCount[$featureNo]){
		print "$featureNo+: $posCount[$featureNo], $posSum[$featureNo], ", 
						$posSum[$featureNo] / max($posCount[$featureNo], 1), "\n";
		print "$featureNo-: $negCount[$featureNo], $negSum[$featureNo], ", 
						$negSum[$featureNo] / max($negCount[$featureNo], 1), "\n";
	}
}
