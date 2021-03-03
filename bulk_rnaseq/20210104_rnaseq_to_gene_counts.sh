#!/bin/bash
# Date 20210104


# ------------------ USAGE ------------------ 
# ./20210104_rnaseq_to_gene_counts.sh /path/to/sequencing_files /path/to/output_directory

# Example slurm submission (SBATCH options):
# 	--job-name=DATE_rnaseq_to_gene_counts
# 	--output=DATE_rnaseq_to_gene_counts_%A_%a.log
#   --cores=4
#   --threads-per-core=1
# 	--time=12:00:00
# 	--array=0-79:2 ## Number of samples to be processed

# ------------------ Inputs (in order of passing into script) -------------- 
# 		1. Directory where sequencing files are
# 			- within directory, should be a file called filenames.txt, which orders the files sequencially 
# 			 i.e.: Sample1_R1.fastq.gz
#       		       Sample1_R2.fastq.gz
# 		2. Output directory

# ------------------ Outputs ------------------
# 		1. Fastqc results in output directory, as a multiqc html file
# 		2. Kallisto outputs - gene counts

# ------------------ NOTES ------------------ 
# - Script is set to be run as a parallel SLURM script, see sample submission above
# - This pipeline assumes Kallisto already has an indexed reference. See command `kallisto index` for information how to get indexed reference
# 	Ex: kallisto index --i gencode.v31.transcripts.idx ~/reference_genomes/hg38/gencode_GRCh38.p12_release31/gencode.v31.transcripts.fa
# - This pipeline is for PAIRED READ SEQUENCING ONLY, but could be modified for single reads
# - See notebook for importing kallisto abundance files for analysis: /cellar/users/ndefores/analyses/2021113_rnaseq_differential_expression_analysis_from_kallisto.ipynb


### ------------------ Begin pipeline ------------------ 

# Stop the script on errors, unset variables, and on pipefails
set -euo pipefail

## ----------- Point pipeline to files -----------
# directory where sequencing files are
seq_dir=$1

# directory where output should go
out_dir=$2

### ------ Only do this section once ------------------
# if not first element of array, hold while the data checks and fastqc can be done 
if [ $SLURM_ARRAY_TASK_ID -eq 0 ]
then
	# check if seq directory exists, if not exit with error
	if [ ! -d $seq_dir ]
	then
		echo ERROR: $seq_dir not found. Cancelling all jobs...
		scancel $SLURM_ARRAY_JOB_ID
		exit 1
	fi

	# check if output directory exists, if not create it
	if [ ! -d $out_dir ]
	then
		mkdir $out_dir
		echo -e "Created output directory at $out_dir \n"
	fi

	# check that there is a file named "filenames.txt" in files directory, and exit if missing
	if [ $(ls $seq_dir | grep -wc filenames.txt) -eq 0 ]
	then 
		echo ERROR: filenames.txt not found in $seq_dir. Please create file of sequential list of files to be analyzed in $seq_dir. Cancelling all jobs...
		scancel $SLURM_ARRAY_JOB_ID
		exit 1
	fi

	# make directory for kallisto files
	if [ ! -d $out_dir/kallisto_runs ]
	then
		echo -e "Created kallisto output directory at $out_dir/kallisto_runs \n"
		mkdir $out_dir/kallisto_runs
	fi

	## ----------- Quality check sequencing data -----------
	# run fastqc 
	mkdir $out_dir/fastqc_res
	echo -e "Running fastqc...\n"
	/cellar/users/ndefores/software/FastQC/fastqc -o $out_dir/fastqc_res $seq_dir/*.gz

	# run multiqc to summarize
	echo -e "Running multiqc to summarize fastqc results...\n"
	multiqc $out_dir/fastqc_res/

	# move data to output dir
	mv multiqc_* $out_dir/fastqc_res/
else
	echo "Waiting for data checks and data QC to start..."
	sleep 60
fi


## ----------- Run files through Kallisto -----------
# list files into array from file listing filenames
declare -a files=($(cut -f 1 $seq_dir/filenames.txt))

# run all simultaneously: make sure that the array contains number of fastq files to process, by 2
i=$SLURM_ARRAY_TASK_ID

x1="${files[$i]}" # Read 1 
name="${files[$i]%_S*}" # name of output
let t=i+1	
x2="${files[$t]}" # Read 2

echo -e "Running kallisto for sample ${name}...\n"

## ----- Kallisto command -----
kallisto quant -i /cellar/users/ndefores/annotations/hg38/gencode_GRCh38.p12_release31/kallisto_idx/gencode.v31.transcripts.idx -o $out_dir/kallisto_runs/$name --threads=4 -b 20 $seq_dir/$x1 $seq_dir/$x2

echo -e "Running kallisto for sample ${name} complete."