if [ $# -lt 1 ]
then
	echo "Please specify an author name"
	exit
fi

author=$1

if [ $# -eq 2 ]
then
	saveFile=$2
else
	saveFile="${author,,*}.txt"
fi

echo "Extract publications by '$author' into '$saveFile'.."
grep -C1 --group-separator '' -P "(,|^)$author(,|$| \d)" "dblp.extracted.txt" > "$saveFile"
wc "$saveFile"
