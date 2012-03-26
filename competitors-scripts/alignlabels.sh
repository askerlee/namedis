for i in *-labels.txt; do
	NAME=$(echo "$i" | sed -e 's/-labels.txt//')
	echo
	echo $NAME:
	grep -q "key:" "$i"
	if [ $? -eq 0 ]; then
		cut -f2 -s "$i"|sort|uniq|wc
		perl align-distinct.pl "$NAME.txt" "$i"
	else
		grep -q "key:" "$NAME.txt"
		if [ $? -ne 0 ]; then
			echo "WARN: $NAME.txt is still in the old format"
		else
			perl align.pl "$NAME.txt" "$i"
		fi
	fi
done
