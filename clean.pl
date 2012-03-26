use strict;
use XML::Parser;
use Getopt::Std;
use POSIX;
use lib '.';
use NLPUtil;

use constant{
	OPTIONS => 'v:p:d:',
};

use enum qw(BITMASK: NATIVEWORD LOANWORD LOAN_PART_PHRASE);

use enum qw(:APOSTROPHE_ BEFORE AFTER NONE IGNORE);

use enum qw(ENGLISH GERMAN FRENCH);

use enum qw(BITMASK:DEBUG_ TESTLANG);

my $debug = 0;

my %pubBackyear = (article => 2, inproceedings => 1, book => 3,
					incollection => 2, phdthesis=> 3, mastersthesis => 1);

my %numMap = (	'37' => '%', '91' => '[', '93' => ']', 160 => ' ',
				'123' => '{', '125' => '}', '124' => '|',
				'147' => '"', '148' => '"', '145' => "'", '146' => "'",
				'150' => '-', '151' => ':', '173' => '-', '176' => ' degree',
				'185' => ' 1', '178' => ' 2', '179' => ' 3',
				171 => '"', 187 => '"',
				153 => '', #trademark sign, discard
				'174' => '', #register sign, discard
				'169' => '', #copyright sign, discard
				'177' => 'plus-minus ', "181" => 'micro',
				'183' => '.', '189' => '1/2',
				"190" => '3/4', '215' => '*', '64' => '@',
				'945' => 'alpha', '948' => 'delta', 949 => 'epsilon',
				'955' => 'lambda', '960' => 'pi',
				8482 => '', #trademark sign
				'x03a3' => 'Sigma', 'x2113' => 'L', 'x00E9' => 'e',
				'64257' => 'fi',
				);

my %langMap = (
					'&aacute;' => 'a', '&acirc;' => 'a', '&agrave;' => 'a', '&aring;' => 'a',
					'&atilde;' => 'a', '&auml;' => 'a',
					'&Aacute;' => 'A', '&Acirc;' => 'A', '&Agrave;' => 'A', '&Aring;' => 'A',
					'&Atilde;' => 'A', '&Auml;' => 'A',
					'&ccedil;' => 'c', '&Ccedil;' => 'C',
					'&eacute;' => 'e', '&ecirc;' => 'e', '&egrave;' => 'e', '&euml;' => 'e',
					'&Eacute;' => 'E', '&Ecirc;' => 'E', '&Egrave;' => 'E', '&Euml;' => 'E',
					'&iacute;' => 'i', '&icirc;' => 'i', '&igrave;' => 'i', '&iuml;' => 'i',
					'&Iacute;' => 'I', '&Icirc;' => 'I', '&Igrave;' => 'I', '&Iuml;' => 'I',
					'&ntilde;' => 'n', '&Ntilde;' => 'N',
					'&oacute;' => 'o', '&ocirc;' => 'o', '&ograve;' => 'o', '&oslash;' => 'o',
					'&otilde;' => 'o', '&ouml;' => 'o',
					'&Oacute;' => 'O', '&Ocirc;' => 'O', '&Ograve;' => 'O', '&Oslash;' => 'O',
					'&Otilde;' => 'O', '&Ouml;' => 'O',
					'&uacute;' => 'u', '&ucirc;' => 'u', '&ugrave;' => 'u', '&uuml;' => 'u',
					'&Uacute;' => 'U', '&Ucirc;' => 'U', '&Ugrave;' => 'U', '&Uuml;' => 'U',
					'&yacute;' => 'y', '&yuml;' => 'y', '&Yacute;' => 'Y',
					'&aelig;' => 'ae', '&AElig;' => 'Ae',
					'&szlig;' => 'ss',
					'&eth;' => 'th', '&thorn;' => 'th', '&ETH;' => 'Th', '&THORN;' => 'Th',
				);

#my @deFrWords = qw(und un une du systeme zu zur zum de der bei ist des le en von im);
#my $deFrPat = "\\b(" . join("|", map { ($_, cap($_)) } @deFrWords) . ")\\b";

my $NO_FOREIGN_TITLE_WARNING = 1;
my $NO_AUTHORLESS_WARNING = 1;
my $M = INT_MAX;
my $processedOptionCount = 0;

my $parser = new XML::Parser(ErrorContext => 2);

$parser->setHandlers(Default => \&default_handler,
             Start => \&start_handler,
             End => \&end_handler);

my %opt;
getopts(OPTIONS, \%opt);

