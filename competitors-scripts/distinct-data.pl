use strict;

use constant{
	namedisDir 					=> "/media/tough/namedis",
	wikipediaDir 				=> "/media/first/wikipedia",
};

use lib namedisDir;
use NLPUtil;
use Distinct;

use lib wikipediaDir;
use ConceptNet;

use Getopt::Std;
my %opt;
getopts("p:y:", \%opt);

my $dirPrefix = "";
if(exists $opt{'p'}){
	$dirPrefix = $opt{'p'};
	if( $dirPrefix !~ /\/$/ ){
		$dirPrefix .= "/";
	}
	print STDERR "Data file path prefix: '$dirPrefix'\n";
}

my @rel2filename = (
# 0	philip s. yu	161
Author			=> 'distinct-authors.txt',

# 0	conf/adbis/DervosLM96	journals/ipl/DervosML98
# the above example must be wrong. A year 96 paper shouldn't cite a year 98 paper
Citation 		=> 'distinct-citation.txt',

# 0	FOCS, 1960	FOCS	1960	9
Conference		=> 'distinct-venues.txt',

# 0	FOCS, 1960	logic	3
ConfKeyword		=> 'distinct-confkeywords.txt',

### useless? ignored
Editor			=> '',

# 0	conf/ACMse/FoussC00a	collaborative	1
PubKeyword		=> 'distinct-pubkeywords.txt',

# 0	conf/ACMse/FoussC00a	ACM Southeast Regional Conference, 2000
Publication		=> 'distinct-pubs.txt',

# 0	philip s. yu	conf/aaai/LongZY07
Publish			=> 'distinct-publish.txt',
);

my %rel2filename = @rel2filename;
my %relNO;

my $index = 0;
my $relName;

while(@rel2filename){
	$relName = shift @rel2filename;
	shift @rel2filename;
	$relNO{$relName} = $index++;
}

my %extraFiles = (
# 0	mobile	26406
Keyword 		=> 'distinct-keywords.txt'
);

# keep the order. so don't use hash
my @insWordsDesc = ( 'Author' => [ 1 ], 'Keyword' => [ 1 ], 'Conference' => [ 1, 2, -3 ],
											# -m means don't do replacement. output verbatim
					 'Publication' => [ 1, 2 ], 'Citation' => [ 1, 2 ], 
					 'ConfKeyword' => [ 1, 2 ], 'PubKeyword' => [ 1, 2 ], 
					 'Publish' => [ 1, 2 ], 
					 # an empty "editor.dat" file
					 'Editor' => [ ],
				   );

my @wordtable;				   
my %wordtable;
my $wid = 0;	# word ID starts from 0

my $relationName;
my $attrList;
my $filename;
my ($inFilename, $relNO, $outFilename);

while(@insWordsDesc){
	$relationName = shift @insWordsDesc;
	$attrList = shift @insWordsDesc;
	
	if($extraFiles{$relationName}){
		$inFilename = ${dirPrefix} . $extraFiles{$relationName};
		numeralizeFile($inFilename, -1, $attrList, undef);
	}
	elsif($rel2filename{$relationName}){
		$inFilename = ${dirPrefix} . $rel2filename{$relationName};
		$outFilename = ${dirPrefix} . lc($relationName) . ".dat";
		$relNO = $relNO{$relationName};
		numeralizeFile($inFilename, $relNO, $attrList, $outFilename);
	}
}

my $WORDTABLE;
open_or_die($WORDTABLE, "> ${dirPrefix}wordtable.dat");

my $w;
for $w(@wordtable){
	print $WORDTABLE "$wordtable{$w}{id}: ($w), $wordtable{$w}{relNO}, $wordtable{$w}{attrNO}\n";
}

sub numeralizeFile
{
	my ($inFilename, $relNO, $columnList, $outFilename) = @_;
	
	my ($IN, $OUT);
	
	if($outFilename){
		open_or_die($OUT, "> $outFilename");
	}
	
	# create an empty '$outFilename' file. for "editor.dat"
	if(! $inFilename){
		return;
	}

	print STDERR "Numeralize '$inFilename'...\n";
	
	open_or_die($IN, "< $inFilename");
	
	my $line;
	my @columns;
	my $colNO;
	my @outNums;
	my $i;
	
	my $inLineCount = 0;
	my $outLineCount = 0;
	
	my $oldwid = $wid;
	
	my $progresser = makeProgresser( vars => [ \$. ], step => 10000 );
	
	while($line = <$IN>){
		&$progresser();
		
		trim($line);
		@columns = split /\t/, $line;
		@outNums = ();
		
		$inLineCount++;
		
		for($i = 0; $i < @$columnList; $i++){
			$colNO = $columnList->[$i];
			if($colNO >= 0){
				push @outNums, word2id( $columns[$colNO], $relNO, $i );
			}
			else{
				# verbatim
				push @outNums, $columns[ - $colNO ];
			}
		}
		
		if($OUT){
			print $OUT join("\t", @outNums), "\n";
			$outLineCount++;
		}
	}
	
	print STDERR "$inLineCount lines read, $outLineCount lines written. ", 
					$wid - $oldwid, " words newly inserted\n";
}

sub word2id
{
	my ($w, $relNO, $attrNO) = @_;
	
	# '()' are used as delimiters in DISTINCT. so replace them
	$w =~ tr/()/<>/;
	$w = lc($w);
	
	if(exists $wordtable{$w}){
#		if($wordtable{$w}{relNO} == -1 && $relNO > 0){
#			print STDERR "WARN: $w\n";
#		}
		return $wordtable{$w}{id};
	}
	else{
		$wordtable{$w} = { id => $wid++, relNO => $relNO, attrNO => $attrNO };
		push @wordtable, $w;
		return $wid - 1;
	}
}
