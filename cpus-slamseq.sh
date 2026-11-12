#!/bin/bash

set -euo pipefail

###############################################################################
# Script name detection
###############################################################################

script_path="${BASH_SOURCE[0]}"
script_name="$(basename "$script_path")"
script_dir="$(dirname "$script_path")"

###############################################################################
# Help text
###############################################################################

show_help() {
    cat << END_OF_HELP
Shows the number of cpus to use for SLURM base on the number of FASTQ files to process.

Usage: $script_name [options]

Wrapper options:
  -s, --samplesheet FILE     Samplesheet CSV (default: samplesheet.csv)
  -m, --max         INT      Maximum number of cpus for SLURM (default: 48)
  -h, --help                 Show this help

Example:
  $script_name --samplesheet samples.csv --max 48

END_OF_HELP
}

###############################################################################
# Default values
###############################################################################

samplesheet="samplesheet.csv"
max_cpus=48

###############################################################################
# Manual argument parsing (safe, collision-free)
###############################################################################

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--samplesheet)
            samplesheet="$2"
            shift 2
            ;;
        --samplesheet=*)
            samplesheet="${1#--samplesheet=}"
            shift 2
            ;;
        -m|--max)
            max_cpus="$2"
            shift 2
            ;;
        --max=*)
            max_cpus="${1#--max=}"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Error: Unknown option '$1'." >&2
            exit 1
            ;;
    esac
done

###############################################################################
# Validate arguments
###############################################################################

if [[ ! -f "$samplesheet" ]]; then
    echo "Error: Samplesheet '$samplesheet' does not exist." >&2
    exit 1
fi
if ! [[ "$max_cpus" =~ ^[0-9]+$ ]]
then
    echo "Error: Max CPUs '$max_cpus' is not an integer." >&2
    usage
    exit 1
fi

###############################################################################
# Find the number of CPUs to use for SlamDunk
###############################################################################

source "${script_dir}/functions.sh"
fastq=()
collect_fastq "$samplesheet" fastq

cpus="${#fastq[@]}"
(( cpus > $max_cpus )) && cpus=$max_cpus
echo "$cpus"
