use strict;
use warnings 'all';

use JSON;
use LWP::UserAgent;
use File::Glob ':glob';
use File::Slurp;
use Time::HiRes qw(gettimeofday);
use Term::ANSIColor;

use lib 'C:/Dropbox/namedis';
use NLPUtil;
use Distinct;

use Getopt::Std;

use constant{
	DOMAIN => "http://arnetminer.org",
	OPTIONS => "b:",
	ARNET_SAVE_DIR => "arnet",
	ARNET_CACHE_DIR => "arnet/cache",
};

my %opt;
getopts(OPTIONS, \%opt);

my $batchFile;
my @allAuthorIDs;
my @allNames;
my $BATCH_AUTHORID;

if(exists $opt{'b'}){
	$batchFile = $opt{'b'};
	print $tee "Process batch file '$batchFile':\n";
	
	open_or_die($BATCH_AUTHORID, "< $batchFile");
	
	NLPUtil::openLogfile();

	my $line;
	while($line = <$BATCH_AUTHORID>){
		trim($line);
		next if ! $line;
		next if $line =~ /^#/;	# a commented line
		
		my ($name, $ids) = split /\t/, $line;
		my @ids = split / /, $ids;
		push @allAuthorIDs, \@ids;
		push @allNames, lc($name);
		print $tee "$name\t@ids\n";
	}
	print $tee scalar @allNames, " names are read and wait to be processed\n";
}
elsif( @ARGV < 1 || 0 < grep { ! /^\d+$/ } @ARGV ){
	die "Usage:\t$0 author_id1 author_id2 ...\n\t$0 -b batch_file\n";
}
else{
	@allAuthorIDs = [ @ARGV ];
	@allNames = ( undef );	# for a single ID, the name is not specified, but read from the web page
	# the $authorName will be set in the call to parsePage()
	
	NLPUtil::openLogfile();
}

my @queue;

my $totalDownMsec = 0;
my $totalDownPageCount = 0;
my $totalPubCount = 0;
my $totalDownName = 0;
my $avgDownMsec;
my $uaErrMsg;
# is an author ID downloaded or queued?
my %isIDDownOrQueue;

my $ua = LWP::UserAgent->new;
$ua->timeout(200);
$ua->agent("Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; SV1;" .
            " .NET CLR 2.0.50727; .NET CLR 1.1.4322; InfoPath.2)");
$ua->default_headers()->referer( DOMAIN );

$SIG{INT} = \&confirmAbort;

NLPUtil::initialize();
print $tee "\n";

my $iniAuthorIDs;
my $authorName;

my $i;
for($i = 0; $i < @allAuthorIDs; $i++){
	$iniAuthorIDs = $allAuthorIDs[$i];
	$authorName = $allNames[$i];
	
	print $tee ">>>>>> ", $i + 1, " ";
	
	my $pubCount = downName($iniAuthorIDs);
	if($pubCount > 0){
		$totalDownName++;
	}
}
print $tee "Totally $totalDownName names, $totalDownPageCount authors, $totalPubCount publications downloaded\n";

# in: $authorID, $source
sub saveToCache($$)
{
	my ($authorID, $source) = @_;
	my $CACHE;

	my $cacheFilename = ARNET_CACHE_DIR . "/$authorID.html";
	
	if( -e $cacheFilename ){
		print $tee "WARN: '$cacheFilename' will be overwritten.\n";
	}
	
	# save the web page into the cache
	eval 'write_file( $cacheFilename, { binmode => ":utf8" }, $source )';
	if($@){
		print $tee "$@\n";
		return 0;
	}
	return 1;
}

# in: $authorID
# out: $source, or undef if "$authorID.html" not found in cache
sub loadFromCache($)
{
	my ($authorID) = @_;
	my $source;
	
	my $cacheFilename = ARNET_CACHE_DIR . "/$authorID.html";

	if( ! -e $cacheFilename ){
		return undef;
	}
	
	# load the web page source from the cache
	eval '$source = read_file( $cacheFilename )';
	if($@){
		print $tee "$@\n";
		return undef;
	}
	return $source;
}

