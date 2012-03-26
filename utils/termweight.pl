use lib '.';
use NLPUtil;

sub loadNetIC
{
	my %args = @_;
	my $filename = $args{filename};

	print "Loading network ICs from '$filename'...\n";

	my $IC;
	if(!open($IC, "< $filename")){
		return;
	}

	@ICs = ();
	@freqs = ();
	@term2AuthorCount = ();
	
	my $i;

	my $line = <$IC>;
	if($line =~ /# MC: ([\d.]+)\. addedFreqSum: ([\d.]+)\. addedCountableFreqCount: ([\d.]+)/){
		$MC = $1;
		$addedFreqSum = $2;
		$addedCountableFreqCount = $3;
		print "$line";
		$avgMatchScore = $addedFreqSum / $addedCountableFreqCount;
		print "Average match score: $avgMatchScore\n";
	}
	else{
		print "WARN: Unknown IC header format, ignore:\n$line";
		$MC = 0;
	}

	my ($id_term, $ic, $freq, $gen1freq, $authorCount);
	my ($id, $term);
	
	my $termID;
	my $tc = 0;

	my %termInfo;
	my $ratio;
	
	while($line = <$IC>){
		next if $line =~ /^#/;
		trim($line);
		next if !$line;

		($id_term, $ic, $freq, $gen1freq, $authorCount) = split /\t/, $line;
		($id, $term) = split / /, $id_term, 2;
		
		$tc++;
		
		if($authorCount == 0){
			$ratio = 0;
		}
		else{
			$ratio = $gen1freq / $authorCount;
		}
		
		if($gen1freq > 100){
			$termInfo{$term}{ratio} = $ratio;
			$termInfo{$term}{gen1freq} = $gen1freq;
			$termInfo{$term}{authorCount} = $authorCount;
		}
	}
	print "$. line read, $tc entries loaded. MC: $MC\n";

	open(OUT, "> terminfo.txt");
	
	my @termlist = sort { $termInfo{$a}{ratio} <=> $termInfo{$b}{ratio} } keys %termInfo;
	
	for $term(@termlist){
		print OUT join("\t", $term, $termInfo{$term}{ratio}, $termInfo{$term}{gen1freq}, 
					$termInfo{$term}{authorCount}), "\n";
	}
}

loadNetIC(filename => '/home/shaohua/wikipedia/ic.txt');
