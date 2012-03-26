my $author2 = { publist => [], keywords => [] };
my $namesake2 = { nameparts => [], prob => 1, authorlist => [],
						authorCount => 1, pubCount => 1 };
my $publication2 = { startLineno => 1, title => 1, pubYear => 1, startYear => 1,
							type => 1, authors => [], keywords => [] };
my $publication3 = { sl => 1, title => 1, py => 1, sy => 1,
							t => 1, a => [], k => [] };

#Test code:			
print "keyword:\t", size(keyword->new), "\t", total_size(keyword->new), "\n";
print "namePart:\t", size(namePart->new), "\t", total_size(namePart->new), "\n";
print "author:\t", size(author->new), "\t", total_size(author->new), "\n";
print "author2:\t", size($author2), "\t", total_size($author2), "\n";

print "namesake:\t", size(namesake->new), "\t", total_size(namesake->new), "\n";
print "namesake2:\t", size($namesake2), "\t", total_size($namesake2), "\n";

print "publication:\t", size(publication->new), "\t", total_size(publication->new), "\n";
print "publication2:\t", size($publication2), "\t", total_size($publication2), "\n";
print "publication3:\t", size($publication3), "\t", total_size($publication3), "\n";

=pod
#Results:
keyword:        120     184
namePart:       120     152
author: 120     296
author2:        139     347
namesake:        152     376
namesake2:       232     488
publication:    152     408
publication2:   285     573
publication3:   248     536
=cut
