my @stopwords1 = qw(
a about above across after again against almost alone along also 
although always am among an and another any anybody anyone anything  
apart are around as  at away be because been before behind being below 
besides between beyond both but by can cannot could  did do does doing done 
down  during each either else enough etc  ever every everybody 
everyone except far few for  from get gets got had  has have having 
her here herself him himself his how however if in indeed instead into  
is it its itself just kept  maybe might  more most mostly much must 
myself  neither  no nobody none nor not nothing  of off often on 
only onto or other others ought our ours out  own  please  
pp quite rather really said seem self selves  shall she should since so 
some somebody somewhat still such than that the their theirs them themselves 
then there therefore these they this thorough thoroughly those through thus to 
together too toward towards until up upon very was we well were what 
whatever when whenever where whether which while who whom whose why will with
within would yet your yourself 
);

my @academicStopwords = qw(via using based);

%stopwords = map { $_, 1 } (@stopwords1, @academicStopwords);

die "Please specify a file to count\n" if @ARGV == 0;

open(TITLES, "< $ARGV[0]");

$| = 1;

my $wc = 0;
my $stopwc = 0;

while($line = <TITLES>){
	if($. % 1000 == 0){
		print "\r$.\r";
	}
	while($line =~ /\b([a-zA-Z]+)\b/g){
		$w = decap($1);
		$wc++;
		if(exists $stopwords{$w}){
			$stopwc++;
		}	
	}	
}

print "\n$stopwc / $wc = ", $stopwc / $wc, "\n";

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
