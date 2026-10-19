# SLAM-seq data analysis

This repository contains scripts to analyse SLAM-seq data on Alliance Canada servers.

To install the scripts on Alliance Canada servers and download genomes, see [INSTALL.md](INSTALL.md)

> [!WARNING]
> Many scripts requires a `genome` argument. This is not yet documented here.

### Steps

1. [Samplesheet](#samplesheet)
2. [Transfer data to scratch](#transfer-data-to-scratch)
3. [Prepare working environment](#prepare-working-environment)
   1. [Set additional variables](#set-additional-variables)
4. [Convert samplesheet to other formats](#convert-samplesheet-to-other-formats)
5. [Trimming reads](#trimming-reads)
6. [Reverse complement (if needed)](#reverse-complement-if-needed)
7. [Sequencing data quality check](#sequencing-data-quality-check)
8. [Finding major isoform (Optional)](#finding-major-isoform-optional)
9. [Align reads and process TC mutations](#align-reads-and-process-tc-mutations)
   1. [SlamDunk](#slamdunk)
   2. [Count multiple TC mutations](#count-multiple-tc-mutations)
   3. [Alleyoop](#alleyoop)
   4. [MultiQC (check Alleyoop output)](#multiqc-check-alleyoop-output)
   5. [Count no TC mutations](#count-no-tc-mutations)
10. [Create BigWig for use on Genome Browser](#create-bigwig-for-use-on-genome-browser)
11. [Correlation for samples and dataset](#correlation-for-samples-and-dataset)
12. [MultiQC](#multiqc)

## Samplesheet

* Here is an example of a samplesheet file [samplesheet.csv](samplesheet.csv).

You must create a samplesheet with at least the following columns in CSV format.

```text
sample    Sample name
```

## Transfer data to scratch

You will need to transfer the following files on the server in the `scratch` folder.

* Samplesheet file.
* FASTQ files.
* Genome files (FASTA and GTF). See [Genomes](https://github.com/BenMartinLab/genomes).
    * Copy `slamdunk` folder for your genome.
* Any additional files that are needed for your analysis.

There are many ways to transfer data to the server. Here are some suggestions.

* Use an FTP software like [WinSCP](https://winscp.net) (Windows), [Cyberduck](https://cyberduck.io) (Mac), [FileZilla](https://filezilla-project.org).
* Use command line tools like `rsync` or `scp`.

## Prepare working environment

Add SLAM-seq scripts folder to your PATH.

```shell
export PATH=/project/def-bmartin/scripts/slamseq:$PATH
```

### Set additional variables

> [!IMPORTANT]
> Change `samplesheet.csv` by your actual samplesheet filename.

```shell
samplesheet=samplesheet.csv
```

> [!WARNING]
> `samples_array` does not contain the right values - Elie used array=0-20 and array=0-41 depending on the scripts.

> [!WARNING]
> A `dataset_array` should also be created - Elie used array=0-11

```shell
samples_array=$(awk -F ',' \
    'NR > 1 && !seen[$1] {ln++; seen[$1]++} END {print "0-"ln-1}' \
    "$samplesheet")
```

> [!IMPORTANT]
> Change `hg38-spike-dm6` by your actual genome name.

```shell
genome=hg38-spike-dm6
```

> [!IMPORTANT]
> Change `dm6` by your actual spike-in genome name.

```shell
spike=dm6
```

## Convert samplesheet to other formats

The samplesheet file must be converted to other formats to run the pipeline. Simply run the following command.

> [!WARNING]
> `convert-samplesheet.py` does not exists yet.

```shell
convert-samplesheet.py $samplesheet
```

## Trimming reads

```shell
sbatch --array=samples_array bbduk.sh
```

## Reverse complement (if needed)

```shell
sbatch --array=samples_array reverse-complement-bbduk.sh
```

## Sequencing data quality check

```shell
sbatch fastqc.sh
```

## Finding major isoform (Optional)

```shell
sbatch salmon-index.sh
sbatch --array=samples_array salmon-quant.sh
sbatch salmon-quantmerge.sh
python salmon-addgene.py --output salmon-quant/salmon-quantmerge-genes.txt --gtf $genome.gtf salmon-quant/salmon-quantmerge.txt
```

## Align reads and process TC mutations

### SlamDunk

```shell
sbatch --array=samples_array slamdunk.sh
```

### Count multiple TC mutations

> [!TIP]
> Reads with multiple TC mutations are more likely to be nascent RNAs than those with a single mutation.

```shell
sbatch slamdunk-count2.sh
```

### Alleyoop

```shell
sbatch alleyoop.sh
```

### MultiQC (check Alleyoop output)

Run MultiQC to get an HTML output from Alleyoop. This will make it easier to see if SlamDunk succeeded.

```shell
sbatch multiqc.sh
```

### Count no TC mutations

> [!TIP]
> Reads with no TC mutations are more likely to be old RNAs.

```shell
python substract-alleyoop-count.py --total slamdunk/alleyoop/merge_totalreadcount.tsv --one slamdunk/alleyoop/merge_onetcreadcount.tsv --output slamdunk/alleyoop/merge_zeroreadcount.tsv
```

## Create BigWig for use on [Genome Browser](https://genome.ucsc.edu/)

Negate scores on negative strands in BedGraph files create by SlamDunk.

```shell
sbatch negate-bedGraph.sh
```

Convert BedGraph files to BigWig.

```shell
sbatch bedGraphToBigWig.sh
```

### Compute scale factors manually in Excel file based on read counts.

> [!WARNING]
> This section is using old code from François SLAM-seq pipeline and should be updated.

```shell
sbatch --array=samples_array filter-bam-mutation-count.sh
sbatch --array=samples_array genome-coverage.sh
sbatch --array=samples_array genome-coverage.sh samples.txt $genome.chrom.sizes scale-factors-spikein.txt slamdunk -spikein
sbatch --array=dataset_array merge-bw.sh
copy-mutations-bw.sh
```

## Correlation for samples and dataset

```shell
sbatch correlation-summary.sh
sbatch correlation-pca.sh
sbatch correlation-plot.sh
sbatch --array=dataset_array correlation-dataset.sh
```

## MultiQC

You may want to run MultiQC again to get the correlations in the report.

```shell
rm -rf multiqc
sbatch multiqc.sh
```
