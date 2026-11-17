#!/bin/bash
#SBATCH --account=def-bmartin
#SBATCH --time=3:00:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --output=scale-factors-%A.out

set -euo pipefail

###############################################################################
# Load modules on Alliance clusters
###############################################################################

if [[ -n "${CC_CLUSTER:-}" ]]; then
    module purge
    module load StdEnv/2023
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
script_dir=$(dirname "$script_path")

###############################################################################
# Help text
###############################################################################

show_help() {
    cat << END_OF_HELP
Wrapper to run 'scale-factors.py'.

Usage: $script_name [options] -- [extra args passed to scale-factors.py]

Wrapper options:
  -t, --threads    INT       Threads (default: \$SLURM_CPUS_PER_TASK * 8)
  -d, --dry-run              Print commands but do not execute
  -h, --help                 Show this help

Everything after '--' or any unknown option is passed directly to scale-factors.py.

Example:
  sbatch --cpus-per-task=8 $script_name samplesheet.csv
  $script_name --threads 8 ./*.fastq.gz

END_OF_HELP
}

###############################################################################
# Default values
###############################################################################

slurm_cpus="${SLURM_CPUS_PER_TASK:-1}"
threads=$((slurm_cpus * 8))
dry_run=false

###############################################################################
# Manual argument parsing (safe, collision-free)
###############################################################################

extra_arguments=()

while [[ $# -gt 0 ]]; do
    case "$1" in
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
            extra_arguments+=("$@")
            break
            ;;
        *)
            # Unknown argument → passthrough
            extra_arguments+=("$1")
            shift
            ;;
    esac
done

###############################################################################
# Load python environment
###############################################################################

source "${script_dir}/slamseq-env/bin/activate"

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
cat << END_OF_ARGUMENT_LOG
------------------------------------------------------------

Threads:     $threads
Dry-run:     $dry_run


END_OF_ARGUMENT_LOG

###############################################################################
# Build command
###############################################################################

cmd=(
    python "${script_dir}/scale-factors.py" --threads "$threads" "${extra_arguments[@]}"
)

###############################################################################
# Execute command
###############################################################################

echo "Command:"
printf "  %q " "${cmd[@]}"
echo
echo

if [[ "$dry_run" == true ]]; then
    echo "Dry-run mode enabled — command not executed."
    exit 0
fi

"${cmd[@]}"
