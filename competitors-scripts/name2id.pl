# convert a list of author names used by DISTINCT to IDs for it to use

use warnings 'all';
use strict;
use lib '/home/shaohua/namedis';

use Distinct;

my @authors = (@distinctNames);#, @tjNames);
			  
my %authors = map { lc($_) => {} } @authors;

my ($line, $name, $id);

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

open(WORDTABLE, "< ${dirPrefix}wordtable.dat");
while($line = <WORDTABLE>){
	$line =~ /^(\d+): \(([\w. ]+)\)/;
	$name = $2;
	$id = $1;
	if(exists $authors{$name}){
		$authors{$name}{id} = $id;
	}
}

my (@fields, $pubcount);
open(AUTHORS, "< ${dirPrefix}distinct-authors.txt");
while($line = <AUTHORS>){
	chomp $line;
	@fields = split /\t/, $line;
	$name = $fields[1];
	$pubcount = $fields[2];
	if(exists $authors{$name}){
		$authors{$name}{pubcount} = $pubcount;
	}
}

print "ID: ", join( ", ", map { $authors{ lc($_) }{id} } @authors ), "\n";
print "Pubcount: ", join( ", ", map { $authors{ lc($_) }{pubcount} } @authors ), "\n";
