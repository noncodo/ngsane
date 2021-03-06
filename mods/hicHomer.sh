#!/bin/bash -e

# Script running HIC HOMER pipeline tapping into bowtie2
# It expects bam files, paired end, as input.
# author: Fabian Buske
# date: August 2013

echo ">>>>> HiC analysis with homer"
echo ">>>>> startdate "`date`
echo ">>>>> hostname "`hostname`
echo ">>>>> job_name "$JOB_NAME
echo ">>>>> job_id "$JOB_ID
echo ">>>>> $(basename $0) $*"

function usage {
echo -e "usage: $(basename $0) -k NGSANE -f bam -o OUTDIR [OPTIONS]"
exit
}
# QCVARIABLES,Resource temporarily unavailable

if [ ! $# -gt 3 ]; then usage ; fi

#INPUTS                                                                                                           
while [ "$1" != "" ]; do
    case $1 in
        -k | --toolkit )        shift; CONFIG=$1 ;; # location of the NGSANE repository
        -f | --bam )            shift; f=$1 ;; # bam file
        -o | --outdir )         shift; OUTDIR=$1 ;; # output dir 
        --recover-from )        shift; RECOVERFROM=$1 ;; # attempt to recover from log file
        -h | --help )           usage ;;
        * )                     echo "don't understand "$1
    esac
    shift
done

#PROGRAMS
. $CONFIG
. ${NGSANE_BASE}/conf/header.sh
. $CONFIG

################################################################################
CHECKPOINT="programs"

for MODULE in $MODULE_HOMERHIC; do module load $MODULE; done  # save way to load modules that itself load other modules

export PATH=$PATH_HOMERHIC:$PATH
module list
echo "PATH=$PATH"
#this is to get the full path (modules should work but for path we need the full path and this is the\
# best common denominator)

echo -e "--NGSANE      --\n" $(trigger.sh -v 2>&1)
echo -e "--samtools    --\n "$(samtools 2>&1 | head -n 3 | tail -n-2)
[ -z "$(which samtools)" ] && echo "[ERROR] no samtools detected" && exit 1
echo -e "--R           --\n "$(R --version | head -n 3)
[ -z "$(which R)" ] && echo "[ERROR] no R detected" && exit 1
echo -e "--homer       --\n "$(which makeTagDirectory)
[ -z "$(which makeTagDirectory)" ] && echo "[ERROR] homer not detected" && exit 1
echo -e "--circos      --\n "$(circos --version)
[ -z "$(which circos)" ] && echo "[WARN] circos not detected"

echo -e "\n********* $CHECKPOINT\n"
################################################################################
CHECKPOINT="parameters"

