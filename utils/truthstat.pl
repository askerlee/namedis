# list the venues and coauthors of big clusters
# and their common venues/coauthors

use feature qw(switch say);
use warnings 'all';
use strict;
use lib '.';
use NLPUtil;

use lib "/media/first/wikipedia";
use ConceptNet;

if(@ARGV < 2){
	die "Usage: $0 [-a(range)|-v] xxx-labels.txt\n";
}

my $flag;
my $listCoauthors = 0;
my $listVenues = 0;
my $yearThres = 0;
my @focusClustNos;
my $focusAuthor;

while(@ARGV > 1){
	$flag = shift @ARGV;
	given($flag){
		when(/-a(.+)/){
			$listCoauthors = 1;	
			# @focusClustNos are by the SN of clusters of the same author (split into many clusters) in the label file
			@focusClustNos = split /,/, $1;
			@focusClustNos = sort { $a <=> $b } @focusClustNos;
			break;
		}
		when(/-c(.+)/){
			$listCoauthors = 2;	
			# @focusClustNos are by the cluster number in the label file
			@focusClustNos = split /,/, $1;
			@focusClustNos = sort { $a <=> $b } @focusClustNos;
			break;
		}
		when(/-v/){
			$listVenues = 1;
			break;
		}
		when(/-y(\d+)/){
			$yearThres = $1;
		}
		default{
			die "Unknown flag '$flag'\n";
		}
	}
}

loadNameCoauthors("coauthor-stat.txt");
loadGroundtruth($ARGV[0]);

sub computeCoauthorOverlap($$$$;$)
{
	my ($cno1, $cno2, $stat1, $stat2, $doClustering) = @_;
	
	my ($cocount1, $cocount2, $collaborativeCoCount1, $collaborativeCoCount2, $sharecount);
	
	my @coauthors1 = grep { $_ ne $focusAuthor && $_ ne "NO" } keys %$stat1;
	my @coauthors2 = grep { $_ ne $focusAuthor && $_ ne "NO" } keys %$stat2;
	my @collaborativeCoauthors1 = grep { $cnCoauthorCount{$_} >= 38 } @coauthors1;
	my @collaborativeCoauthors2 = grep { $cnCoauthorCount{$_} >= 38 } @coauthors2;
	
	$cocount1 = @coauthors1;
	$cocount2 = @coauthors2;
	$collaborativeCoCount1 = @collaborativeCoauthors1;
	$collaborativeCoCount2 = @collaborativeCoauthors2;
	
	my @sharedCoauthors = intersectHash($stat1, $stat2);
	@sharedCoauthors = grep { $_ ne $focusAuthor && $_ ne "NO" } @sharedCoauthors;
	$sharecount = @sharedCoauthors;
	
	if($sharecount == 0){
		return 0;
	}
	
	print STDERR "$cno1($cocount1 / $collaborativeCoCount1) $cno2($cocount2 / $collaborativeCoCount2) share $sharecount, ", 
					trunc(3, $sharecount / $cocount1), " & ", trunc(3, $sharecount / $cocount2), 
					":\n";
	
	if(@sharedCoauthors){
		print STDERR join(", ", map { "$_($cnCoauthorCount{$_}): $stat1->{$_}{q}, $stat1->{$_}{f}-$stat1->{$_}{t}" } @sharedCoauthors), "\n";
		print STDERR join(", ", map { "$_($cnCoauthorCount{$_}): $stat2->{$_}{q}, $stat2->{$_}{f}-$stat2->{$_}{t}" } @sharedCoauthors), "\n";
	}
	
	if($doClustering){
		my @clusters = clusterAuthors(@sharedCoauthors);
		my ($cluster, $i, $j);
		$j = 1;
		for($i = 0; $i < @clusters; $i++){
			$cluster = $clusters[$i];
			next if !$cluster;
			print STDERR "Cluster $i:\n";
			print STDERR join("\t", @$cluster), "\n";
			$j++;
		}
	}
	
	return scalar @sharedCoauthors;
}

