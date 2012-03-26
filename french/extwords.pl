use strict;

my %conv = ('à' => 'a', 'é' => 'e', 'è' => 'e', 'ç' => 'c', 'ô' => 'o', 'ê' => 'e',
		 "\xc3\x89" => 'E', 'î' => 'i', 'â' => 'a', 'û' => 'u', "\xe2\x80\x99" => "'",
		 'œ' => 'oe', 'ï' => 'i', 'ù' => 'u',
			);
$| = 1;
undef $/;
my @files = glob $ARGV[0];

my $totalcount = 0;
my $count;
my $phrasecount = 0;
my $phrasewordcount = 0;
my ($newPhraseCount, $newPhraseWordCount);

my @dupwords = ();
my %wordbag = ();
my $headwordindex;

our $f;
my $s;
my ($w, $w2, $w3);
my $char;
my @ws;

$headwordindex = 0;

for $f(@files){
	open(DATA, "< $f") || die "Cannot open '$f' to read: $!\n";
	$s = <DATA>;
	$count = 0;
	$phrasecount = 0;
	$phrasewordcount = 0;
	while($s =~ m{<td class="bigLetter">(<a [^<>]+>)?([^<>]+)(</a>)?</td>}sg){
		$w = $2;
		$headwordindex++;

		for $char(keys %conv){
			$w =~ s/$char/$conv{$char}/g;
		}
		if($w =~ /\d/){
			print STDERR "$headwordindex: $w\n";
			next;
		}

		$w2 = "";
		if($w =~ s/\(([a-zA-Z\'.\- ]+)\)//){
			# a failed match/replace won't reset $1, $2,...
			$w2 = $1;
		}
		trim($w, $w2);

		if($w =~ /[^a-zA-Z\'\- ]/){
			print STDERR "$headwordindex: $w\n";
			next;
		}
		
		($newPhraseCount, $newPhraseWordCount) = splitphrase($w);
		$phrasecount += $newPhraseCount;
		$phrasewordcount += $newPhraseWordCount;
		
		if($w2 ne ""){
			($newPhraseCount, $newPhraseWordCount) = splitphrase($w2);
			$phrasecount += $newPhraseCount;
			$phrasewordcount += $newPhraseWordCount;
		}
				
#		$w =~ s/\.$//;
#		$w = decap($w);

	}
	print STDERR "$count words ", ($phrasecount == 0) ? "" : "($phrasewordcount from $phrasecount phrases) ",
				"are extracted from $f\n";
}
print STDERR "\n$totalcount words are extracted from ", scalar @files, " files\n";
print STDERR "duplicate words: ", join(", ", @dupwords), "\n";

sub addword
{
	my $w = shift;
	if($w eq ""){
		return 0;
	}
		
	if(exists $wordbag{$w}){
		print STDERR "$headwordindex,DUP: $w (with $wordbag{$w})\n";
		push @dupwords, $w;
		return 0;
	}
	$wordbag{$w} = "$f:$headwordindex";
	$totalcount++;
	$count++;
	print "$w\n";
	return 1;
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

sub trim
{
	for(@_){
		$_ =~ s/^\s+|\s+$//g;
	}
}

sub splitphrase
{
	my ($w, $w2);
	my @ws;
	my $phrasecount;
	my $phrasewordcount;

	for $w(@_){
		if($w =~ / |-|\'/){
			$phrasecount++;
			@ws = split / |-/, $w;
			for $w2(@ws){
				# for contractions like J'espère, we assign the ' to the first part
				if($w2 =~ /([A-Za-z]+\')([A-Za-z]*)/){
					$phrasewordcount += addword($1) + addword($2);
				}
				else{
					$phrasewordcount += addword($w2);
				}
			}
		}
		else{
			addword($w);
		}

	}
	return ($phrasecount, $phrasewordcount);
}