# get basename of f
n=${f##*/}

#is paired ?                                                                                                      
if [ "$f" != "${f/$READONE/$READTWO}" ] && [ -e ${f/$READONE/$READTWO} ]; then
    PAIRED="1"
else
    PAIRED="0"
fi

if [ $PAIRED == "0" ]; then 
    echo "[ERROR] paired library required for HIC analysis" && exit 1
fi

FASTASUFFIX=${FASTA##*.}

if [ "$HOMER_HIC_INTERACTIONS" != "all" ] && [ "$HOMER_HIC_INTERACTIONS" != "cis" ] && [ "$HOMER_HIC_INTERACTIONS" != "trans" ]; then
    echo "[ERROR] HiC interactions not specified (all, cis or trans) : $HOMER_HIC_INTERACTIONS"
fi

echo -e "\n********* $CHECKPOINT\n"
################################################################################
CHECKPOINT="recall files from tape"

if [ -n "$DMGET" ]; then
	dmget -a ${f/$READONE/"*"}
	dmget -a $OUTDIR/*
fi

echo -e "\n********* $CHECKPOINT\n"
################################################################################

#homer likes to write in the current directory, so change to target
CURDIR=$(pwd)
cd $OUTDIR

################################################################################
CHECKPOINT="create tagdirectory"

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else

    RUN_COMMAND="makeTagDirectory $OUTDIR/${n/%$READONE.$ASD.bam/_tagdir_unfiltered} $f,${f/$READONE/$READTWO} $HOMER_HIC_TAGDIR_ADDPARAM"
    echo $RUN_COMMAND && eval $RUN_COMMAND
    
    cp -r $OUTDIR/${n/%$READONE.$ASD.bam/_tagdir_unfiltered} $OUTDIR/${n/%$READONE.$ASD.bam/_tagdir_filtered}
    
    RUN_COMMAND="makeTagDirectory $OUTDIR/${n/%$READONE.$ASD.bam/_tagdir_filtered} -update $HOMER_HIC_TAGDIR_ADDPARAM"
    echo $RUN_COMMAND && eval $RUN_COMMAND

    # mark checkpoint
    if [ -d $OUTDIR/${n/%$READONE.$ASD.bam/_tagdir_filtered} ];then echo -e "\n********* $CHECKPOINT\n"; unset RECOVERFROM; else echo "[ERROR] checkpoint failed: $CHECKPOINT"; exit 1; fi

fi

################################################################################
CHECKPOINT="create background model"    

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else 
    
    RUN_COMMAND="analyzeHiC $OUTDIR/${n/%$READONE.$ASD.bam/_tagdir_filtered} $HOMER_HIC_BACKGROUND_ADDPARAM -createModel $OUTDIR/${n/%$READONE.$ASD.bam/_background.txt} active.model.txt -cpu $CPU_HOMERHIC"
    echo $RUN_COMMAND && eval $RUN_COMMAND

    # mark checkpoint
    if [ -f $OUTDIR/${n/%$READONE.$ASD.bam/_background.txt} ];then echo -e "\n********* $CHECKPOINT\n"; unset RECOVERFROM; else echo "[ERROR] checkpoint failed: $CHECKPOINT"; exit 1; fi

fi

################################################################################
CHECKPOINT="normalize matrices"    

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else 

    if [ "$HOMER_HIC_INTERACTIONS" == "all" ]; then
        RUN_COMMAND="analyzeHiC $OUTDIR/${n/'_'$READONE.$ASD.bam/_tagdir_filtered} $HOMER_HIC_NORMALIZE_ADDPARAM -model $OUTDIR/${n/'_'$READONE.$ASD.bam/_background.txt}  > $OUTDIR/${n/'_'$READONE.$ASD.bam/_matrix.txt}"
        echo $RUN_COMMAND && eval $RUN_COMMAND
    
    elif [ "$HOMER_HIC_INTERACTIONS" == "cis" ]; then
        [ ! -f $FASTA.fai ] && samtools faidx $FASTA
    
        for CHR in $(awk '{print $1'} $FASTA.fai); do
    	    RUN_COMMAND="analyzeHiC $OUTDIR/${n/'_'$READONE.$ASD.bam/_tagdir_filtered} $HOMER_HIC_NORMALIZE_ADDPARAM -chr $CHR -model $OUTDIR/${n/'_'$READONE.$ASD.bam/_background.txt}  > $OUTDIR/${n/'_'$READONE.$ASD.bam/_${CHR}_matrix.txt}"
    	    echo $RUN_COMMAND && eval $RUN_COMMAND
        done
    elif [ "$HOMER_HIC_INTERACTIONS" == "trans" ]; then
       [ ! -f $FASTA.fai ] && samtools faidx $FASTA
    
        for CHR1 in $(awk '{print $1'} $FASTA.fai); do
            for CHR2 in $(awk '{print $1'} $FASTA.fai); do
                if [ "$CHR1" != "$CHR2" ]; then
                    RUN_COMMAND="analyzeHiC $OUTDIR/${n/'_'$READONE.$ASD.bam/_tagdir_filtered} $HOMER_HIC_NORMALIZE_ADDPARAM -chr $CHR1 -chr2 $CHR2 -model $OUTDIR/${n/'_'$READONE.$ASD.bam/_background.txt}  > $OUTDIR/${n/'_'$READONE.$ASD.bam/_${CHR1}-${CHR2}_matrix.txt}"
                    echo $RUN_COMMAND && eval $RUN_COMMAND
                fi
            done
        done
    fi

    # mark checkpoint
    echo -e "\n********* $CHECKPOINT\n"
fi

################################################################################
CHECKPOINT="PCA clustering"

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else 

    RUN_COMMAND="runHiCpca.pl ${n/%$READONE.$ASD.bam/} $OUTDIR/${n/%$READONE.$ASD.bam/_tagdir_filtered} $HOMER_HIC_PCA_ADDPARAM -cpu $CPU_HOMERHIC "
    echo $RUN_COMMAND && eval $RUN_COMMAND

    # mark checkpoint
    if [ -f $OUTDIR/${n/.$ASD.bam/}-${INPUT}.summary.txt ];then echo -e "\n********* $CHECKPOINT\n"; unset RECOVERFROM; else echo "[ERROR] checkpoint failed: $CHECKPOINT"; exit 1; fi

fi

################################################################################
CHECKPOINT="Significant interactions"

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else 
    
    if [ "$HOMER_HIC_INTERACTIONS" == "all" ]; then
        RUN_COMMAND="analyzeHiC $OUTDIR/${n/'_'$READONE.$ASD.bam/_tagdir_filtered} $HOMER_HIC_INTERACTION_ADDPARAM -interactions $OUTDIR/${n/'_'$READONE.$ASD.bam/_significantInteractions.txt} -nomatrix -cpu $CPU_HOMERHIC "
        echo $RUN_COMMAND && eval $RUN_COMMAND
    
    elif [ "$HOMER_HIC_INTERACTIONS" == "cis" ]; then
        for CHR in $(awk '{print $1'} $FASTA.fai); do
            RUN_COMMAND="analyzeHiC $OUTDIR/${n/'_'$READONE.$ASD.bam/_tagdir_filtered} $HOMER_HIC_INTERACTION_ADDPARAM -chr $CHR -interactions $OUTDIR/${n/'_'$READONE.$ASD.bam/_significantInteractions_$CHR.txt} -nomatrix -cpu $CPU_HOMERHIC "
            echo $RUN_COMMAND && eval $RUN_COMMAND
        done
    
    elif [ "$HOMER_HIC_INTERACTIONS" == "trans" ]; then
        for CHR1 in $(awk '{print $1'} $FASTA.fai); do
            for CHR2 in $(awk '{print $1'} $FASTA.fai); do
                if [ "$CHR1" != "$CHR2" ]; then
                    RUN_COMMAND="analyzeHiC $OUTDIR/${n/'_'$READONE.$ASD.bam/_tagdir_filtered} $HOMER_HIC_INTERACTION_ADDPARAM -chr $CHR1 -chr2 $CHR2 -interactions $OUTDIR/${n/'_'$READONE.$ASD.bam/_significantInteractions_$CHR1-$CHR2.txt} -nomatrix -cpu $CPU_HOMERHIC "
                    echo $RUN_COMMAND && eval $RUN_COMMAND
                fi
            done
        done
    fi

    # mark checkpoint
    if [[ $(ls $OUTDIR/${n/'_'$READONE.$ASD.bam/_significantInteractions_}* |  wc -l ) -ge 1 ]];then echo -e "\n********* $CHECKPOINT\n"; unset RECOVERFROM; else echo "[ERROR] checkpoint failed: $CHECKPOINT"; exit 1; fi
fi

################################################################################
CHECKPOINT="Annotate interactions"

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else 

    RUN_COMMAND="annotateInteractions.pl $OUTDIR/${n/%$READONE.$ASD.bam/_significantInteractions.txt} $HOMER_HIC_ANNOTATE_ADDPARAM $OUTDIR/${n/%$READONE.$ASD.bam/_annotations}"
    echo $RUN_COMMAND && eval $RUN_COMMAND

    # mark checkpoint
    if [ -d $OUTDIR/${n/%$READONE.$ASD.bam/_annotations} ];then echo -e "\n********* $CHECKPOINT\n"; unset RECOVERFROM; else echo "[ERROR] checkpoint failed: $CHECKPOINT"; exit 1; fi

fi

################################################################################
CHECKPOINT="Circos plots (optional)"

if [[ -n "$RECOVERFROM" ]] && [[ $(grep -P "^\*{9} $CHECKPOINT" $RECOVERFROM | wc -l ) -gt 0 ]] ; then
    echo "::::::::: passed $CHECKPOINT"
else 
    if hash ${CIRCOS} 2>&- ; then
        echo "********* Circos plots"
        RUN_COMMAND="analyzeHiC $OUTDIR/${n/%$READONE.$ASD.bam/_tagdir_filtered} -res 1000000 -pvalue 1e-7 -cpu $CPU_HOMERHIC -circos ${n/%$READONE.$ASD.bam/} -minDist 2000000000 -nomatrix"
        echo $RUN_COMMAND && eval $RUN_COMMAND
    fi

    # mark checkpoint
    echo -e "\n********* $CHECKPOINT\n"
fi

################################################################################
# back to where we came from
cd $CURDIR

################################################################################
echo ">>>>> HiC analysis with homer - FINISHED"
echo ">>>>> enddate "`date`

