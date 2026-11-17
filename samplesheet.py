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
        if not row[column].strip():
          errors.append(f"Row {reader.line_num}: {column} is empty")
      for fastq_column in [FASTQ_1_COLUMN, FASTQ_2_COLUMN]:
        if fastq_column in row and row[fastq_column] and not os.path.exists(
            row[fastq_column]):
          errors.append(
            f"Row {reader.line_num}: {fastq_column} not found: {row[fastq_column]}")
  if errors:
    print(f"Found {len(errors)} validation error(s):", file=sys.stderr)
    for error in errors:
      print(f"  - {error}", file=sys.stderr)
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
        f"ERROR: Columns {missing_columns} not found in samplesheet {samplesheet}")
    for row in reader:
      values = []
      for column in required_columns:
        if not row[column].strip():
          raise argparse.ArgumentTypeError(
            f"ERROR: Empty value found in required column '{column}' at row {reader.line_num} of samplesheet {samplesheet}"
          )
        values.append(row[column])
      values.extend([row[column] if column in row else ""
                     for column in optional_columns])
      yield values


def main(argv: list[str] | None = None):
  """
  Samplesheet utilities.

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
    f"""Validate samplesheet headers and content.
    
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

  args = parser.parse_args(argv)
  args.func(args)


if __name__ == "__main__":
  main()
