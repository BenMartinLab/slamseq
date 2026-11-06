#!/usr/bin/env python3

import argparse
import csv
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def validate_required_columns(header: list[str]):
  """
  Validate that required columns are present in the samplesheet file.

  :param header: Column headers from samplesheet file.
  """
  required = {"sample", "fastq_1"}
  missing = required - set(header)
  if missing:
    sys.exit(f"ERROR: Missing required columns: {', '.join(missing)}")


def validate_fastq(fastq_path: Path):
  """
  Validate that FASTQ file exists.

  :param fastq_path: FASTQ file path
  """
  if not fastq_path.exists():
    sys.exit(f"ERROR: FASTQ file '{fastq_path}' does not exist.")


def read_samplesheet(samplesheet_path: Path) -> tuple[
  list[str], list[dict[str, str]]]:
  """
  Reads samplesheet file, validates required columns and that FASTQ files exist.

  :param samplesheet_path: samplesheet file path
  :return: headers, rows
  """
  with samplesheet_path.open(encoding="utf-8-sig") as f:
    reader = csv.reader(f)
    header = next(reader)

    validate_required_columns(header)

    rows = []
    for row in reader:
      row_dict = dict(zip(header, row))
      row_dict = {k: v.strip() for k, v in row_dict.items()}
      validate_fastq(Path(row_dict["fastq_1"]))
      if "fastq_2" in header:
        validate_fastq(Path(row_dict["fastq_2"]))
      rows.append(row_dict)

  return header, rows


def write_slamdunk(samplesheet_rows: list[dict[str, str]],
    slamdunk_path: Path,
    fastq_path: Path):
  """
  Writes samplesheet file for use with SlamDunk.

  :param samplesheet_rows: Rows from samplesheet CSV file.
  :param slamdunk_path: Where to write barcode whitelist file.
  :param fastq_path: Change parent directory of FASTQ files to this path.
  """
  with open(slamdunk_path, "w") as f:
    writer = csv.writer(f)
    index = 0
    for row in samplesheet_rows:
      index += 1
      fastq1 = fastq_path.joinpath(Path(row.get("fastq_1", "")).name)
      writer.writerow(
        [fastq1, row.get("sample", "") + "_R1",
         str(index), str(index)])
      if "fastq_2" in row:
        fastq2 = fastq_path.joinpath(Path(row.get("fastq_2", "")).name)
        writer.writerow(
          [fastq2, row.get("sample", "") + "_R2",
           str(index), str(index)])


def main(argv: list[str] | None = None):
  """
  Converts samplesheet to the following format:
    - SlamDunk samplesheet

  :param argv: command line arguments
  """

  parser = argparse.ArgumentParser(
    description="Convert SLAM-seq samplesheet into SlamDunk samplesheet.")
  parser.add_argument(
    "samplesheet",
    nargs="?",
    help="Input samplesheet CSV file."
  )
  parser.add_argument(
    "-i", "--input",
    help="Input samplesheet CSV file (alternative to positional argument)."
  )
  parser.add_argument(
    "-s", "--slamdunk",
    help="Output SlamDunk samplesheet file.  (default: basename of samplesheet + '.slamdunk.csv')"
  )
  parser.add_argument(
    "-f", "--fastq",
    help="Directory containing FASTQ files to be processed by SlamDunk.  (default: %(default)s)",
    default="bbduk"
  )

  args = parser.parse_args(argv)

  # Determine input file
  samplesheet = args.samplesheet or args.input
  if not samplesheet:
    sys.exit("ERROR: You must specify a samplesheet (positional or --input).")
  samplesheet_path = Path(samplesheet)
  if not samplesheet_path.exists():
    sys.exit(f"ERROR: Samplesheet '{samplesheet}' does not exist.")

  # Default output paths
  slamdunk = args.slamdunk or samplesheet_path.with_suffix(".slamdunk.csv")
  fastq_path = Path(args.fastq)

  samplesheet_headers, samplesheet_rows = read_samplesheet(samplesheet_path)
  write_slamdunk(samplesheet_rows, slamdunk, fastq_path)

  print("Conversion complete.")
  print(f"SlamDunk samplesheet:  {slamdunk}")


if __name__ == "__main__":
  main()
