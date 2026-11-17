#!/usr/bin/env python3

import argparse
import concurrent.futures
import csv
import os
import os.path
import statistics
import sys
from dataclasses import dataclass
from pathlib import Path

import pysam


@dataclass(frozen=True)
class ReadCounts:
  main: int
  spike: int | None


@dataclass(frozen=True)
class ScaleFactors:
  main: float
  spike: float | None


def readable_path(filepath: str):
  """
  Validate that file exists and is readable, or if it's "-" for stdin.

  :param filepath: path to file
  :return: path to file
  :raises argparse.ArgumentTypeError: if filepath doesn't exist
  """
  if filepath == "-":
    return None  # Special case for stdin/stdout path name

  path = Path(filepath)
  if not path.exists():
    # Raise ArgumentTypeError to make argparse show a clean error message
    raise argparse.ArgumentTypeError(f"ERROR: File not found: {filepath}")

  if not os.access(path, os.R_OK):
    raise argparse.ArgumentTypeError(f"ERROR: File not readable: {filepath}")

  # If all checks pass, return the path
  return path


def dir_path(dirpath: str):
  """
  Validate that directory exists.

  :param dirpath: path to directory
  :return: path to directory
  """
  if not dirpath or os.path.isdir(dirpath):
    return Path(dirpath)
  else:
    raise NotADirectoryError(dirpath)


BASE_SCALE = 1000000


def main(argv: list[str] | None = None):
  """
  Compute scale factors based on reads aligning to main genome and spike-in genome.

  :param argv: command line arguments
  """
  parser = argparse.ArgumentParser(
    formatter_class=argparse.RawDescriptionHelpFormatter,
    description=
    """Compute scale factors based on reads aligning to main genome and spike-in genome.
    
    It is assumed that BAM files present in the bam folder respect these requirements:
      * an index file is present for all BAM files
      * every spike read is mapped to a spike chromosome as primary alignment (ideally)
      * spike chromosomes are absent from the main genome
      * BAM files are already deduplicated if you want to count deduplicated reads
      
    It is recommended to use approximately 8 threads per allocated CPU on Alliance clusters such as Rorqual or Fir.""")
  parser.add_argument("--samplesheet", type=readable_path,
                      help="Sample sheet file where sample names will be used as labels")
  parser.add_argument("-o", "--output",
                      default="-",
                      help="Tab delimited file containing multiple scale factor options  (default: standard output)")
  parser.add_argument("-b", "--bam", type=dir_path, default="slamdunk/filter",
                      help="Folder where BAM files are located  (default: %(default)s)")
  parser.add_argument("-s", "--spike_fasta", type=readable_path,
                      help="FASTA file containing spike-in genome")
  parser.add_argument("-S", "--scale", type=int, default=BASE_SCALE,
                      help="Base scale to use to compute scale factors  (default: %(default)s)")
  parser.add_argument("-m", "--mean", action="store_true",
                      help="Divide scale factors by the mean of all scale factors  (default: false)")
  parser.add_argument("-t", "--threads", type=int, default=8,
                      help="Number of BAM files to read in parallel  (default: %(default)s)")
  args = parser.parse_args(argv)

  compute_scale_factors(
    samplesheet_file=args.samplesheet,
    output_file=Path(args.output) if args.output != "-" else None,
    bam_folder=args.bam,
    spike_fasta_file=args.spike_fasta,
    scale=args.scale,
    mean=args.mean, threads=args.threads)


def compute_scale_factors(samplesheet_file: Path | None,
    output_file: Path | None,
    bam_folder: Path, spike_fasta_file: Path | None, scale: int, mean: bool,
    threads: int = 8) -> None:
  """
  Compute scale factors based on reads aligning to main genome and spike-in genome.

  :param samplesheet_file: sample sheet file
  :param bam_folder: folder where BAM files are located
  :param output_file: output file that will contain multiple scale factor options
  :param spike_fasta_file: FASTA file containing spike-in genome
  :param scale: base scale to use to compute scale factors
  :param mean: divide scale factors by the mean of all scale factors
  :param threads: number of threads for reading BAM
  :return: None
  """
  bam_files = get_bam_files(samplesheet_file, bam_folder)

  read_counts = get_read_counts(bam_files=bam_files,
                                spike_fasta_file=spike_fasta_file,
                                threads=threads)

  scale_factors = get_scale_factors(read_counts=read_counts, scale=scale,
                                    mean=mean)

  write_output(output_file=output_file,
               read_counts=read_counts,
               scale_factors=scale_factors,
               scale=scale,
               mean=mean)


