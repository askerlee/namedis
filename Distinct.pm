package Distinct;

use strict;
use warnings 'all';

use lib '.';
use NLPUtil;

use List::Util qw(min max sum);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw( loadChosenConfs loadChosenAuthors loadKeywordTable dumpKeywords replaceAuthorNames
				  loadDBFile dumpPub2 loadDistinctFile
				  
				  %chosenConfs %chosenConfs2 %chosenAuthors %chosenKeywords $maxConfIndex
				  %nameReplaceList %titleAuthor2venueKey %titleVenue2key %safeKeys
				  @distinctNames @tjNames
				  
				  $AUTHOR_PUBCOUNT_THRES $VENUE_YEAR_THRES $VENUE_PUB_SUM_THRES
				);
				
our %chosenConfs;
our %chosenConfs2;
our %chosenAuthors;
our %chosenKeywords;

our %titleAuthor2venueKey;
our %titleVenue2key;

# names used in DISTINCT paper
our @distinctNames	= ("Hui Fang","Ajay Gupta", 
						"Joseph Hellerstein", 
						"Rakesh Kumar", "Michael Wagner", "Bing Liu",
						"Jim Smith", "Lei Wang",
						"Wei Wang",
						"Bin Yu", 
			 		  );
# names used in tang jie's paper			 		  
our @tjNames		= ("Liping Wang", "David Brown", "David Jensen", "Gang Wu",
			  			"Xiaodong Wang", "Tao Peng", "Peng Cheng", "Wen Gao"
			 		  );

@distinctNames  = map { lc($_) } @distinctNames;
@tjNames 		= map { lc($_) } @tjNames;

our %nameReplaceList = ('joseph m. hellerstein' 	=> 'joseph hellerstein', 
					   'joseph l. hellerstein' 	=> 'joseph hellerstein',
					   'michael m. wagner'		=> 'michael wagner',
					   'ajay k. gupta'			=> 'ajay gupta',
					   'jim e. smith'			=> 'jim smith',
					   );

our @safeKeys = qw(conf/delta/FangNJY06 conf/accv/ChettyW06 conf/ewsn/WangCSW06 
					conf/apweb/WangF06 conf/icb/WangLNCW06);
our %safeKeys = map { $_ => 1 } @safeKeys;

our $maxConfIndex = -1;

our $AUTHOR_PUBCOUNT_THRES = 2;
our $VENUE_YEAR_THRES = 1;
our $VENUE_PUB_SUM_THRES = 10;

sub loadChosenConfs($)
{
	my $confFile = shift;
	
	my $CONF;
	print STDERR "Loading conference file '$confFile'...\n";
	open_or_die($CONF, "< $confFile");
	
	my $line;
	my ($idx, $name, $venue, $year, $papercount);
	
	while($line = <$CONF>){
		next if $line =~ /^#/;
		
		trim($line);
		($idx, $name, $venue, $year, $papercount) = split /\t/, $line;
#		if($years < $yearsThres){
#			last;
#		}
		$chosenConfs{$name} = { index => $idx, venue => $venue, year => $year, papercount => $papercount };
		
		# the index of the last year of this venue. It's not important which year the index is of,
		# we only need the index values keep the order of venues
		$chosenConfs2{$venue} = $idx;
		
		$maxConfIndex = max($maxConfIndex, $idx);
	}
	print STDERR scalar keys %chosenConfs, " conferences are loaded, max index: $maxConfIndex\n";
}

sub loadChosenAuthors($)
{
	my ($authorFile) = @_;
	
	my $AUTHORS;
	print STDERR "Loading author file '$authorFile'...\n";
	open_or_die($AUTHORS, "< $authorFile");
	
	my $line;
	my ($idx, $name, $years, $papercount);
	
	while($line = <$AUTHORS>){
		next if $line =~ /^#/;
		
		trim($line);
		($idx, $name, $papercount) = split /\t/, $line;
#		if($papercount < $pubCountThres){
#			last;
#		}
		$chosenAuthors{$name} = { index => $idx, papercount => $papercount };
	}
	print STDERR scalar keys %chosenAuthors, " authors are loaded into the training set\n";
}

sub loadKeywordTable($)
{
	my ($keywordTableFile) = @_;
	
	my $KEYWORDS;
	print STDERR "Loading keyword table file '$keywordTableFile'...\n";
	open_or_die($KEYWORDS, "< $keywordTableFile");
	
	my $line;
	my ($idx, $word, $freq);
	
	while($line = <$KEYWORDS>){
		next if $line =~ /^#/;
		
		trim($line);
		($idx, $word, $freq) = split /\t/, $line;
		$chosenKeywords{$word} = { index => $idx, freq => $freq };
	}
	print STDERR scalar keys %chosenKeywords, " keywords are loaded into the keyword table\n";
}

