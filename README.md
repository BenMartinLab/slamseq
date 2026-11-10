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
fastq1    Path to FastQ file for reads 1. 
fastq2    Path to FastQ file for reads 2 (leave empty if you have single-end reads)
```

FASTQ files have to be gzipped and have the extension “.fastq.gz” or “.fq.gz”.

## Transfer data to scratch

You will need to transfer the following files on the server in the `scratch` folder.

* Samplesheet file.
* FASTQ files.
* FASTA file containing the adapter sequences.
* Genome files (FASTA and GTF). See [Genomes](https://github.com/BenMartinLab/genomes).
    * Copy `slamdunk` folder for your genome.
* Any additional files that are needed for your analysis.

There are many ways to transfer data to the server. Here are some suggestions.

* Use an FTP software like [WinSCP](https://winscp.net) (Windows), [Cyberduck](https://cyberduck.io)
  (Mac), [FileZilla](https://filezilla-project.org).
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

> [!IMPORTANT]
> Change `adapters.fa` by your actual adapters FASTA filename.

```shell
adapters=adapters.fa
```

```shell
cpus=$(cpus-slamseq.sh -s "$samplesheet" -m 64)
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

The samplesheet file must be converted to other formats to run the pipeline. Simply run the
following command.

```shell
convert-samplesheet.py $samplesheet
```

> [!IMPORTANT]
> If your sequences need to be reversed complement, use this command instead.

```shell
convert-samplesheet.py $samplesheet --fastq bbduk-rc
```

## Trimming reads

```shell
sbatch bbduk.sh \
    --samplesheet $samplesheet \
    ref=$adapters \
    k=13 \
    ktrim=r \
    mink=5 \
    qtrim=r \
    trimq=10 \
    minlength=20
```

## Reverse complement (if needed)

```shell
sbatch seqtk-seq.sh \
    --samplesheet $samplesheet \
    --fastq-dir bbduk \
    -r
```

## Sequencing data quality check

```shell
sbatch fastqc.sh ./*.fastq.gz bbduk*/*.fastq.gz
```

## Finding major isoform (Optional)

> [!WARNING]
> Salmon scripts do not work right now.

```shell
sbatch salmon-index.sh
sbatch --array=samples_array salmon-quant.sh
sbatch salmon-quantmerge.sh
python salmon-addgene.py --output salmon-quant/salmon-quantmerge-genes.txt --gtf $genome.gtf salmon-quant/salmon-quantmerge.txt
```

## Align reads and process TC mutations

### SlamDunk

```shell
sbatch slamdunk.sh all \
    --outputDir slamdunk \
    --reference "$genome.fa" \
    --bed "$genome-transcripts.bed" \
    --trim-5p 5 \
    --topn 100 \
    --multimap \
    --min-coverage 10 \
    --var-fraction 0.8 \
    --max-read-length 151 \
    --min-base-qual 26 \
    --skip-sam \
    "$(basename samplesheet .csv).slamdunk.csv"
```

### Count multiple TC mutations

> [!TIP]
> Reads with multiple TC mutations are more likely to be nascent RNAs than those with a single
mutation.

```shell
mv slamdunk/count slamdunk/count_onetcreadcount
```

```shell
sbatch --cpus-per-task="$cpus" --mem="$((cpus * 2))G" slamdunk.sh count \
    --outputDir slamdunk/count_twotcreadcount \
    --reference "$genome.fa" \
    --bed "$genome-transcripts.bed" \
    --max-read-length 151 \
    --min-base-qual 26 \
    --conversion-threshold 2 \
    slamdunk/filter/*.bam
```

### Alleyoop

> [!TIP]
> All methods for Alleyoop can be launched in parallel.

#### rates

```shell
sbatch --cpus-per-task="$cpus" --mem="${cpus}G" alleyoop.sh rates \
    --outputDir slamdunk/alleyoop/rates \
    --reference "$genome.fa" \
    --min-basequality 26 \
    slamdunk/filter/*.bam
```

#### tccontext

