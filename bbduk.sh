#!/bin/bash
#SBATCH --account=def-bmartin
#SBATCH --time=03:00:00
#SBATCH --cpus-per-task=16
#SBATCH --mem=140G
#SBATCH --output=bbduk-%A.out

set -euo pipefail

###############################################################################
# Load modules on Alliance clusters
###############################################################################

if [[ -n "${CC_CLUSTER:-}" ]]; then
    module purge
    module load StdEnv/2023
    module load bbmap/39.06
    echo
fi

###############################################################################
# Script name detection (SLURM-friendly)
###############################################################################

script_path="${BASH_SOURCE[0]}"
if [[ "$(basename "$script_path")" == "slurm_script" && -n "${SLURM_JOB_ID:-}" ]]; then
    script_path="$(scontrol show job "$SLURM_JOB_ID" \
        | awk -F= '/Command=/ {print $2; exit}')"
fi
script_name="$(basename "$script_path")"
script_dir="$(dirname "$script_path")"

###############################################################################
# Help text
###############################################################################

show_help() {
    cat << END_OF_HELP
Usage: $script_name [options] -- [extra args passed to bbduk]

Wrapper options:
  -S, --samplesheet FILE     Samplesheet CSV (default: samplesheet.csv)
  -o, --output-dir DIR       Output directory (default: bbduk)
  -t, --threads    INT       Threads (default: SLURM_CPUS_PER_TASK)
  -j, --jobs       INT       Number of jobslots for parallel (default: 8)
  -d, --dry-run              Print commands but do not execute
  -h, --help                 Show this help

Everything after '--' or any unknown option is passed directly to bbduk.

Do not specify FASTQ files; they are inferred from the samplesheet.

Example:
  sbatch --cpus-per-task=8 $script_name --samplesheet samples.csv ref=adapters.fa
  $script_name --samplesheet samples.csv ref=adapters.fa

END_OF_HELP
}

###############################################################################
# Default values
###############################################################################

samplesheet="samplesheet.csv"
output_dir="bbduk"
threads="${SLURM_CPUS_PER_TASK:-1}"
jobs=8
dry_run=false

###############################################################################
# Manual argument parsing (safe, collision-free)
###############################################################################

extra_parameters=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -S|--samplesheet)
            samplesheet="$2"
            shift 2
            ;;
        --samplesheet=*)
            samplesheet="${1#--samplesheet=}"
            shift 2
            ;;
        -o|--output-dir)
            output_dir="$2"
            shift 2
            ;;
        --output-dir=*)
            output_dir="${1#--output-dir=}"
            shift
            ;;
        -t|--threads)
            threads="$2"
            shift 2
            ;;
        --threads=*)
            threads="${1#--threads=}"
            shift
            ;;
        -j|--jobs)
            jobs="$2"
            shift 2
            ;;
        --jobs=*)
            jobs="${1#--jobs=}"
            shift
            ;;
        -d|--dry-run)
            dry_run=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        --)
            shift
            extra_parameters+=("$@")
            break
            ;;
        *)
            # Unknown argument → passthrough
            extra_parameters+=("$1")
            shift
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

###############################################################################
# Get FASTQ file list
###############################################################################

source "${script_dir}/functions.sh"
fastq=()
collect_fastq "$samplesheet" fastq

###############################################################################
# Number of threads per job
###############################################################################

threads_per_job=$(((threads + jobs - 1) / jobs))
if [[ "${#fastq[@]}" -lt "$jobs" ]]; then
    threads_per_job=$threads
fi

###############################################################################
# Logging + SLURM metadata + environment dump
###############################################################################

cat << END_OF_SLURM_LOG
------------------------------------------------------------
$script_name started at: $(date)
Host: $(hostname)
User: $USER
Script: $script_name

SLURM metadata:
  Job ID:        ${SLURM_JOB_ID:-N/A}
  Array Task ID: ${SLURM_ARRAY_TASK_ID:-N/A}
  CPUs:          ${SLURM_CPUS_PER_TASK:-N/A}
  Node:          ${SLURM_NODELIST:-N/A}
END_OF_SLURM_LOG
if [[ ${debug:-} == true ]]; then
    echo "Environment dump:"
    env | sort
fi
cat << END_OF_PARAMETER_LOG
------------------------------------------------------------

Samplesheet:     $samplesheet
Output dir:      $output_dir
Threads:         $threads
Threads per job: $threads_per_job
Jobs:            $jobs
Dry-run:         $dry_run


END_OF_PARAMETER_LOG

###############################################################################
# Build bbduk command
###############################################################################

cmd=(
    bbduk.sh
    usejni=t
    threads="$threads_per_job"
    "${extra_parameters[@]}"
)

###############################################################################
# Execute bbduk
###############################################################################

parallel_parameters=("--verbose")
if [[ "$dry_run" == true ]]; then
    parallel_parameters=("--dry-run")
else
    mkdir -p "${output_dir}"
fi
echo "Commands:"
parallel --jobs "$jobs" \
    "${parallel_parameters[@]}" \
    "${cmd[@]}" in="{}" out="${output_dir}/{/}" \
    ::: "${fastq[@]}"
echo
echo

if [[ "$dry_run" == true ]]; then
    echo "Dry-run mode enabled — commands not executed."
    exit 0
fi