if(exists $opt{'v'}){
	my @verboseArg = split /,/, lc($opt{'v'});
	for(@verboseArg){
		if($_ eq "foreign"){
			print "Foreign title warning is enabled\n";
			$NO_FOREIGN_TITLE_WARNING = 0;
		}
		elsif($_ eq "noauthor"){
			print "No-author warning is enabled\n";
			$NO_AUTHORLESS_WARNING = 0;
		}
		else{
			die "FATAL  verbose argument '$_' is not understood\n";
		}
	}
	$processedOptionCount++;
}

if(exists $opt{'p'}){
	$M = $opt{'p'};
	if($M =~ /[^0-9]/){
		die "FATAL  maximum valid publications '$M' is not understood\n";
	}
	print "No more than $M valid publications will be processed\n";
}
if(exists $opt{'d'}){
	if($opt{'d'} =~ /\blang\b/){
		$debug |= DEBUG_TESTLANG;
	}
	print "Detailed information of testLang() will be output\n";
}

if(grep { OPTIONS !~ /$_/ } keys %opt){
	die "FATAL  Unknown options: ", join(',', keys %opt), "\n";
}

print "\n" if $processedOptionCount;

if(@ARGV == 0){
    die "Please specify the DBLP file to process\n";
}

my $file = shift;
my ($outfilestem) = $file =~ /(.+)\.[^.]+$/;
my $outfile = getAvailName("$outfilestem.extracted.txt");

my %engMap;
my %germanMap;
my %frenchMap;
my ($GERTITLES, $FRETITLES);

loadVocab(\%engMap, "dic/english.dic", "common English",
					APOSTROPHE_AFTER, NATIVEWORD);
loadVocab(\%engMap, "dic/english-all.dic", "common English 2",
					APOSTROPHE_AFTER, NATIVEWORD);
loadVocab(\%engMap, "dic/english-academic.dic", "academic English",
					APOSTROPHE_AFTER, NATIVEWORD);
loadVocab(\%engMap, "dic/english-manual.dic", "manually-added English",
					APOSTROPHE_AFTER, NATIVEWORD);

loadVocab(\%germanMap, "dic/german.dic", "German",
					, APOSTROPHE_NONE, NATIVEWORD);
loadVocab(\%germanMap, "dic/german-manual.dic", "manually-added German",
					, APOSTROPHE_NONE, NATIVEWORD);
loadVocab(\%frenchMap, "dic/french-all.dic", "French",
					APOSTROPHE_BEFORE, NATIVEWORD);
loadVocab(\%engMap, "dic/french-phrase.dic", "French",
					APOSTROPHE_IGNORE, LOANWORD);
loadVocab(\%frenchMap, "dic/french-phrase.dic", "French",
					APOSTROPHE_BEFORE, NATIVEWORD);

my $germanTitlesFilename = getAvailName("german-titles.txt");
my $frenchTitlesFilename = getAvailName("french-titles.txt");
open_or_die($GERTITLES, "> $germanTitlesFilename");
open_or_die($FRETITLES, "> $frenchTitlesFilename");

print "Extracted records will be saved into '$outfile'\n";
open_or_die(OUT, "> $outfile");

my @tagStack = ();
my @innerTextStack = ();

my $parentInnerText;
my $tagDepth = 0;
my $recordStartLn;
my $interestRecord = 0;
my $str;
my $thisTitle;
my $pubYear;
my $pubType;
my $pubKey;
my $booktitle;
my $hasForeignChar;
my $isGermanFrench;
my $isTitleForeign;
my $isLastEnded;
my @authorNames;

our $gAuthorCount = 0;
our $gRecordCount = 0;
our $gValidgRecordCount = 0;
our $noAuthorPubCount = 0;
our $noYearPubCount = 0;
our $foreignTitleCount = 0;
our $uninterestingPubCount = 0;
my %gPubCountByYear;
my %gNameCount;

my @counters = (qw($gValidgRecordCount $gRecordCount $recordStartLn), 
				'ny: $noYearPubCount', 'na: $noAuthorPubCount', 
				'fo: $foreignTitleCount', 'un: $uninterestingPubCount');

NLPUtil::initialize(progressDelim => "  ", progressVars => 
						[ \$gValidgRecordCount, \$gRecordCount, \$recordStartLn ]);

eval '$parser->parsefile($file)';
if($@){
	print $@;
	unlink $outfile;
	print "'$outfile' removed\n";
}

progress2();

summary();

