use strict;
use warnings 'all';
use feature qw(switch say);

use lib '/media/tough/namedis';
use NLPUtil;

use lib '.';
use ConceptNet;

use enum qw(BITMASK:ST_ INI PAGE HEADER TEXT TABLE REF REFLIST REDIRECT);
my @enumSyms = qw(:ST_ INI PAGE HEADER TEXT TABLE REF REFLIST REDIRECT);

my %enum2name = revEnumMap(@enumSyms);

if(@ARGV == 0){
	die "Usage: $0 input_file\n";
}

my @wikiFiles;
my @matchFiles;
for(@ARGV){
	@matchFiles = glob($_);
	push @wikiFiles, @matchFiles;
	if(@wikiFiles == 0){
		die "No file matches pattern '$_'\n";
	}
}

sub revEnumMap
{
	my $name;
	my $v;
	my $prefix = "";
	my %enum2name;
	
	for $name(@_){
		if($name =~ /^:/){
			$prefix = substr($name, 1);
		}
		else{
			$name = "$prefix$name";
			$v = &{$main::{$name}};
			$enum2name{$v} = $name;
		}
	}
	return %enum2name;
}

sub lookupEnumMap
{
	my $v = shift;

	return bitmap2desc($v, scalar @enumSyms, \%enum2name);
}
	
my $state;
my $lastState;

sub setState
{
	$lastState = $state;
	$state = $_[0];
#	print "$. ST: ", lookupEnumMap($lastState), " -> ", lookupEnumMap($state), "\n";
}

sub orState
{
	$lastState = $state;
	$state |= $_[0];
#	print "$. ST: ", lookupEnumMap($lastState), " -> ", lookupEnumMap($state), "\n";
}

sub xorState
{
	$lastState = $state;
	$state ^= $_[0];
#	print "$. ST: ", lookupEnumMap($lastState), " -> ", lookupEnumMap($state), "\n";
}

=pod

my ($concept1, $concept2);

open_or_die(CONCEPTS, "< csmathling-full.txt");
ConceptNet::iniLists();

while($line = <CONCEPTS>){
	&$progress();
	
	trim($line);
	next if !$line;
	
	($concept2, $concept1) = split /\t/, $line;

	addEdge(\@conceptNet, $concept2, $concept1);
}
progress_end("$. lines read from 'csmathling-full.txt'");

=cut

# a dirty hack, to avoid removing parentheses or braces
$puncs{')'} = 0;
$puncs{'('} = 0;
$puncs{'{'} = 0;
$puncs{'}'} = 0;

my $extFilename = getAvailName("extended.txt");

print STDERR "Extracted terms will be saved into '$extFilename'.\n";
open_or_die(OUT, "> $extFilename");

#*OUT = *STDERR;

my $wc = 0;
my $lwc;

my $progresser = makeProgresser(vars => [ \$., \$lwc ], step => 10000);

my $excludedType = qr/(Wikipedia|File|Template|Portal):/;

my $fi = 0;
my $flc = 0;
my $fc = @wikiFiles;
for(@wikiFiles){
	$fi++;
	processFile($_);
	$wc += $lwc;
	$flc += $.;
}
print STDERR "$wc subordinates extracted from $fc files ($flc lines), ", 
				trunc(3, $wc * 100 / $flc), "\%\n";

