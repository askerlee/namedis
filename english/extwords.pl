undef $/;
@files = glob $ARGV[0];

my $totalcount = 0;
my $count;
my $phrasecount = 0;
my $phrasewordcount = 0;
my @dupwords = ();
my %wordbag = ();

for $f(@files){
	open(DATA, "< $f") || die "Cannot open '$f' to read: $!\n";
	$s = <DATA>;
	$count = 0;
	$phrasecount = 0;
	$phrasewordcount = 0;
	while($s =~ m{<li>\s*([^<>]+?)\s*</li>}sg){
		$w = $1;
		if($w =~ /\d/){
			next;
		}
		if($w =~ /[^a-zA-Z\'. ]/){
			print STDERR "$w\n";
			next;
		}
		$w =~ s/\.$//;
		$w = decap($w);
		
		if($w =~ / /){
			$phrasecount++;
			@ws = split / /, $w;
			for(@ws){
				if(addword($_)){
					$phrasewordcount++;
				}	
			}	
		}
		else{
			addword($w);
		}	
	}
	print STDERR "$count words ", ($phrasecount == 0) ? "" : "($phrasewordcount from $phrasecount phrases) ",
				"are extracted from $f\n";
}
print STDERR "$totalcount words are extracted from ", scalar @files, " files\n";
print STDERR "duplicate words: ", join(", ", @dupwords), "\n";

sub addword
{
	my $w = shift;
	if(exists $wordbag{$w}){
		#print STDERR "DUP: $w (with $wordbag{$w})\n";
		push @dupwords, $w;
		return;
	}
	$wordbag{$w} = $f;
	$totalcount++;
	$count++;
	print "$w\n";
}

sub decap
{
	if(@_ == 1){
		my $w = $_[0];
		if($w !~ /[a-z]/ && length($w) > 1){
			return $w;
		}
		$w =~ s/\b([A-Z])(?=[^A-Z]|$)/\L$1/g;
		return $w;
	}
	else{
		for(@_){
			if(!/[a-z]/ && length > 1){
				next;
			}
			$_ =~ s/\b(\w)/\L$1/g;
		}
	}
}
