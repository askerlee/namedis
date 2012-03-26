use List::Util qw(sum);

sub trunc
{
	my $prec = shift;
	my @results;
	
	for(@_){
		push @results, 0 + sprintf("%.${prec}f", $_);
	}
	return @results;
}

@a = qw(
1 4 4 6 6 12 4 12 12 4 1 4 6 4 1
);

$s = sum(@a);
$ep = 0;
for $f(@a){
	$ep += ($f / $s) ** 2;
}

ratio($ep, @a);

$uniform = 1 /  scalar @a;
ratio($uniform, @a);

sub ratio
{
	my $base = shift;
	my @a = @_;
	my $s = sum(@a);
	print join(", ", $s, trunc(4, $base)), "\n";
	for $f(@a){
		print "$f, ", trunc(4, $f / $s / $base), "\n";
	}
	print "\n";
}
