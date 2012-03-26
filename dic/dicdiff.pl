if(@ARGV < 2){
	die "Usage: $0 check_dict base_dict\n";
}

$dic1name = $ARGV[0];
$dic2name = join(",", @ARGV[1.. $#ARGV]);

loaddic(\%dic1, $ARGV[0]);
for($i = 1; $i < @ARGV; $i++){
	loaddic(\%dic2, $ARGV[$i]);
}
diff(\%dic1, \%dic2);

sub loaddic
{
	my ($t, $filename) = @_;
	open(DIC, "< $filename") || die "Cannot open '$filename' to read: $!\n";
	my @lines = <DIC>;
	my $w;
	my $line;
	my @fields;
	
	my $count = 0;
	
	for $line(@lines){
		chomp $line;
		if($line =~ /^#/){
			next;
		}
		
		$line = decap($line);
		@fields = split /\t/, $line;
		$w = $fields[0];
		$w =~ s/\.$//;
		
		$count += splitphrase($t, $w, $line);
	}
	print STDERR "$count words loaded from '$filename'\n";
}

sub diff
{
	my ($smaller, $bigger) = @_;
	my @diffwords;
	my @commonwords;
	
	for $w(sort keys %{$smaller}){
		if(!exists $bigger->{$w}){
			push @diffwords, $w;
		}
	}
	if(@diffwords > 0){
		print STDERR (scalar @diffwords), " words in '$dic1name' are not in '$dic2name'\n";
		print "# beginning of words from $dic1name\n";
		for(@diffwords){
			if($_ ne $smaller->{$_}){
				print "$_\t$smaller->{$_}\n";
			}	
			else{
				print "$_\n";
			}	
		}
		print "# end of words from $dic1name\n";
	}
	
	for $w(sort values %{$smaller}){
		if(exists $bigger->{$w}){
			push @commonwords, $w;
		}
	}
	if(@commonwords > 0){
		print STDERR "Common words:\n", join(", ", @commonwords), "\n";
	}
	else{
		print STDERR "No words in common\n";
	}
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

sub splitphrase
{
	my $wordbag = shift;
	my ($w, $w2);
	my @ws;
	my $count = 0;

	$w = shift;
	my $line = shift;
	
	if($w =~ / |-|\'/){
		@ws = split / |-/, $w;
		for $w2(@ws){
			# for contractions like J'esp¨¨re, we assign the ' to the first part
			if($w2 =~ /([A-Za-z]+\')([A-Za-z]*)/){
				$count += addword($wordbag, $1, $line) + addword($wordbag, $2, $line);
			}
			else{
				$count += addword($wordbag, $w2, $line);
			}
		}
	}
	else{
		$count += addword($wordbag, $w, $line);
	}
	
	return $count;
}

sub addword
{
	my $wordbag = shift;
	my $w = shift;
	my $line = shift;
	
	if($w eq ""){
		return 0;
	}
		
	if(exists $wordbag->{$w}){
		print STDERR "DUP: $w\n";
		return 0;
	}
	$wordbag->{$w} = $line;
	return 1;
}
