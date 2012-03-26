%conv = ('à' => a, 'é' => e, 'è' => e, 'ç' => c, 'ô' => o, 'ê' => e, 
		 "\xc3\x89" => 'E', 'î' => i, 'â' => a, 'û' => u, "\xe2\x80\x99" => "'",
		 'œ' => oe, 'ï' => i, 
			);

while(<>){
	if($_ =~ m{<dt>(<b>)?(.*?)(<a [^>]+>)?([^<>&]+)(</a>)?(</b>)?([^<]|<[^a])*(&#160;)?</dt>}){
		$w = $4;
		for $k(keys %conv){
			$w =~ s/$k/$conv{$k}/g;
		}
		if($w !~ /[a-z]/){
			next;
		}
		$w =~ s/[(\[].+?[)\]]//g;
		$w =~ s/^\s+|\s+$//g;
		$w =~ s/\s*[!?]$//g;
		if($w =~ / \/ /){
			@phrases = split /\s+\/\s+/, $w;
		}
		else{
			if($w =~ m{\w+/\w}){
				if($w !~ /\s/){
					($p1, $p2) = split /\//, $w;
					@phrases = ($p1, $p1 . $p2);
				}
				else{
					@parts = split /\s/, $w;
					@phrases = (shift @parts);
					for $part(@parts){
						if($part !~ /\//){
							for(@phrases){
								$_ .= " $part";
							}
						}
						else{
							@alts = split /\//, $part;
							for(@phrases){
								for $alt(@alts){
									push @phrases2, "$_ $alt";
								}
							}
							@phrases = @phrases2;
						}
					}
				}
			}
			else{
				if($w =~ /,/){
					print "#$w\n";
				}
				else{
					print "$w\n";
				}
				next;
			}
		}
		for(@phrases){
			if(/,/){
				print "#$_\n";
			}
			else{
				print "$_\n";
			}	
		}
	}
	elsif($_ =~ m{<dt>}){
		print $_;
	}
}