sub default_handler
{
	my ($p, $s) = @_;

	my ($hash, $desc);

	if($interestRecord){
		if($s =~ /^\&(\#?)([a-zA-Z]+);$/){
			$hash = $1;
			$desc = $2;
			if(exists $xmlSymMap{$s}){
				$s = $xmlSymMap{$s};
			}
			elsif(exists $langMap{$s}){
				$s = $langMap{$s};
				$hasForeignChar = 1;
			}
			elsif($hash && exists $numMap{$desc}){
				$s = $numMap{$desc};
			}
			else{
				$hasForeignChar = 1;
				print "Unknown entity at ", $p->current_line, ": $s\n";
			}
		}
		$str .= $s;
	}
}

sub start_handler
{
	my ($p, $el, %attrs) = @_;
	push @tagStack, $el;
	push @innerTextStack, $str;

	# if the 3rd layer of tag have a nested tag, such as <tag1>blahblah<tag2>dadada</tag2></tag1>,
	# then we need to save the string "blahblah" before going to tag2.
	$str = "";
	$tagDepth++;

	if($tagDepth == 2){
		if(exists $pubBackyear{$el}){
			$interestRecord = 1;
			$recordStartLn = $p->current_line;
			@authorNames = ();
			$hasForeignChar = 0;
			$isTitleForeign = 0;
			$isGermanFrench = 0;
			$pubType = $el;
			if(exists $attrs{key}){
				$pubKey = $attrs{key};
			}
		}
		else{
			$interestRecord = 0;
			$uninterestingPubCount++;
		}
		if($gRecordCount % 1000 == 0){
			progress2();
		}
		$gRecordCount++;
	}
}

sub end_handler
{
	my ($p, $el) = @_;

	$parentInnerText = pop @innerTextStack;

	if($interestRecord){
		if($tagDepth == 3){
			if($el eq "author" || $el eq "editor"){
				if($str =~ /,/){
					print "\nAuthor name contains ',', ignore: $str\n";
					next;
				}
				push @authorNames, $str;
			}
			elsif($el eq "title"){
				# unescape again. sometimes the title contains things like &amp;uuml;
				$str = unescapeEntity($str);
				$isGermanFrench = 
						testLang($str, \%germanMap, GERMAN, APOSTROPHE_NONE, $GERTITLES)
										||
						testLang($str, \%frenchMap, FRENCH, APOSTROPHE_BEFORE, $FRETITLES);
						
				$thisTitle = $str;

				if($hasForeignChar || $isGermanFrench){
					$isTitleForeign = 1;
				}
			}
			elsif($el eq "year"){
				$pubYear = $str;
			}
			elsif($el eq "booktitle"){
				$booktitle = $str;
			}
			elsif($el eq "journal"){
				if($pubType eq "article"){
					$booktitle = $str;
				}
			}
			$hasForeignChar = 0;
			$isGermanFrench = 0;
		}
		elsif($tagDepth == 2){
			if($isTitleForeign){
				if(!$NO_FOREIGN_TITLE_WARNING){
					progress2();
					print "\nPublication title seems not english, ignore:\n",
							$thisTitle, "\n";
				}
				$foreignTitleCount++;
			}
			elsif(@authorNames == 0){
				if(!$NO_AUTHORLESS_WARNING){
					progress2();
					print "\nPublication has no author, ignore:\n",
							$thisTitle, "\n";
				}
				$noAuthorPubCount++;
			}
			elsif(!$pubYear){
				$noYearPubCount++;
			}
			else{
				# dump begins
				print OUT "$thisTitle\n", join(",", @authorNames), "\n";
				print OUT "$pubYear";
				if($booktitle){
					print OUT ". $pubType: $booktitle";
				}
				if($pubKey){
					print OUT ". key: $pubKey";
				}
				print OUT "\n\n";
				# dump ends
				
				$gPubCountByYear{$pubYear}++;
				$gValidgRecordCount++;
				for(@authorNames){
					$gNameCount{$_}++;
				}
				if($gValidgRecordCount % 1000 == 0){
					progress2();
				}
				$gAuthorCount += @authorNames;

				if($gValidgRecordCount >= $M){
					summary();
					print "\nLast line being processed is ", $p->current_line + 1, "\n";
					die "Exit early.\n";
				}
			}
			$thisTitle = "";
			$pubYear = 0;
			$booktitle = "";
			$pubKey = "";
			@authorNames = ();
			$interestRecord = 0;
			$hasForeignChar = 0;
			$isGermanFrench = 0;
			$isTitleForeign = 0;
		}
		elsif($tagDepth > 3 && $tagStack[2] eq "title"){
			$str = $parentInnerText . $str;
		}
	}
	pop @tagStack;
	$tagDepth--;
}

sub summary
{
	my $pubCount = $gValidgRecordCount;
	my $namesakeCount = scalar keys %gNameCount;

	print "\n\n$gRecordCount records processed\n";
	print "$noAuthorPubCount pubs have no author, $noYearPubCount have no year, ",
				"$foreignTitleCount are foreign\n\n";

	print c1000($pubCount), " valid publications by ", $gAuthorCount, " authors.\n";
	if($pubCount > 0){
		print $gAuthorCount / $pubCount, " authors each publication.\n";
	}

	print "\nPublication breakdown by year:\n";
	my @years = sort { $a <=> $b } keys %gPubCountByYear;
	my $year;
	for $year(@years){
		print "$year:\t", c1000($gPubCountByYear{$year}), "\n";
	}
	print "\n";

	print c1000($namesakeCount), " distinct namesakes.";
	if($namesakeCount > 0){
		print " Each occurs ", $gAuthorCount / $namesakeCount, " times\n";
		print $pubCount / $namesakeCount, " publications per namesake\n";
	}
	my @names = sort { $gNameCount{$b} <=> $gNameCount{$a} } keys %gNameCount;

	my $i;
	print "\n100 most prolific namesakes:\n";

	for($i = 0; $i < 100 && $i < @names; $i++){
		print "$names[$i]\t\t\t$gNameCount{$names[$i]}\n";
	}
	print "\n";
}

sub unescapeEntity
{
	my $s = shift;
	my ($ent, $hash,$desc);

	while($s =~ /(\&(\#?)([a-zA-Z0-9]+);)/g){
		$ent = $1;
		$hash = $2;
		$desc = $3;
		if(exists $xmlSymMap{$ent}){
			$s =~ s/$ent/$xmlSymMap{$ent}/;
		}
		if(exists $langMap{$ent}){
			$s =~ s/$ent/$langMap{$ent}/;
			$hasForeignChar = 1;
		}
		elsif($hash && exists $numMap{"$desc"}){
			$s =~ s/$ent/$numMap{"$desc"}/;
		}
	}
	return $s;
}

sub testLang
{
	my ($s, $foreignMap, $foreignLangType, $apostropheFlag, $logfh) = @_;
	
	my @foreignWords;
	my @sharedWords;
	my @engWords;
	my @unknownWords;
	
	my $w;
	my (@wordsFor, @wordsEng);
	my (@wfs, @wes, $wf, $we);
	my $matchlen;
	my $totalwordcount = 0;
	
	while($s =~ /(?<![a-zA-Z0-9\'])([a-zA-Z\']+)(?![a-zA-Z0-9\'])/g){
		$w = decap($1);
		
		if($w !~ /\'/ || $engMap{$w} & (LOAN_PART_PHRASE | LOANWORD) ){
			$totalwordcount++;
			if($foreignMap->{$w} == NATIVEWORD){
				if(!exists $engMap{$w}){
					push @foreignWords, $w;
				}
				elsif($engMap{$w} & LOAN_PART_PHRASE){
					$matchlen = matchPhrase($w, substr($s, pos($s)), \%engMap);
					if($matchlen == 0){
						if($engMap{$w} & NATIVEWORD){
							push @sharedWords, $w;
						}
						elsif($engMap{$w} & LOANWORD){
							push @sharedWords, $w;
						}
						else{
							push @foreignWords, $w;
						}
					}
					else{
						push @sharedWords, $w . substr($s, pos($s), $matchlen);
						pos($s) += $matchlen;
					}
				}
				# match phrase fails
				elsif($engMap{$w} & NATIVEWORD){
					push @sharedWords, $w;
				}
				elsif($engMap{$w} & LOANWORD){
					push @sharedWords, $w;
				}
			}
			elsif(exists $engMap{$w}){
				push @engWords, $w;
			}
			else{
				push @unknownWords, $w;
			}	
		}
		else{
			$totalwordcount += 2;
			@wfs = splitApostrophe($w, $apostropheFlag);
			@wes = splitApostrophe($w, APOSTROPHE_AFTER);
			for $wf(@wfs){
				if($foreignMap->{$wf} == NATIVEWORD){
					push @foreignWords, $wf;
				}	
			}
			for $we(@wes){
				if($engMap{$we} & NATIVEWORD){
					push @engWords, $we;
				}
			}
		}	
	}
	
	if($debug & DEBUG_TESTLANG){
		print "$s\n";
		print "Foreign words:\t", join(", ", @foreignWords), "\n";
		print "Shared words:\t", join(", ", @sharedWords), "\n";
		print "English words:\t", join(", ", @engWords), "\n";
		print "Unknown words:\t", join(", ", @unknownWords), "\n";
		print "\n";
	}
	
	if($totalwordcount <= 4 && @engWords >= $totalwordcount - 1){
		return 0;
	}
		
	if(@foreignWords > 0 && @foreignWords *  3 >= @engWords){
		print $logfh "$s\n";
		return 1;
	}
	if(@foreignWords > 0 && @sharedWords >= @engWords){
		print $logfh "$s\n";
		return 1;
	}
	return 0;
}

sub loadVocab
{
	my ($wordmap, $vocabfile, $langname, $apostropheFlag, $isLoaned) = @_;
	open_or_die(VOCAB, "< $vocabfile");

	my $w;
	my $entrycount = 0;
	my $wordcount = 0;
	my $phrasecount = 0;
	my (@words, @words2);
	my $part;

	my $w2;

	my $oldwordcount;
	
	while($w = <VOCAB>){
		if($w =~ /^\#/ || $w =~ /,/ || $w !~ /[a-zA-Z]/){
			next;
		}
		chomp $w;
		$w = decap($w);

		$oldwordcount = $wordcount;
		
		# phrase
		if($w =~ /\s|-/){
			$phrasecount++;
			
			@words = split /\s+|-/, $w;

			if($isLoaned == NATIVEWORD){
				for $w2(@words){
					@words2 = splitApostrophe($w2, $apostropheFlag);
					map { $wordcount += addword($wordmap, $_, NATIVEWORD) } @words2;
	
					if(@words2 > 1){
						$wordcount += addword($wordmap, $w2, NATIVEWORD);
					}
				}
			}
			else{
				$part = shift @words;
				while(@words > 0){
					# part of a loan phrase may be a word in the native language
					# so use "|" here
					# if the type of a single word contains LOAN_PART_PHRASE, 
					# it can be NATIVEWORD or LOANWORD
					$wordmap->{$part} |= LOAN_PART_PHRASE;
					$part .= " " . (shift @words);
				}
			}
			# if $w is a native phrase, it actually will never be matched up
			$wordcount += addword($wordmap, $w, $isLoaned);
		}
		# single word
		else{
			if($isLoaned == NATIVEWORD){
				@words2 = splitApostrophe($w, $apostropheFlag);
				map { $wordcount += addword($wordmap, $_, NATIVEWORD) } @words2;

				if(@words2 > 1){
					$wordcount += addword($wordmap, $w, NATIVEWORD);
				}
			}
			else{
				$wordcount += addword($wordmap, $w, LOANWORD);
#				print "$w: loaned single word is not supported\n";
#				next;
			}
		}
		
		if($isLoaned == LOANWORD && $wordcount == $oldwordcount){
			print "Not inserted: $w\n";
		}
			
		$entrycount++;
	}
	print "$entrycount entries in '$vocabfile' processed, $wordcount $langname words",
			$phrasecount > 0 ? "/phrases" : "", " loaded\n";
}

sub splitApostrophe
{
	my ($w, $apostropheFlag) = @_;
	
	my $wordcount = 0;
	
	if($w =~ /^([A-Za-z]*)(\')([A-Za-z]*)$/){
		if($apostropheFlag == APOSTROPHE_AFTER){
			return ($1, $2.$3);
		}
		elsif($apostropheFlag == APOSTROPHE_BEFORE){
			return ($1.$2, $3);
		}
		elsif($apostropheFlag == APOSTROPHE_NONE){
#			print "Unexpected \"'\" in $w\n";
		}
		elsif($apostropheFlag == APOSTROPHE_IGNORE){
			return ($w);
		}
	}
	else{
		return ($w);
	}
}
	
sub addword
{
	my ($wordbag, $w, $isLoaned) = @_;
	
	if($w eq ""){
		return 0;
	}
		
	if(exists $wordbag->{$w}){
		if(($wordbag->{$w} & $isLoaned) == 0){
			if($wordbag->{$w} == LOAN_PART_PHRASE){
				$wordbag->{$w} |= $isLoaned;
				return 1;
			}
			else{
				$wordbag->{$w} |= $isLoaned;
				return 0;
			}	
		}
		else{
			# print STDERR "DUP: $w\n";
			return 0;
		}
	}
	else{
		$wordbag->{$w} = $isLoaned;
		return 1;
	}	
}

sub matchPhrase
{
	my ($leadword, $s, $langmap) = @_;
	
	my $matchlen = 0;
	
	while($s =~ /^[^a-zA-Z0-9\']([a-zA-Z\']+)(?![a-zA-Z0-9\'])/g){
		$leadword .= " " . $1;
		$matchlen += pos($s);
		
		if($langmap->{$leadword} & LOANWORD){
			return $matchlen;
		}
		elsif($langmap->{$leadword} & LOAN_PART_PHRASE){
			$s = substr($s, pos($s));
			next;
		}
		else{
			return 0;
		}
	}
	return 0;
}
