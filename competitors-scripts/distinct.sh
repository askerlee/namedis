#!/bin/bash

#perl distinct-keywords.pl $@
perl distinct-venues0.pl $@
perl distinct-authors.pl $@
perl distinct-pubvenuekeywords.pl $@
perl distinct-citation.pl $@ /home/shaohua/wikipedia/useless/dblp.txt
perl distinct-data.pl $@
