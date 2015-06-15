#!/bin/bash

# Dependencies: bowtie2, samtools, seqtk
# Some code borrowed from https://wikis.utexas.edu/display/bioiteam/Example+BWA+alignment+script

# Test if the correct number of input files are specified
DATABASE=0
DELETE=1
NAME=0
FORWARD=0
REVERSE=0
UNPAIRED=0

HELP="""
	Made by: Alvar Almstedt & Mats Töpel

	-d	:	Database to be used for mapping to with bowtie2*
	-u	:	Unpaired read library**
	-1	:	Forward reads (paired)**
	-2	:	Reverse reads (paired)**
	-n	:	User specified analysis Name*
	-k	:	Keep intermediary *.sam files, else deleted after analysis
	-h	:	Help (what you are reading now)

*: Mandatory options
**: Either -1 and -2 for paired libraries or -u for unpaired. One of the two options are mandatory.

"""

while getopts :d:u:1:2:n:kh opt; do
  case $opt in
	d)
		echo "-d (database) was input as $OPTARG" >&2
		DATABASE=$OPTARG
	;;
	u)
		echo "-u (unpaired) was input as $OPTARG" >&2
		UNPAIRED=$OPTARG
	;;
	1)
		echo "-1 (forward) was input as $OPTARG" >&2
		FORWARD=$OPTARG
	;;
	2)
		echo "-2 (reverse) was input as $OPTARG" >&2
		REVERSE=$OPTARG
	;;
	n)
		echo "-n (name) was input as $OPTARG" >&2
		NAME=$OPTARG
	;;
	k)
		echo "-k (keep) was triggered, sam files will be kept" >&2
		DELETE=0
	;;
	h)
		echo "$HELP"
		exit 1
	;;
	\?)
		echo "Invalid option: -$OPTARG" >&2
		echo "Type $0 -h for usage"
		exit 1
	;;
  esac
done

if [ $DATABASE = 0 ] ; then
	echo "You must specify a database file. Write $0 -h for usage"
	exit 1
fi

if [ $NAME = 0 ] ; then
	echo "You must specify a name for your analysis. Write $0 -h for usage."
	exit 1
fi

if [ $FORWARD = 0 ] || [ $REVERSE = 0 ] && [ $UNPAIRED = 0 ] ; then
	echo "Paired libraries need forward and reverse files, otherwise do an unpaired analysis. Write $0 for usage"
	exit 1
fi

# bowtie2 [options]* -x <bt2-idx> {-1 <m1> -2 <m2> | -U <r>} [-S <sam>]

# shift $((OPTIND-1))


#if [ "$2" == "" ]; then
#
#	echo ""
#	echo "Usage: $0 <reference>.fasta <file1>.fastq [<file2>.fastq]"
#	echo ""
#	echo "	A reference fasta file and one (for singlets)" 
#	echo "	or two (paired end) fastq files are required."
#	echo ""
#	exit 1;
#fi

#	echo -n "Name of output directory: "
#	read NAME

#	echo -n "Remove *.sam files after completion? (y/n): "
#	read DELETE

# Print some informative error meassages
err() {
    echo "$1 exited unexpectedly";
    exit 1;
}

# Function for checking the exit code of a child process
ckeckExit() {
if [ "$1" == "0" ]; then
	echo "[Done] $2 `date`";
else
	err "[Error] $2 returned non-0 exit code $1";
fi
}

# Assigns names to variables
DATE=`date +%C%y_%m_%d`
SAM_FULL=mapping_full_$DATE.sam
SAM_MAPPER=mappers_$DATE.sam
SAM_NON_MAPPER=non_mappers_$DATE.sam
LIST_MAPPER=mappers_$DATE.lst
LIST_NON_MAPPER=non_mappers_$DATE.lst
LIST_TRUE_NON_MAPPER=non_mapper.lst
LIST_TRUE_MAPPER=mapper.lst
OUTDIR="$NAME"_$DATE
MAPPING_INFO=README_mapping.txt

# Creates a bowtie2 database and names it by date and a random number
files=$(ls "$DATABASE".?.bt2 2> /dev/null | wc -l)
if [ "$files" = "0" ]; then
	echo "[info] Creating bowtie2 database..."
	bowtie2-build -f $DATABASE $DATABASE
	ckeckExit $? "bowtie2-build"
else
	echo "[info] bowtie2 database aready exists, proceeding..." 
fi
wait

mkdir $OUTDIR

# Starts bowtie2 mapping
if [ $FORWARD != 0 ] || [ $REVERSE != 0 ] ; then
	echo "[info] Running bowtie2 mapping on paired libraries..."
	bowtie2 -x $DATABASE -1 $FORWARD -2 $REVERSE -S $OUTDIR/$SAM_FULL 2> $OUTDIR/$MAPPING_INFO
	ckeckExit $? "bowtie2"
	wait
else
	echo "[info] Running bowtie2 mapping on unpaired library..."
	bowtie2 -x $DATABASE -U $UNPAIRED -S $OUTDIR/$SAM_FULL 2> $OUTDIR/$MAPPING_INFO
	ckeckExit $? "bowtie2"
	wait
fi


# Splits the sam files into mappers and non_mappers
	echo "[info] Separating sam files..."
	samtools view -S -F4 $OUTDIR/$SAM_FULL > $OUTDIR/$SAM_MAPPER &
	    ckeckExit $? "samtools"
	samtools view -S -f4 $OUTDIR/$SAM_FULL > $OUTDIR/$SAM_NON_MAPPER &
	    ckeckExit $? "samtools"
	wait