sub dumpKeywords($$$)
{
	my ($keyList, $hKeywords, $keywordFilename) = @_;
	
	my $key;
	my @keywords;
	my $keyword;
	my $keywordList;
	
	my $KEYWORD_PROFILE;
	
	if(! open_or_warn($KEYWORD_PROFILE, "> $keywordFilename") ){
		return;
	}
	
	my $index = 0;
	
	for $key(@$keyList){
		$keywordList = $hKeywords->{$key};
		@keywords = sort { $keywordList->{$b} <=> $keywordList->{$a}
											   ||
										$a	  cmp 	$b
						 } keys %$keywordList;
		
		for $keyword(@keywords){
			print $KEYWORD_PROFILE join( "\t", $index, $key, $keyword, $keywordList->{$keyword} ), "\n";
			$index++;
		}
	}
	
	print STDERR "$index attr-keyword pairs saved into '$keywordFilename'\n";
}

sub replaceAuthorNames
{
	my @authorNames = @_;
	my $name;
	
	for $name(@authorNames){
		if($nameReplaceList{$name}){
			$name = $nameReplaceList{$name};
		}
	}
	
	return @authorNames;
}

# default: not DISTINCT format
sub dumpPub2($$;$)
{
	my ($FH, $pub, $isDistinctFormat) = @_;
	
	if(! defined($pub->venue) ){
		$pub->venue("");
	}
	
	if(! $isDistinctFormat){
		print $FH $pub->title, "\n";
		print $FH join( ", ", @{ $pub->authors } ), "\n";
		print $FH join( ". ", $pub->year, $pub->venue, "key: " . $pub->pubkey ), "\n";
	}
	else{
		# jianmin jiang, hui fang, yong yin,    "conf/delta/fangnjy06"   delta, 2006
		print $FH join( ", ", @{ $pub->authors } ), ',    "', lc( $pub->pubkey ), '"   ', 
					$pub->venue, ", ", $pub->year, "\n";
	}
}
	
sub loadDBFile($)
{
	my $title;
	my $year;
	my $venue;
	my $authorLine;
	my $thisPublication;
	
	my $loadCount = 0;
	
	my $dblpFilename = shift;
	
	print $tee "Open file '$dblpFilename' to process...\n";

	my $DB;
	if(! open_or_warn($DB, "< $dblpFilename")){
		return;
	}
	
	while(!eof($DB)){
		$thisPublication = parseCleanDBLP($DB);
		
		$title = $thisPublication->title;
		trimPunc($title);
		
		$year = $thisPublication->year;
		$venue = $thisPublication->venue;
		
		$authorLine = join(",", @{$thisPublication->authors} );

		if(exists $titleAuthor2venueKey{"$year-$title-$authorLine"}){
			warn "Title '$title' already exists in \%titleAuthor2venueKey\n";
		}
		else{
			$titleAuthor2venueKey{"$year-$title-$authorLine"} = { venue => $thisPublication->venue, 
														pubkey => $thisPublication->pubkey };
		}
		
		if($venue){
			if(exists $titleVenue2key{"$year-$title-$venue"}){
				warn "Title '$title' already exists in \%titleVenue2key\n";
			}
			else{
				$titleVenue2key{"$year-$title-$venue"} = { pubkey => $thisPublication->pubkey };
			}
		}
	}
	
	$loadCount = max(scalar keys %titleVenue2key, scalar keys %titleAuthor2venueKey);
	
	print $tee "$loadCount publications loaded.\n\n";
}

sub loadDistinctFile($$)
{
	my %key2affil;
	
	my $loadCount = 0;
	
	my ($distinctFilename, $affiliations) = @_;
	
	print $tee "Open file '$distinctFilename' to process...\n";

	my $DB;
	if(! open_or_warn($DB, "< $distinctFilename")){
		return;
	}
	<$DB>;<$DB>;<$DB>; # skip the header
	
	my $line;
	my $nominalClustNo;
	my $realClustNo = 0;
	my $affil;
	my $clustSize = 0;
	my $readcount = 0;
	
	while(!eof($DB)){
		$line = <$DB>;
		trim($line);
		
		if( ! $line ){
			if($readcount != $clustSize){
				die "Cluster $nominalClustNo: said $clustSize, but read $readcount\n";
			}
			
			$realClustNo++;
			$readcount = 0;
			next;
		}
		
		# Cluster 0, 73 tuples
		if($line =~ /^Cluster (\d+), (\d+) tuples( \([^()]+\))?/){
			$nominalClustNo = $1;
			$clustSize = $2;
			$affil = $3;
			
			if($affil){
				trim($affil);
			}
			else{
				$affil = "yin's cluster $nominalClustNo";
			}
			
			push @$affiliations, $affil;
			next;
		}
		
		#bing liu, robert l. grossman,    "conf/dils/neglurgl05"   NULL, 2005
		if($line =~ /[a-z.]+( [a-z.]+, )+   "([^\"]+)"   [^,]+, \d{4}/){
			$key2affil{$2} = $realClustNo;
			$readcount++;
			
			next;
		}
		
		print STDERR "Unknown format: $line\n";
	}
	
	return \%key2affil;
}

1;