sub processFile
{
	my $line;
	
	my %synbag;
	my @disambigOptions;
	my $synonym;
	my $synonym_lc;
	
	my $title;
	my $filename = shift;
	
	print STDERR "Process file '$filename' ($fi of $fc):\n";
	open_or_die(IN, "< $filename");
	print OUT "# $filename\n";
	
	my $lastRoundState;
	$lwc = 0;
	
	my $interested = 1;
	my $isDisambigPage;
	$state = ST_INI;

	while($line = <IN>){
		&$progresser();
		
		do{
			$lastRoundState = $state;
			
			trimTrailing($line);
			$line =~ s/\&lt;/</g;
			$line =~ s/\&gt;/>/g;
			
			if($line =~ /<page>/gc){
				setState(ST_HEADER);
			}
			if($line =~ /<title>([^<>]+)<\/title>/gc){
				$title = $1;
				%synbag = ();
				@disambigOptions = ();
				$isDisambigPage = 0;
				
				if($title =~ /$excludedType/
								||
				   $title =~ /[\x80-\xff]/
				   				||
				   $title =~ /&[^;]+;/){
					$interested = 0;
				}
				else{
					$interested = 1;
				}
		#		$interested = exists $wordtable{$title};
			}
			if($state == ST_HEADER && $line =~ /<redirect\s*\/>/gc){
				orState(ST_REDIRECT);
			}
			if($line =~ /<text( [^<>]+)?>/gc){
				xorState(ST_HEADER);
				orState(ST_TEXT);
			}		
			if($interested && $state & ST_TEXT){
				# simply discard everything in reference list
				if($state & ST_REFLIST){
					next;
				}
				
				if($state & ST_REDIRECT){
					if($line =~ /#REDIRECT\s*\[\[([^\]\[]+)\]\]/gci){
						$synonym = $1;
						if($line !~ /[\x80-\xff]/
								&&
						   $line !~ /$excludedType/ ){
							print OUT "$title\t$synonym\tredir\n";
							$lwc++;
						}
					}
					next;
				}
					
				# section title
				if(substr($line, 0, 2) eq "==" && substr($line, -2, 2) eq "=="){
					if($line =~ /\breferences/i){
						orState(ST_REFLIST);
					}
					next;
				}
				if($state & ST_REF){
					if($line =~ /<\/ref>/gc){
						xorState(ST_REF);
					}
					else{
						next;	# still in <ref>...</ref>
					}
				}
				if($line =~ /<ref( [^<>]+)?>/gc){
					orState(ST_REF);
				}
				if($line =~ /^ /gc){
					next;	# code block
				}
				
				if( $line =~ /\{\|/gc ){
					orState(ST_TABLE);
				}
				if( $line =~ /\|\}/gc ){
					xorState(ST_TABLE);
				}
				if( $line =~ /\{\{disambig\}\}/ ){
					$isDisambigPage = 1;
				}
				
				if($state == ST_TEXT){
					
					while($line =~ /'''(.+?)'''/gc){
						$synonym = $1;
						if($synonym =~ /\[\[[^\]]+\|[^\]]+\]\]./
							|| 
						   $synonym =~ /.\[\[[^\]]+\|[^\]]+\]\]/){
							$synonym =~ s/\[\[[^\]]+\|//g;
						}
						else{
							$synonym =~ s/\|[^\[]+\]\]//g;
						}
						$synonym =~ s/[\[\]]//g;
						$synonym =~ s/http:\/\/\S+//g;
						$synonym =~ s/''//g;
						trimPunc($synonym);
						$synonym_lc = lc($synonym);
						$synonym =~ s/^(.)/\U$1/;
						next if length($synonym_lc) <= 3
								|| $synonym_lc =~ /^\d+$/
								|| $synonym_lc =~ /^\(\d+\)$/
								|| $synonym_lc =~ /^figure \d+$/
								|| $synbag{$synonym_lc}
								|| $synonym =~ /[\x80-\xff]/
								|| $synonym =~ /&[^;]+;/	# no html entities
#								|| $termTable{$synonym}
								|| substr($synonym, 0, 1) eq '-'
								|| substr($synonym, -1, 1) eq '-'
								|| lc($title) =~ /\Q$synonym_lc\E/
								|| $stopwords{$synonym_lc};
						print OUT "$synonym\t$title\n";
						$lwc++;
						$synbag{$synonym_lc}++;
					}
					
					if($line =~ /^\*\s*\[\[([^\]]+)\]\]/){
						my $disambigOption = $1;
						# sometimes it's like 
						# **[[Artificial Intelligence (journal)|''Artificial Intelligence'' (journal)]]
						($disambigOption) = split /\|/, $disambigOption;
						# why this check? remove noises? I couldn't remember
						# but if the option contains the whole title, little new info is contained in the option
						# maybe it's good to keep it ambiguous
						# but i guess in most cases the option contains the title.
						# therefore effectively disambiguation pages are discarded
						if($disambigOption !~ /\b\Q$title\E\b/i){
							push @disambigOptions, $disambigOption;
						}
					}
				}
			}
			if($line =~ /<\/text>/gc){
				xorState(ST_TEXT);
			}
			if($line =~ /<\/page>/gc){
				setState(ST_INI);
				
				if($isDisambigPage){
					for(@disambigOptions){
						print OUT "$title\t$_\n";
						$lwc++;
					}
				}
			}
		}while($lastRoundState != $state);	# allow multiple tags in one line?
	}
	
	my $percent = $. > 0 ? trunc(3, $lwc * 100 / $.) : 0;
	progress_end($., $lwc, $percent . '%');
}
