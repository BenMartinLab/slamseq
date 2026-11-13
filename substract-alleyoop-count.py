#!/usr/bin/env python3

import argparse
import os
import sys


def readable_file(filepath: str):
  """
  Checks if a file exists and is readable, or if it's "-" for stdin.

  :param filepath: path to file
  :return: path to file
  :raises argparse.ArgumentTypeError: if filepath doesn't exist
  """
  if filepath == "-":
    return filepath  # Special case for stdin/stdout path name

  if not os.path.exists(filepath):
    # Raise ArgumentTypeError to make argparse show a clean error message
    raise argparse.ArgumentTypeError(f"ERROR: File not found: {filepath}")

  if not os.access(filepath, os.R_OK):
    raise argparse.ArgumentTypeError(f"ERROR: File not readable: {filepath}")

  # If all checks pass, return the original string (the filepath)
  return filepath


def main(argv: list[str] | None = None):
  parser = argparse.ArgumentParser(
    description="Substracts Alleyoop merge's one T->C read counts from total read counts.")
  parser.add_argument("-t", "--total", type=readable_file,
                      required=True,
                      help="Alleyoop merge's total read counts in TSV format")
  parser.add_argument("-1", "--one", type=readable_file, required=True,
                      help="Alleyoop merge's one T->C read counts in TSV format")
  parser.add_argument("-o", "--output",
                      default=sys.stdout,
                      help="Output TSV file")

  args = parser.parse_args(argv)
  substract_onetc(total_reads_file=args.total, onetc_reads_file=args.one,
                  output_file=args.output)


def substract_onetc(total_reads_file: str, onetc_reads_file: str,
    output_file: str):
  """
  Substracts Alleyoop merge's one T->C read counts from total read counts.

  :param total_reads_file: Alleyoop merge's total read counts in TSV format
  :param onetc_reads_file: Alleyoop merge's one T->C read counts in TSV format
  :param output_file: Output TSV file
  """
  with (open(total_reads_file, "r") as total_reads_reader,
        open(onetc_reads_file, "r") as onetc_reads_reader,
        open(output_file, "w") as output_writer):
    # Copy metadata headers.
    for index in range(0, 3):
      output_writer.write(total_reads_reader.readline())
      onetc_reads_reader.readline()

    # Copy main headers.
    headers = total_reads_reader.readline().rstrip("\r\n").split("\t")
    onetc_headers = onetc_reads_reader.readline().rstrip("\r\n").split("\t")
    if len(headers) != len(onetc_headers):
      sys.exit(
        f"ERROR: Number of headers {len(headers)} does not match number of headers {len(onetc_headers)}")
    output_writer.write("\t".join(headers))
    output_writer.write("\n")

    for line in total_reads_file:
      columns = line.rstrip("\r\n").split("\t")
      onetc_columns = onetc_reads_reader.readline().rstrip("\r\n").split("\t")
      if columns[3] != onetc_columns[3]:
        sys.exit(
          f"ERROR: Gene {columns[3]} in total count does not match gene {onetc_columns[3]} in one T->C count file.")
      # Copy regular columns.
      output_writer.write("\t".join(columns[:10]))
      for index in range(10, len(columns)):
        count = int(columns[index])
        onetc_count = int(onetc_columns[index])
        output_writer.write(f"\t{count - onetc_count}")
      output_writer.write("\n")


if __name__ == '__main__':
  main()
