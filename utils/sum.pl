while(<>){
	chomp;
	($a, $b) = split /: /;
	$sum+=$b;
	$c{$a} = $b;
}
@n = sort {$c{$b} <=> $c{$a}} keys %c;
print $sum;
print "\n";
for(@n){
	print "$_: $c{$_}\n";
}