sub loadGroundtruth
{
	my $truthFilename = shift;
	print $tee "Open groundtruth file '$truthFilename' to process...\n";

	my $DB;
	if(! open_or_warn($DB, "< $truthFilename")){
		return;
	}
	
	$truthFilename =~ /([^\-]+)-/;
	$focusAuthor = $1;
	
	die "Unknown format of filename: '$truthFilename'\n" if !$focusAuthor;
	
	print STDERR "Focus author: $focusAuthor\n";
	
	my $expectClusterHeading = 1;
	my $line;
	my ($clustID, $clustSize, $identity);
	my $authorID;
	
	$clustSize = 0;
	my $readcount = 0;
	
	my $title;
	my $year;
	my $venue;
	my $authorLine;
	my $yearVenueLine;
	my $thisPublication;
	my @authorNames;

	my $alignedCount = 0;
	my $unalignedCount = 0;
	my $totalPubCount = 0;
	my $unidentifiedCount = 0;
	
	my %venueStat;
	my %coauthorStat;
	my @coauthorStats;
	my %coauthorStats;
	my @clustIDs = ("BUG");
	
	my $clustNo = 0;
	my $clustStartLn;
	
	my $author;
	
	while(!eof($DB)){
		$line = <$DB>;
		trim($line);
		if(!$line){
			if($readcount != $clustSize){
				print $tee "$clustStartLn: Cluster size $clustSize != $readcount (read count)\nStop reading the file.\n";
				return 0;
			}
			$readcount = 0;

			$expectClusterHeading = 1;
			
			if($identity){
				if($listVenues){
					print STDERR "$identity(", scalar keys %venueStat, "):\n";
					print STDERR dumpSortedHash(\%venueStat, undef, undef);
					print STDERR "\n\n";
				}
				elsif($listCoauthors){
=pod					
					print STDERR "$identity(", scalar keys %coauthorStat, "):\n";
					print STDERR 
					dumpSortedHash(\%coauthorStat, 
						sub{ 
							return $coauthorStat{$_[1]}{q} cmp $coauthorStat{$_[0]}{q};
						},
						sub{
							#return "$_[0]: $coauthorStat{$_[0]}{q}, $coauthorStat{$_[0]}{f}-$coauthorStat{$_[0]}{t}";
							return "$_[0]: $coauthorStat{$_[0]}{q}";
						}
					);
					print STDERR "\n\n";
=cut
					$coauthorStat{NO} = $clustNo;
					push @{ $coauthorStats{$identity} }, { %coauthorStat };
					push @coauthorStats, { %coauthorStat };
					push @clustIDs, $identity;
				}
			}
			# at the beginning of the file, since there's blank line, $coauthorStats[0] will be assigned to the empty hash
			# so valid numbering of clusters is from 1 as well
			else{
				push @coauthorStats, { %coauthorStat };
			}
						
			$clustNo++;
			
			%venueStat = ();
			%coauthorStat = ();
			next;
		}
		
		if($. == 1 && $line =~ /^\d+ clusters\.$/){
			next;
		}
		
		if($expectClusterHeading){
			if($line =~ /Cluster (\d+), (\d+) papers:(\s+(.+))?$/){
				$clustID = $1;
				$clustSize = $2;
				$identity = $4;
				if($identity =~ m{^N/A}){
					$identity = undef;
				}
				else{
					$identity =~ tr/()/[]/;
				}
				
#				$identity ||= "cluster $clustID";
				
				$expectClusterHeading = 0;
				
				$clustStartLn = $.;
				
				next;
			}
			else{
				print $tee "$.: Unknown cluster heading:\n$line\nStop reading the file.\n";
				return 0;
			}
		}
		
		$title = $line;
		$authorLine = <$DB>;
		$yearVenueLine = <$DB>;
		
		$totalPubCount++;
		
		trim($authorLine, $yearVenueLine);
		
		$thisPublication = parseDBLPBlock($title, $authorLine, $yearVenueLine);
		
		$readcount++;
		
		$title = $thisPublication->title;
		trimPunc($title);
		
		$year  = $thisPublication->year;
				
		$venue = $thisPublication->venue;
		
		$venueStat{$venue}++;
		
		for $author(@{ $thisPublication->authors }){
			#next if $author eq $focusAuthor;
			$coauthorStat{$author}{q}++;
			updateYearRange($coauthorStat{$author}, $year);
		}
		
		$identity ||= $thisPublication->authorID;
	}
	
	if($listCoauthors){
		my ($i, $j, $k, $cno1, $cno2);
		for($i = 0; $i < @focusClustNos; $i++){
			$cno1 = $focusClustNos[$i];
			
			if( ! defined($clustIDs[$cno1]) || $listCoauthors == 2 ){
				for($j = $i + 1; $j < @focusClustNos; $j++){
					next if $i == $j;
					
					$cno2 = $focusClustNos[$j];
					my $stat1 = $coauthorStats[$cno1];
					my $stat2 = $coauthorStats[$cno2];
					
					computeCoauthorOverlap($cno1, $cno2, $stat1, $stat2);
				}
			}
			else{
				$identity = $clustIDs[$cno1];
				my @coauthorStats = @{ $coauthorStats{$identity} };

				for($j = 0; $j < @coauthorStats; $j++){
					my $stat1 = $coauthorStats[$j];
					$cno1 = $stat1->{NO};
					
					for($k = $j + 1; $k < @coauthorStats; $k++){
						my $stat2 = $coauthorStats[$k];
						$cno2 = $stat2->{NO};
						
						computeCoauthorOverlap($cno1, $cno2, $stat1, $stat2);
					}
				}
			}
		}
	}
}