# Creates directories for the lists and reads to go in
	mkdir $OUTDIR/lists
	mkdir $OUTDIR/mapped_reads
	mkdir $OUTDIR/non_mapped_reads
	mkdir $OUTDIR/half_mapped_reads

# Makes lists containing the headers of the mapping and non_mapping reads
	echo "[info] Creating lists..."
	cut -f1 $OUTDIR/$SAM_MAPPER | sort | uniq > $OUTDIR/lists/"$NAME"_$LIST_MAPPER &
	    ckeckExit $? "cut"
	cut -f1 $OUTDIR/$SAM_NON_MAPPER | sort | uniq > $OUTDIR/lists/"$NAME"_$LIST_NON_MAPPER &
	    ckeckExit $? "cut"
	wait

if [ $FORWARD != 0 ] || [ $REVERSE != 0 ] ; then
# Removes half_mapper duplicates from the mapping reads
	diff $OUTDIR/lists/"$NAME"_$LIST_NON_MAPPER $OUTDIR/lists/"$NAME"_$LIST_MAPPER | grep "> " | sed "s/> //g" > $OUTDIR/lists/"$NAME"_$LIST_TRUE_MAPPER
	    ckeckExit $? "diff, grep or sed"
	wait

# Removes half_mapper duplicates from the non_mapping reads
	diff $OUTDIR/lists/"$NAME"_$LIST_NON_MAPPER $OUTDIR/lists/"$NAME"_$LIST_MAPPER | grep "< " | sed "s/< //g" > $OUTDIR/lists/"$NAME"_$LIST_TRUE_NON_MAPPER
	    ckeckExit $? "diff, grep or sed"
	wait

# Creates temporary file for the lists to be concatenated in
	touch $OUTDIR/lists/temp.lst

# Redirects/appends mappers and non_mappers to the temp file
	cat $OUTDIR/lists/"$NAME"_$LIST_MAPPER > $OUTDIR/lists/temp.lst
	    ckeckExit $? "cat"
	cat $OUTDIR/lists/"$NAME"_$LIST_NON_MAPPER >> $OUTDIR/lists/temp.lst
	    ckeckExit $? "cat"
	wait

# Redirects only the duplicate lines to the half_mapper list
	sort $OUTDIR/lists/temp.lst | uniq -d > $OUTDIR/lists/"$NAME"_half_mappers.lst
	    ckeckExit $? "sort"
	wait

# Comment the following three lines out if you want to double-check list numbers
	rm $OUTDIR/lists/temp.lst
	rm $OUTDIR/lists/"$NAME"_$LIST_MAPPER
	rm $OUTDIR/lists/"$NAME"_$LIST_NON_MAPPER
	wait
else
	echo "[info] Unpaired libraries will not produce half_mappers, proceeding..."
	rmdir $OUTDIR/half_mapped_reads
fi
# Pulling mapped reads from libraries
	echo "[info] Fetching reads..."


if [ $FORWARD != 0 ] || [ $REVERSE != 0 ] ; then
	seqtk subseq $FORWARD $OUTDIR/lists/"$NAME"_$LIST_TRUE_MAPPER > $OUTDIR/mapped_reads/"$NAME"_mappers_$FORWARD &
	    ckeckExit $? "seqtk"
	seqtk subseq $REVERSE $OUTDIR/lists/"$NAME"_$LIST_TRUE_NON_MAPPER > $OUTDIR/mapped_reads/"$NAME"_mappers_$REVERSE &
	    ckeckExit $? "seqtk"
	wait

# Pulling non_mapped reads from libraries
	seqtk subseq $FORWARD $OUTDIR/lists/"$NAME"_$LIST_TRUE_NON_MAPPER > $OUTDIR/non_mapped_reads/"$NAME"_non_mappers_$FORWARD &
	    ckeckExit $? "seqtk"
	seqtk subseq $REVERSE $OUTDIR/lists/"$NAME"_$LIST_TRUE_NON_MAPPER > $OUTDIR/non_mapped_reads/"$NAME"_non_mappers_$REVERSE &
	    ckeckExit $? "seqtk"
	wait

# Pulling half_mapped reads from libraries
	seqtk subseq $FORWARD $OUTDIR/lists/"$NAME"_half_mappers.lst > $OUTDIR/half_mapped_reads/"$NAME"_half_mappers_$FORWARD &
	    ckeckExit $? "seqtk"
	seqtk subseq $REVERSE $OUTDIR/lists/"$NAME"_half_mappers.lst > $OUTDIR/half_mapped_reads/"$NAME"_half_mappers_$REVERSE &
	    ckeckExit $? "seqtk"
	wait

else
	seqtk subseq $UNPAIRED $OUTDIR/lists/"$NAME"_$LIST_MAPPER > $OUTDIR/mapped_reads/"$NAME"_mappers_$UNPAIRED &
	ckeckExit $? "seqtk"
	seqtk subseq $UNPAIRED $OUTDIR/lists/"$NAME"_$LIST_NON_MAPPER > $OUTDIR/non_mapped_reads/"$NAME"_non_mappers_$UNPAIRED &
	ckeckExit $? "seqtk"
	wait
fi

# Deletes intermediary *.sam files if desired
if [[ $DELETE = 1 ]] ; then
	echo "[info] Removing intermediary sam files..."
	rm $OUTDIR/*.sam
    else
	echo "[info] Keeping sam files"
fi

echo "Finished running bowtie2 mapping and filtering $(date)"