```shell
sbatch --cpus-per-task="$cpus" --mem="${cpus}G" alleyoop.sh tccontext \
    --outputDir slamdunk/alleyoop/tccontext \
    --reference "$genome.fa" \
    --min-basequality 26 \
    slamdunk/filter/*.bam
```

#### utrrates

```shell
sbatch --cpus-per-task="$cpus" --mem="${cpus}G" alleyoop.sh utrrates \
    --outputDir slamdunk/alleyoop/utrrates \
    --reference "$genome.fa" \
    --bed "$genome-transcripts.bed" \
    --multiTCStringency \
    --max-read-length 151 \
    --min-basequality 26 \
    slamdunk/filter/*.bam
```

#### snpeval

```shell
sbatch --cpus-per-task="$cpus" --mem="${cpus}G" alleyoop.sh snpeval \
    --outputDir slamdunk/alleyoop/snpeval \
    --snp-directory slamdunk/snp \
    --reference "$genome.fa" \
    --bed "$genome-transcripts.bed" \
    --min-coverage 10 \
    --var-fraction 0.8 \
    --multiTCStringency \
    --max-read-length 151 \
    --min-base-qual 26 \
    slamdunk/filter/*.bam
```

#### summary

```shell
sbatch --cpus-per-task="$cpus" --mem="${cpus}G" alleyoop.sh summary \
    --output slamdunk/alleyoop/summary_onetcreadcount.tsv \
    --tcountDir slamdunk/count_onetcreadcount \
    slamdunk/filter/*.bam
```

#### summary for >2 T>C conversions

```shell
sbatch --cpus-per-task="$cpus" --mem="${cpus}G" alleyoop.sh summary \
    --output slamdunk/alleyoop/summary_twotcreadcount.tsv \
    --tcountDir slamdunk/count_twotcreadcount \
    slamdunk/filter/*.bam
```

#### merge total read count

```shell
sbatch --cpus-per-task="$cpus" --mem="${cpus}G" alleyoop.sh merge \
    --output slamdunk/alleyoop/merge_totalreadcount.tsv \
    --column ReadCount \
    slamdunk/count_onetcreadcount/*.tsv
```

#### merge TC read count

```shell
sbatch --cpus-per-task="$cpus" --mem="${cpus}G" alleyoop.sh merge \
    --output slamdunk/alleyoop/merge_onetcreadcount.tsv \
    --column TcReadCount \
    slamdunk/count_onetcreadcount/*.tsv
```

#### merge >2 TC read count

```shell
sbatch --cpus-per-task="$cpus" --mem="${cpus}G" alleyoop.sh merge \
    --output slamdunk/alleyoop/merge_twotcreadcount.tsv \
    --column TcReadCount \
    slamdunk/count_twotcreadcount/*.tsv
```

#### tcperreadpos

```shell
sbatch --cpus-per-task="$cpus" --mem="${cpus}G" alleyoop.sh tcperreadpos \
    --outputDir slamdunk/alleyoop/tcperreadpos \
    --reference "$genome.fa" \
    --snp-directory slamdunk/snp \
    --max-read-length 151 \
    --min-basequality 26 \
    slamdunk/filter/*.bam
```

#### tcperutrpos

```shell
sbatch --cpus-per-task="$cpus" --mem="${cpus}G" alleyoop.sh tcperutrpos \
    --outputDir slamdunk/alleyoop/tcperutrpos \
    --reference "$genome.fa" \
    --bed "$genome-transcripts.bed" \
    --snp-directory slamdunk/snp \
    --max-read-length 151 \
    --min-basequality 26 \
    slamdunk/filter/*.bam
```

#### dump

```shell
sbatch --cpus-per-task="$cpus" --mem="${cpus}G" alleyoop.sh dump \
    --outputDir slamdunk/alleyoop/dump \
    --reference "$genome.fa" \
    --snp-directory slamdunk/snp \
    --min-basequality 26 \
    slamdunk/filter/*.bam
```

### MultiQC (check Alleyoop output)

Run MultiQC to get an HTML output from Alleyoop. This will make it easier to see if SlamDunk
succeeded.

```shell
sbatch multiqc.sh \
  --outdir multiqc \
  fastqc ${slamdunk_dir}/alleyoop
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
