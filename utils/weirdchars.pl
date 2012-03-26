open(DATA, "< $ARGV[0]");

binmode(DATA);

while(!eof(DATA)){
	read(DATA, $c, 1);
	if(ord($c) > 0x80 && !$printed{$c}){
		$printed{$c} = 1;
	}
}
@chars = sort { ord($a) <=> ord($b) } keys %printed;
for(@chars){
	printf "%X\n", ord($_);
}
