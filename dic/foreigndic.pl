use strict;

my %conv = ("[\xE0-\xE2]" => 'a', "\xE7" => 'c', "[\xE8-\xEB]" => 'e',
			 "[\xEC-\xEF]" => 'i', "[\xF2-\xF6]" => 'o',
			 "[\xF9-\xFC]" => 'u',
			);

my $outfile;

if(@ARGV == 0){
	die "Please specify a file to process\n";
}
if(@ARGV == 1){
	$outfile = "$ARGV[0].2";
}
else{
	$outfile = $ARGV[1];
}


open(OUT, "> $outfile") || die "Cannot open '$outfile' to write: $!\n";

my %foreignwords;
my %enwords;
my %encommonwords;

loaddic(\%enwords, "english.dic");
loaddic(\%encommonwords, "english-all.dic");
loaddic(\%encommonwords, "english-academic.dic");
loaddic(\%encommonwords, "english-manual.dic");

open(FOREIGN, "< $ARGV[0]") || die "Cannot open '$ARGV[0]' to read: $!\n";

my @foreignwords = <FOREIGN>;

my ($w, $w2);
my @fields;
	
my $pat;
my $comment;
my $foreignwordcount;
my $outcount;

for $w(@foreignwords){
	chomp $w;
	if($w =~ /^#/){
		next;
	}

	$w = decap($w);
	@fields = split /\t/, $w;
	if($fields[1] =~ /\(([^()]+)\)/){
		$comment = $1;
		if($comment =~ /^(ou|et|avoir) ([a-z\']+)$/){
			$w2 = $1;
		}
	}
	$w = $fields[0];

	if($w =~ /[^a-zA-Z\'\- ]/){
		for $pat(keys %conv){
			$w =~ s/$pat/$conv{$pat}/g;
		}
	}
	if($w =~ /[^a-zA-Z\'\- ]/){
		print "$.: $w\n";
	}
	else{
		if($foreignwords{$w}){
			next;
		}
		$foreignwords{$w} = 1;
		$foreignwordcount++;

		if($encommonwords{$w} == 1){
#			print "COMMON: $w\n";
			next;
		}
		else{
			if($enwords{$w} == 1){
				print "RARE: $w\n";
			}
			print OUT "$w\n";
			$outcount++;
		}
	}
}
print "$foreignwordcount foreign words, $outcount has been written into $outfile\n";

sub loaddic
{
	my ($t, $filename) = @_;
	open(DIC, "< $filename") || die "Cannot open '$filename' to read: $!\n";
	my @lines = <DIC>;
	my $w;
	my @fields;
	
	my $count = 0;
	
	for $w(@lines){
		chomp $w;
		if($w =~ /^#/){
			next;
		}
		
		$w = decap($w);
		@fields = split /\t/, $w;
		$w = $fields[0];
		$w =~ s/\.$//;
		
		if(!exists $t->{$w}){
			$count++;
			$t->{$w} = 1;
		}	
	}
	print "$count words loaded from '$filename'\n";
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
