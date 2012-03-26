for i in arnet/*-arnet.txt; do
	NAME=$(echo "$i" | sed -e 's/arnet\///' -e 's/-arnet.txt//')
	echo $NAME:
	perl alignarnet.pl "$NAME-labels.txt" "$i"
	echo
done