sub downName
{
	my $nameDownPageCount = 0;
	my $namePubCount = 0;
	
	# in each run, $authorName is fixed. i.e. only crawl certain name's ambiguous authors
	my ($ids) = @_;
	@queue = @$ids;
	
	print $tee "Name '$authorName' (@queue):\n";
	
	my $authorID;
	
	my @authorPubs;
	my @affiliations;
	
	# 1: queued. 2: downloaded
	map { $isIDDownOrQueue{$_} = 1 } @queue;
	
	for $authorID(@queue){
		my $source;
		my $sourceNewlyDown = 0;
		
		print $tee "\n>>> $authorID\n";
		
		$source = loadFromCache($authorID);
		
		if(! $source){
			#my $url = "http://www.arnetminer.org/viewperson.do?naid=$authorID";
			my $url = "http://arnetminer.org/person/-$authorID.html";
			$source = uaget($url, "Please check the Internet connection");
			if(!$source){
				print $tee "$uaErrMsg\n";
				push @queue, $authorID;
				next;
			}
			$sourceNewlyDown = 1;
		}
				
		$nameDownPageCount++;
		
		# 2: downloaded
		$isIDDownOrQueue{$authorID} = 2;
		
		# global var $authorName may be changed in parsePage()
		my ($pubs, $authorIDs, $affiliation) = parsePage($source);
		
		# web page is abnormal
		next if $pubs == -1;
		
		if($sourceNewlyDown){
	 		saveToCache($authorID, $source);
	 	}
	 	
		next if ! $pubs;
		
		push @authorPubs, $pubs;
		push @affiliations, $affiliation;
		$namePubCount += @$pubs;
		
		my $authorID;
		my $newPageCount = 0;
		
		for $authorID(@$authorIDs){
			if( ! $isIDDownOrQueue{$authorID} ){
				push @queue, $authorID;
				$isIDDownOrQueue{$authorID} = 1;
				$newPageCount++;
			}
		}
		if($newPageCount > 0){
			print $tee "$newPageCount new pages found and queued\n";
		}
		
	}
	
	print $tee "\n$namePubCount publications of $nameDownPageCount authors downloaded\n";
	
	if($namePubCount == 0){
		print $tee "!!! There must be something wrong\n\n";
		return 0;
	}
	print $tee "\n";
	
	my $outFilename = ARNET_SAVE_DIR . "/" . lc($authorName) . "-arnet.txt";
	#$outFilename = getAvailName($outFilename);
	open_or_die(OUT, "> $outFilename");
	print OUT scalar @authorPubs, " clusters.\n\n";
	
	my $outClustSN = 1;
	my $clustSN;
	my $identity;
	
	my @sortedClustSNs = sort { scalar @{ $authorPubs[$b] } <=> scalar @{ $authorPubs[$a] } } (0 .. $#authorPubs);
	
	for $clustSN( @sortedClustSNs ){
		next if !$authorPubs[$clustSN];
		my @pubs = @{ $authorPubs[$clustSN] };
		if(@pubs == 0){
			next;
		}
		
		$identity = $affiliations[$clustSN];
	
		print $tee "Cluster $outClustSN, ", scalar @pubs, " papers:\t$identity\n";
		print OUT "Cluster $outClustSN, ", scalar @pubs, " papers:\t$identity\n";
		
		my $thisPublication;
		for $thisPublication(reverse @pubs){
			dumpPub( \*OUT, $thisPublication );
		}
	
		print OUT "\n";
		$outClustSN++;
	}
	
	$outClustSN--;
	print $tee "\n$outClustSN clusters dumped into '$outFilename'\n\n";
	
	$totalPubCount += $namePubCount;
	$totalDownPageCount += $nameDownPageCount;
	
	return $namePubCount;
}
	
sub uaget($$)
{
    my ($url, $errmsg) = @_;
	
    my ($beforesec, $beforems) = gettimeofday;

    print $tee "GET: $url\n";
    my $response = $ua->get($url);
    print $tee "Done. ";
    
    my ($aftersec, $afterms) = gettimeofday;
    my $msspent = int( ($aftersec - $beforesec) * 1000 + ($afterms - $beforems) / 1000 );
	print $tee "$msspent msec. ";

    if($response->is_success){
    	$totalDownMsec += $msspent;
    	$totalDownPageCount++;
    	$avgDownMsec = $totalDownMsec / $totalDownPageCount;
    	print $tee length($response->content), " bytes.\n";
        return $response->content;
    }
    print $tee "\n";
    my $status = $response->status_line;
    $uaErrMsg = "$status\n";
    if($errmsg){
        $uaErrMsg .= "Failed to download '$url'\n$errmsg";
    }
    return undef;
}

# extra headers $headers is optional, so put it at the last variable
sub uapost($$$;$)
{
    my ($url, $form, $errmsg, $headers) = @_;
	
    my ($beforesec, $beforems) = gettimeofday;

    print $tee "POST: $url\n";
    
    my $response;
    if($headers){
    	$response = $ua->post($url, $form, @$headers);
    }
    else{
    	$response = $ua->post($url, $form);
    }
    print $tee "Done. ";
    
    my ($aftersec, $afterms) = gettimeofday;
    my $msspent = int( ($aftersec - $beforesec) * 1000 + ($afterms - $beforems) / 1000 );
	print $tee "$msspent msec. ";

    if($response->is_success){
    	$totalDownMsec += $msspent;
    	$totalDownPageCount++;
    	$avgDownMsec = $totalDownMsec / $totalDownPageCount;
    	print $tee length($response->content), " bytes.\n";
        return $response->content;
    }
    print $tee "\n";
    my $status = $response->status_line;
    $uaErrMsg = "$status\n";
    if($errmsg){
        $uaErrMsg .= "Failed to download '$url'\n$errmsg";
    }
    return undef;
}

# return: 1, if equal; 0, non-equal
sub checkNameEqual($$)
{
	my ($name1List, $name2) = @_;
	
	if( isChineseName($name2) ){
		if( 0 == grep { $_ eq $name2 } @$name1List ){
			print $tee "Focus author has a different name: ", join("|", @$name1List), " != $name2\n";
			return 0;
		}
		return 1;
	}
	else{
		# "J. Hellerstein" should match "Joseph L. Hellerstein"
		
		my $name1;
		for $name1(@$name1List){
			my $name1Ini = substr($name1, 0, 1);
			my $name2Ini = substr($name2, 0, 1);
	
			my $name1LastName = ( split / /, $name1 )[-1];
			my $name2LastName = ( split / /, $name2 )[-1];
			if( $name1Ini eq $name2Ini && $name1LastName eq $name2LastName ){
				return 1;
			}
		}
		
		print $tee "Focus author has a different name: ", join("|", @$name1List), " != $name2\n";
		return 0;
	}
}

# in: source snippet containing paper records, focus author name, focus author ID
# out: $readPaperCount, ref to an array of extracted pubs
sub extractPubs($$$)
{
	my @pubs;
	my $readPaperCount;
	
	my ($pubsSource, $authorAliases, $focusAuthorID) = @_;
	
	my %authorAliases = map { lc($_) => 1 } @$authorAliases;
	
	while( $pubsSource =~ m{<li pid="\d+" class="s-item" .+?</li>}sgp ){
		my $record = ${^MATCH};
		my ( $title ) = $record =~ m{<a class="title" href="[^\"]*">([^<>]+)</a>};
		my @authorNames = $record =~ m{<a class="(?:cur)?" href="/person/[^\"]+">([^<>]+)</a>}g;
		
#		my $isNameReverse = testChnNameReverse(@authorNames);
		
		for(@authorNames){
			$_ = lc;
		
#			if( $isNameReverse >= 0 && isChineseName($_)
#					&& !isCantoneseName($_, $isNameReverse) ){
#				$_ = standardizeChineseName($_, $isNameReverse);
#			}
		}
		
		@authorNames = replaceAuthorNames(@authorNames);

		my ($year, $venue) = $record =~ m{<p>\s*(\d+),\s*<a href="/conference/[^\"]*">([^<>]+)</a>}s;
		($title, $venue) = restoreXmlEntity($title, $venue);
			
		# if venue has multiple sections, keep the first one
		# if venue is like "ACCV (3)", remove the parentheses.
		# An author may publish on different tracks of the same conf
		$venue = (split /,/, $venue )[0];
		$venue =~ s/\([^()]+\)//;
			
		trim($title, $venue);
			
		$readPaperCount++;
						
		# no "pubkey" available :( . No venue type either
		my $thisPublication = publication->new( title => $title, year => $year, 
						venue => $venue, authors => [ @authorNames ], 
						authorID => $focusAuthorID );
		
		# Some pubs don't contain the focus name. Shouldn't be collected. 
		# But still counted in $readPaperCount
		if( 0 == grep { $authorAliases{$_} } @authorNames ){
			print $tee "WARN: no '$authorName' in the author list of this publication, discard:\n";
			dumpPub($tee, $thisPublication);
			print $tee "\n";
			next;
		}

		push @pubs, $thisPublication;
			
	}
	
	return ($readPaperCount, \@pubs);	
}

# in: $source: web page source. 
# return (\@pubs, \@namesakeIDs, $affiliation)
# $authorName is changed to a global var, as opposed to a passed-in var. 
# it is author name of the currently processed page, and may be changed here if it's undef
# To reduce complexity, $authorName should never have aliases
# But the current processed page could have aliases, one of which could match $authorName
sub parsePage($)
{
	# OBSOLETE: view-source:http://www.arnetminer.org/viewperson.do?naid=652767&name=Bin%20Yu
	# view-source:http://arnetminer.org/person/-652767.html
	
	# don't use 'shift' here. We may modify $_[0] 
	my $source = $_[0];
	
	# OBSOLETE: <title>Bin Yu</title>
	# <title>Bin Yu | AMiner.org</title>
	$source =~ m{<title>([^<>]+)<\/title>};
	my $name = lc($1);
	$name = (split /\|/, $name)[0];
	trim($name);
	
	# There are name aliases! Rakesh K. Sharma vs. Rakesh Kumar
	# OBSOLETE: <span style='color:#ccc;font-size: 11px'> (ALIAS: Rakesh Kumar Sharma, Rakesh Kumar, Rakesh Sharma)</span>
	# <em>ALIAS: Rakesh Kumar Sharma, Rakesh Kumar, Rakesh Sharma</em>
	my ( $aliases ) = $source =~ m{<em>ALIAS: ([^<>]+)</em>};
	my @aliases;
	if($aliases){
		@aliases = split /, /, lc($aliases);
		print $tee "Aliases: ",$aliases, "\n";
	}
	
	my $focusID;
	my @namesakeIDs;
	
	if( ! $authorName ){
		$authorName = $name;
		print $tee "Name being processed: $authorName\n";
	}
	elsif( ! checkNameEqual( [ $name, @aliases ], $authorName) ){
		return -1;
	}
	unshift @aliases, $authorName;
	
	my $focusAuthorID;
	my $focusAffiliation;
	my $focusPaperCount;
	
	# OBSOLETE: var naid = '1170134';
	# <input value="Rakesh-K-Sharma/267587" name="t:ac" type="hidden"></input>
	if( $source !~ m{<input value="[^\"/]+/(\d+)" name="t:ac" type="hidden"></input>} ){
		print $tee "!!! FATAL: Couldn't find author ID in this page. Download error?\n";
		return -1;
	}
	$focusAuthorID = $1;
	
=pod
OBSOLETE:
	The text around Affiliation is like:
	<tr>
      <th valign="top">Affiliation:</th>
      <td>University of North Carolina at Chapel Hill</td>
    </tr>

The text around Affiliation is like:
<dt>Affiliation:</dt><dd>Electrical and Computer Engineering Department, University of Illinois at Urbana Champaign
</dd>    
=cut

	if( $source !~ m{<dt>Affiliation:</dt><dd>([^<>]+)</dd>}s ){
		print $tee "No affiliation found in the page. Use '($focusAuthorID)' instead\n";
		$focusAffiliation = "($focusAuthorID)";
	}
	else{
		$focusAffiliation = restoreXmlEntity( $1 );
		trim($focusAffiliation);
		$focusAffiliation =~ s/ *(\r)?\n */, /g;
		
		# Sometimes the affiliations may be duplicate. e.g. two Bin Yu's are from CS, CMU
		# So in case of it, I append the affiliation with the author ID. It also helps to manually
		# download the page for debugging purposes
		$focusAffiliation .= " ($focusAuthorID)";
	}
    
    # The count appearing in the top of the page like:
    # <th colspan="1" rowspan="1">#Papers:</th><td colspan="1" rowspan="1">727</td>
    # is sometimes inaccurate. Use "ALL (count)" at the publication switching tab instead

=pod
<li class="bigbutton buttonset fm"><a tab="all">
ALL (121)
</a>
=cut

	if( $source !~ m{<li class="bigbutton buttonset fm"><a tab="all">\s*ALL(?:<br clear="none"/>| )\((\d+)\)\s*</a>}s ){
		print $tee "!!! FATAL: no paper count found in the page. Check manually please\n";
		return -1;
	}
	else{
		$focusPaperCount = $1;
	}
	
	# OBSOLETE: div class="na_person selected" title="Bin Yu ..." onclick="location.href='viewperson.do?name=Bin Yu&naid=652767'"
	#while( $source =~ /div class="na_person (selected)?" title="([^\"]+)" onclick="location.href='([^\']+)'"/g ){
=pod
	href="/person/index.napersonselector.search/Rakesh$0020K.$0020Sharma/267589?t:ac=Rakesh-K-Sharma/267587"><img alt="Rakesh K. Sharma" src="http://pic.aminer.org/picture/images/no_photo.jpg"/></a><dl><dt>
4
</dt><dd>
H-index: 1
</dd><dd>
#Papers: 3
</dd><dd>
#Citation: 21
</dd></dl><p class="info">
Northern Illinois univ., DeKalb

</p>

=cut

	while( $source =~ m{
			href="/person/index.napersonselector.search/[^/\"]+/(\d+)(?:;jsessionid=[0-9a-f]+)?\?t:ac=[^\"]+">
			<img\ alt="([^\"]+)"\ src="[^\"]+"/></a><dl><dt>\s*(\d+)\s*</dt>
			<dd>\s*H-index:\ \d+\s*</dd>
			<dd>\s*\#Papers:\ (\d+)\s*</dd>
			<dd>\s*\#Citation:\ \d+\s*</dd></dl>
			<p\ class="info">\s*([^<>]+)</p>
			}sxg 
		){
		my $authorID = $1;
		$name = $2;
		# the sequence number in the disambiguated list
		my $authorNo = $3;
		my $paperCount = $4;
		my $affiliation = $5;
		
		$name =~ s/\d+$//;
		trim($name, $affiliation);
		$affiliation =~ s/ *(\r)?\n */, /g;
		
		if( $paperCount == 0 ){
			# This page contains no paper. no need to queue this author ID.
			# Even if the paper count is 0, as we don't know whether this author is the 
			# focus author (whom the current page refers to), 
			# we still need to see how many papers can be extracted from the current page later
			next;
		}
		
		# queue this author ID, and check if it hasn't been crawled/queued yet.
		# if it hasn't, it'll be crawled later
		push @namesakeIDs, $authorID;
	}
	
	if( ! $focusAffiliation ){
		print $tee "Affiliation of current author is not extracted. Weird\n";
		return -1;
	}
	else{
		print $tee "$focusPaperCount papers, at '$focusAffiliation'\n"
	}
	
	my ($pubsSource) = $source =~ m{<ul id="pub_list" class="ls_publication ls_pub_clearly">(.+?)</div></div></div></div><div class="t-zone" id="updatePublicationOwnerShipZone">}s;
	
	my $readPaperCount = 0;
	
	my $pubs;	# ref to array of pubs
	
=pod
An example publication:
<li pid="3321485" class="s-item" year="2012" style="border-left: solid 2px orange"><span class="num">727</span><p><div class="floatr"><a shape="rect" class="fnbtn2 bibtex s-bibtex" href="#">BIBTEX</a><a shape="rect" rel="nofollow" class="fnbtn2 foaf s-pdf h" href="#">PDF</a></div><a class="title" href="/publication/effects-of-copper-plasticity-on-the-induction-of-stress-in-silicon-from-copper-through-silicon-vias-tsvs-for-d-integrated-circuits-3321485.html">Effects of Copper Plasticity on the Induction of Stress in Silicon from Copper Through-Silicon Vias (TSVs) for 3D Integrated Circuits. </a></p><p><a class="" href="/person/benjamin-backes-14241273.html">Benjamin Backes</a>,
<a class="" href="/person/colin-mcdonough-14156950.html">Colin McDonough</a>,
<a class="" href="/person/larry-smith-71986.html">Larry Smith</a>,
<a class="cur" href="/person/wei-wang-1128214.html">Wei Wang</a>,
<a class="" href="/person/robert-e-geer-1635600.html">Robert E. Geer</a>.
</p><p>
2012,
<a href="/conference/j-electronic-testing-5143.html">J. Electronic Testing, </a>
pp.53~62
</p></li>
=cut

	($readPaperCount, $pubs) = extractPubs($pubsSource, \@aliases, $focusAuthorID);
	
	if($readPaperCount != $focusPaperCount){
		if( $focusPaperCount > 100 && $readPaperCount == 100 ){
			my ($ajaxurl, $zone) = $source =~ m{"PersonPublications":\[\{"updateZoneLink":"[^\"]+","link":"([^\"]+)","zone":"([^\"]+)"\}\]};
			if(! $ajaxurl){
				print $tee "!!! FATAL: this page doesn't contain 'PersonPublications' ajaxurl. Check manually please\n";
				return -1;
			}
			$ajaxurl =~ s/\$0025s/all/g;
			$ajaxurl = DOMAIN . $ajaxurl;
			print $tee "Only $readPaperCount publications are in this page. Getting all via AJAX request\n";

AJAXDOWN:			
			my $jsonSource = uapost( $ajaxurl, { 't:zoneid' => $zone }, "Please check the Internet connection",
									[ "X-Prototype-Version" => "1.7", "X-Requested-With" => "XMLHttpRequest" ] 
								);
			if(!$jsonSource){
				print $tee "$uaErrMsg\n";
				return -1;
			}
			
			my $jsonHash = decode_json($jsonSource);
			my $jsonContent = $jsonHash->{content};
			my @parts = $jsonContent =~ /(<[^<>]+>)([^<>]*)/g;
			
			my $i;
			for($i=0; $i< @parts; $i+=2){
				$parts[$i] =~ s/\'/\"/g;
			}
			my $jsonContent2 = join("", @parts);
			
			($readPaperCount, $pubs) = extractPubs($jsonContent2, \@aliases, $focusAuthorID);
			if($readPaperCount != $focusPaperCount){
				print $tee "Paper counts disagree: found $readPaperCount != said $focusPaperCount\n";
				return -1;
			}
			else{
				my $oldLen = length($_[0]);
				# update the crawled source code
				$_[0] =~ s{(?<=<ul id="pub_list" class="ls_publication ls_pub_clearly">).+?(?=</div></div></div></div><div class="t-zone" id="updatePublicationOwnerShipZone">)}{$jsonContent2}s;
				my $newLen = length($_[0]);
				if($newLen <= $oldLen){
					print $tee "Updating crawled source code failed. Manually check please.\n";
					return -1;
				}
				print $tee "Crawled source code updated. $oldLen bytes -> $newLen bytes\n";
			}
		}
		else{
			print $tee "Paper counts disagree: found $readPaperCount != said $focusPaperCount\n";
			return -1;			
		}
	}
	
	print $tee scalar @$pubs, " valid papers extracted\n";
	
	$_[0] =~ s/;jsessionid=[0-9a-f]+//g;
	
	return ($pubs, \@namesakeIDs, $focusAffiliation);
}

sub confirmAbort
{
	delete $SIG{INT};
	
	print $tee "\n$totalDownPageCount pages downloaded, ", scalar @queue, " pages in the queue. ";
	print $tee "Are you sure you want to exit? (y/N) ";
	my $input = <STDIN>;
	if($input =~ /^y$/i){
		exit;
	}
	else{
		$SIG{INT} = \&confirmAbort;
		return;
	}
}