def get_bam_files(samplesheet_file: Path | None,
    bam_folder: Path) -> dict[str, Path]:
  """
  Finds BAM file associated with each sample.

  :param samplesheet_file: sample sheet file
  :param bam_folder: folder where BAM files are located
  :return: list of BAM file associated with each sample
  """
  bam_files = {}
  with samplesheet_file.open("r",
                             encoding="utf-8-sig") if samplesheet_file else sys.stdin as samplesheet_in:
    reader = csv.DictReader(samplesheet_in)
    for row in reader:
      row_samples = [row["sample"] + "_R1"]
      if "fastq_2" in row:
        row_samples.append(row["sample"] + "_R2")
      for sample in row_samples:
        sample_bam_files = list(bam_folder.glob(sample + "*.bam"))
        if len(sample_bam_files) == 0:
          raise FileNotFoundError(
            f"Error: no BAM file could be found in folder {bam_folder} for sample {sample}")
        elif len(sample_bam_files) != 1:
          print(
            f"Warning: multiple BAM files found for sample {sample}, using bam {sample_bam_files[0]} - all bam files: {sample_bam_files}",
            file=sys.stderr)
        bam_files[sample] = sample_bam_files[0]
  return bam_files


def get_read_counts(bam_files: dict[str, Path], spike_fasta_file: Path | None,
    threads: int = 8) -> dict[str, ReadCounts]:
  """
  Return the number of reads in bam_file.

  :param bam_files: BAM file for each sample
  :param spike_fasta_file: FASTA file containing spike-in genome
  :param threads: number of threads for reading BAM
  :return: number of reads for main genome and spike genome for each sample
  """
  futures = {}
  spike_chromosomes = None
  if spike_fasta_file:
    spike_chromosomes = parse_chromosomes(spike_fasta_file)
  with concurrent.futures.ThreadPoolExecutor(max_workers=threads) as executor:
    for sample, bam_file in bam_files.items():
      futures[executor.submit(get_read_counts_from_bam, bam_file,
                              spike_chromosomes)] = sample
    results = {}
    for future in concurrent.futures.as_completed(futures):
      sample = futures[future]
      results[sample] = future.result()
  return results


def get_read_counts_from_bam(bam_file: Path,
    spike_chromosomes: list[str] | None = None) -> ReadCounts:
  """
  Return the number of reads in bam_file for main genome and spike genome.

  :param bam_file: BAM file
  :param spike_chromosomes: only count reads associated with these chromosomes
  :return: the number of reads in bam_file for main genome and spike genome.
  """
  with pysam.AlignmentFile(str(bam_file), "rb") as align:
    if not align.check_index():
      raise RuntimeError(f"ERROR: BAM file {bam_file} is not indexed")
    total_read_count = align.count(read_callback=valid_read)
    spike_read_count = None
    if spike_chromosomes:
      spike_read_count = 0
      for chromosome in spike_chromosomes:
        try:
          spike_read_count += align.count(contig=chromosome,
                                          read_callback=valid_read)
        except ValueError:
          print(
            f"Warning: BAM file {bam_file} does not contain chromosome {chromosome} "
            f"from spike-in FASTA", file=sys.stderr)
      main_read_count = total_read_count - spike_read_count
    else:
      main_read_count = total_read_count
  assert main_read_count >= 0
  return ReadCounts(main_read_count, spike_read_count)


