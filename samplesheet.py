#!/usr/bin/env python3

import argparse
import csv
import os
import sys
from pathlib import Path
from typing import Iterator

SAMPLE_COLUMN = "sample"
FASTQ_1_COLUMN = "fastq_1"
FASTQ_2_COLUMN = "fastq_2"
REQUIRED_COLUMNS = [SAMPLE_COLUMN, FASTQ_1_COLUMN]


def samplesheet_arg(filepath: str):
  """
  Checks if samplesheet file exists and is readable, or if it's "-" for stdin.

  :param filepath: path to samplesheet
  :return: path to samplesheet
  :raises argparse.ArgumentTypeError: if samplesheet doesn't exist or cannot be read
  """
  if filepath == "-":
    return None  # Special case for stdin/stdout path name

  path = Path(filepath)
  if not path.exists():
    raise argparse.ArgumentTypeError(
      f"ERROR: Samplesheet not found: {filepath}")
  if not os.access(path, os.R_OK):
    raise argparse.ArgumentTypeError(
      f"ERROR: Samplesheet not readable: {filepath}")
  return path


def writable_file(filepath: str):
  """
  Validate that file is writable, or if it's "-" for stdout.

  :param filepath: path to file
  :return: path to file
  :raises argparse.ArgumentTypeError: if filepath is not writable
  """
  if filepath == "-":
    return None  # Special case for stdin/stdout path name

  path = Path(filepath)
  if not path.parent.is_dir():
    raise argparse.ArgumentTypeError(
      f"ERROR: Parent directory of file not found: {filepath}")
  if not os.access(path.parent, os.W_OK):
    raise argparse.ArgumentTypeError(
      f"ERROR: Parent directory of file not writable: {filepath}")
  return path


def validate(args: argparse.Namespace):
  """
  Validate samplesheet headers and content.

  Validation will check for:
    * Required columns based on headers - required columns are {REQUIRED_COLUMNS}
    * Required columns never have empty values
    * FASTQ files existence

  :param args: command line arguments
  :return: None
  """
  validate_samplesheet(args.samplesheet)


def validate_samplesheet(samplesheet: Path) -> None:
  """
  Validate samplesheet headers and content.

  :param samplesheet: path to samplesheet file
  :return: None
  """
  errors = []
  warnings = []
  with samplesheet.open("r",
                        encoding="utf-8-sig") if samplesheet else sys.stdin as samplesheet_in:
    reader = csv.DictReader(samplesheet_in)
    missing_columns = [
      column for column in REQUIRED_COLUMNS if
      column not in (reader.fieldnames if reader.fieldnames else [])]
    if missing_columns:
      errors.append(f"Missing columns: {missing_columns}")
    for row in reader:
      for column in REQUIRED_COLUMNS:
        if column in row and not row[column].strip():
          errors.append(f"Row {reader.line_num}: '{column}' is empty")
      for fastq_column in [FASTQ_1_COLUMN, FASTQ_2_COLUMN]:
        if fastq_column in row and row[fastq_column] and not os.path.exists(
            row[fastq_column]):
          warnings.append(
            f"Row {reader.line_num}: '{fastq_column}' not found: '{row[fastq_column]}'")
  if errors:
    print(f"Found {len(errors)} error(s):", file=sys.stderr)
    for error in errors:
      print(f"  - {error}", file=sys.stderr)
  if warnings:
    print(f"Found {len(warnings)} warning(s):", file=sys.stderr)
    for warning in warnings:
      print(f"  - {warning}", file=sys.stderr)
  if errors:
    sys.exit(1)


def rows(args: argparse.Namespace) -> None:
  """
  Print selected columns from samplesheet file to stdout separated by tabs.

  The output will contain the columns in this order:
    * Required columns in the order provided by the arguments
    * Optional columns in the order provided by the arguments.

  For example, the following command
  'samplesheet.py samplesheet.csv -c sample fastq_1 -o fastq_2 -c control'
  will output the columns in this order:
  [sample, fastq_1, control, fastq_2]

  :param args: command line arguments
  :return: None
  """
  for values in parse_rows(args.samplesheet, args.columns, args.optional):
    print("\t".join(values))


def parse_rows(samplesheet: Path, required_columns: list[str] | None = None,
    optional_columns: list[str] | None = None) -> Iterator[list[str]]:
  """
  Returns selected columns from samplesheet file.

  :param samplesheet: path to samplesheet file
  :param required_columns: required columns to read
  :param optional_columns: optional columns to read
  :return: values of columns
  """
  if not required_columns:
    required_columns = []
  if not optional_columns:
    optional_columns = []
  with samplesheet.open("r",
                        encoding="utf-8-sig") if samplesheet else sys.stdin as samplesheet_in:
    reader = csv.DictReader(samplesheet_in)
    missing_columns = [
      column for column in required_columns if
      column not in (reader.fieldnames if reader.fieldnames else [])]
    if missing_columns:
      raise argparse.ArgumentTypeError(
        f"ERROR: Columns {missing_columns} not found in samplesheet")
    for row in reader:
      values = []
      for column in required_columns:
        if not row[column].strip():
          raise argparse.ArgumentTypeError(
            f"ERROR: Empty value found in required column '{column}' at row {reader.line_num} of samplesheet"
          )
        values.append(row[column])
      values.extend([row[column] if column in row else ""
                     for column in optional_columns])
      yield values


def convert(args: argparse.Namespace) -> None:
  """
  Convert SLAM-seq samplesheet into SlamDunk samplesheet.

  :param args: command line arguments
  :return: None
  """
  slamdunk = Path(
    args.slamdunk) if args.slamdunk else args.samplesheet.with_suffix(
    ".slamdunk.csv")
  write_slamdunk(args.samplesheet, slamdunk, args.fastq)


def write_slamdunk(samplesheet: Path,
    slamdunk: Path,
    fastq_dir: Path):
  """
  Writes samplesheet file for use with SlamDunk.

  :param samplesheet: samplesheet file
  :param slamdunk: where to write samplesheet in SlamDunk format
  :param fastq_dir: change parent directory of FASTQ files to this path
  """
  if fastq_dir and not fastq_dir.exists():
    print(f"WARNING: FASTQ directory '{fastq_dir}' does not exists yet.\n",
          file=sys.stderr)
  print(f"Creating sampleheet '{slamdunk}' for SlamDunk.", file=sys.stderr)
  with samplesheet.open("r",
                        encoding="utf-8-sig") if samplesheet else sys.stdin as samplesheet_in, slamdunk.open(
    "w") as slamdunk_out:
    reader = csv.DictReader(samplesheet_in)
    writer = csv.writer(slamdunk_out)
    index = 0
    for row in reader:
      index += 1
      fastq1 = Path(row[FASTQ_1_COLUMN])
      fastq2 = Path(row[FASTQ_2_COLUMN]) if FASTQ_2_COLUMN in row and row[
        FASTQ_2_COLUMN].strip() else None
      if fastq_dir:
        fastq1 = fastq_dir.joinpath(fastq1.name)
        fastq2 = fastq_dir.joinpath(fastq2.name) if fastq2 else None
      writer.writerow(
        [fastq1, row[SAMPLE_COLUMN] + "_R1",
         str(index), str(index)])
      if fastq2:
        writer.writerow(
          [fastq2, row[SAMPLE_COLUMN] + "_R2",
           str(index), str(index)])


def main(argv: list[str] | None = None):
  """
  Samplesheet utilities for SLAM-seq.

  :param argv: command line arguments
  :return: None
  """
  parser = argparse.ArgumentParser(
    description="Samplesheet utilities."
  )
  subparsers = parser.add_subparsers(
    dest="command",
    required=True
  )

  validate_parser = subparsers.add_parser(
    "validate",
    help="Validate samplesheet",
    formatter_class=argparse.RawDescriptionHelpFormatter,
    description=
    f"""Validate SLAM-seq samplesheet headers and content.
    
    Validation will check for:
      * Required columns based on headers - required columns are {REQUIRED_COLUMNS}
      * Required columns never have empty values
      * FASTQ files existence {[FASTQ_1_COLUMN, FASTQ_2_COLUMN]}
    """
  )
  validate_parser.add_argument(
    "samplesheet",
    type=samplesheet_arg,
    help="Input samplesheet CSV file ('-' for stdin)."
  )
  validate_parser.set_defaults(func=validate)

  rows_parser = subparsers.add_parser(
    "rows",
    help="Print selected columns from samplesheet file to stdout separated by tabs.",
    formatter_class=argparse.RawDescriptionHelpFormatter,
    description=
    """Print selected columns from samplesheet file to stdout separated by tabs.
    
    One line will be printed for each row in the samplesheet.
    
    The output will contain the columns in this order:
      * Required columns in the order provided by the arguments
      * Optional columns in the order provided by the arguments.
    
    For example, the following command
    'samplesheet.py samplesheet.csv -c sample fastq_1 -o fastq_2 -c control'
    will output the columns in this order:
    [sample, fastq_1, control, fastq_2]
    """
  )
  rows_parser.add_argument(
    "samplesheet",
    type=samplesheet_arg,
    help="Input samplesheet CSV file ('-' for stdin)."
  )
  rows_parser.add_argument(
    "-c", "--columns",
    nargs="+",
    help="Header of required columns to read. Will fail if a column is missing"
  )
  rows_parser.add_argument(
    "-o", "--optional",
    nargs="+",
    help="Header of optional columns to read. Missing columns will be present in the output but will contain empty strings"
  )
  rows_parser.set_defaults(func=rows)

  convert_parser = subparsers.add_parser(
    "convert",
    help="Convert SLAM-seq samplesheet into SlamDunk samplesheet.",
    description="Convert SLAM-seq samplesheet into SlamDunk samplesheet."
  )
  convert_parser.add_argument(
    "samplesheet",
    type=samplesheet_arg,
    help="Input samplesheet CSV file ('-' for stdin)."
  )
  convert_parser.add_argument(
    "-s", "--slamdunk",
    type=writable_file,
    help="Output SlamDunk samplesheet file.  (default: (samplesheet without extension) + '.slamdunk.csv')"
  )
  convert_parser.add_argument(
    "-f", "--fastq",
    help="Directory containing FASTQ files to be processed by SlamDunk.  (default: %(default)s)",
    type=Path,
    default="bbduk"
  )
  convert_parser.set_defaults(func=convert)

  args = parser.parse_args(argv)
  args.func(args)


if __name__ == "__main__":
  main()