def valid_read(read) -> bool:
  """
  Return True if read is to be counted, False otherwise.

  Read is to be counted if it passes these requirements:
    * properly paired (for paired-end reads)
    * passed QC
    * is a primary alignment

  :param read: read from a BAM/SAM file
  :return: True if read is to be counted, False otherwise
  """
  return (((read.is_paired and read.is_proper_pair) or not read.is_paired)
          and not read.is_qcfail and not read.is_secondary and not read.is_supplementary)


def parse_chromosomes(fasta_file: Path | None) -> list[str]:
  """
  Parses chromosome names present in FASTA file.

  :param fasta_file: FASTA file
  :return: chromosome names present in FASTA file
  """
  chromosomes = []
  with fasta_file.open("r",
                       encoding="utf-8-sig") if fasta_file else sys.stdin as fasta_file_in:
    for line in fasta_file_in:
      if line.startswith(">"):
        chromosomes.append(line[1:].split()[0])
  return chromosomes


def get_scale_factors(read_counts: dict[str, ReadCounts],
    scale: int,
    mean: bool) -> dict[str, ScaleFactors]:
  """
  Compute scale factors for main and spike genomes for each sample.

  :param read_counts: number of reads for main genome and spike genome for each sample
  :param scale: base scale to use to compute scale factors
  :param mean: divide scale factors by the mean of all factors
  :return: scale factors for main and spike genomes
  """
  main_scale = {sample: scale / read_count.main for sample, read_count in
                read_counts.items()}
  spike_scale = {
    sample: scale / read_count.spike if read_count.spike else None for
    sample, read_count in read_counts.items()}
  valid_spike_scales = [
    value for value in spike_scale.values()
    if value is not None
  ]
  main_scale_mean = statistics.mean(
    list(main_scale.values()))
  spike_scale_mean = statistics.mean(
    valid_spike_scales) if valid_spike_scales else None
  if mean:
    main_scale = {sample: value / main_scale_mean for sample, value
                  in main_scale.items()}
    spike_scale = {
      sample: value / spike_scale_mean if value and spike_scale_mean else None
      for sample, value in spike_scale.items()}
  return {sample: ScaleFactors(main_scale[sample], spike_scale[sample]) for
          sample in read_counts}


def write_output(output_file: Path | None,
    read_counts: dict[str, ReadCounts],
    scale_factors: dict[str, ScaleFactors],
    scale: int,
    mean: bool) -> None:
  """
  Writes output to file.

  :param output_file: output file
  :param read_counts: read counts for main genome and spike genome for each sample
  :param scale_factors: scale factors /Users/poitrac/IdeaProjects/slamseq/scale-factors.py
  :param scale: base scale to use to compute scale factors
  :param mean: true if scale factors were divided by mean of all scale factors
  :return: None
  """
  with output_file.open("w",
                        encoding="utf-8") if output_file else sys.stdout as output_out:
    sample_column = "sample"
    main_count_column = "main genome reads count"
    main_scale_column = f"sequencing depth scale factors - {scale:.2e} / main genome reads count"
    spike_count_column = "spike-in reads count"
    spike_scale_column = f"spike-in scale factors - {scale:.2e} / spike-in reads count"
    spike_ratio_column = "spike-in reads ratio"
    if mean:
      main_scale_column += " / mean of main scale factors"
      spike_scale_column += " / mean of spike-in scale factors"
    fieldnames = [sample_column, main_count_column, main_scale_column]
    if next(iter(read_counts.values())).spike is not None:
      fieldnames += [spike_count_column, spike_scale_column, spike_ratio_column]
    writer = csv.DictWriter(output_out, fieldnames=fieldnames)
    writer.writeheader()
    for sample, read_count in read_counts.items():
      scale_factor = scale_factors[sample]
      row = {sample_column: sample, main_count_column: read_count.main,
             main_scale_column: scale_factor.main}
      if read_count.spike:
        row |= {spike_count_column: read_count.spike,
                spike_scale_column: scale_factor.spike,
                spike_ratio_column: read_count.spike / (
                    read_count.main + read_count.spike)}
      writer.writerow(row)


if __name__ == '__main__':
  main()
