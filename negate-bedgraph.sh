#!/bin/bash
#SBATCH --account=def-bmartin
#SBATCH --time=3:00:00
#SBATCH --cpus-per-task=8
#SBATCH --mem=8G
#SBATCH --output=negate-bedgraph-%A.out

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

###############################################################################
# Help text
###############################################################################

show_help() {
    cat << END_OF_HELP
Negate scores of BedGraph files.

Usage: $script_name [options] sample_1.bg sample_2.bg sample_3.bg

Options:
  -j, --jobs      INT        Number of jobslots for parallel (default: \$SLURM_CPUS_PER_TASK or 1)
  -d, --dry-run              Print commands but do not execute
  -h, --help                 Show this help

Example:
  sbatch --cpus-per-task=8 $script_name sample_1.bg sample_2.bg sample_3.bg
  $script_name all --jobs 8 sample_1.bg sample_2.bg sample_3.bg

END_OF_HELP
}

###############################################################################
# Default values
###############################################################################

jobs="${SLURM_CPUS_PER_TASK:-1}"
dry_run=false

###############################################################################
# Manual argument parsing (safe, collision-free)
###############################################################################

extra_arguments=()

while [[ $# -gt 0 ]]; do
    case "$1" in
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
# Validate arguments
###############################################################################

for bedgraph_file in "${extra_arguments[@]}"; do
    if ! [[ -f "$bedgraph_file" ]]; then
        echo "Error: BedGraph '$bedgraph_file' does not exists." >&2
        exit 1
    fi
done

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

Jobs:             $jobs
Dry-run:          $dry_run


END_OF_ARGUMENT_LOG

###############################################################################
# Execute command
###############################################################################

parallel_parameters=("--verbose")
if [[ "$dry_run" == true ]]; then
    parallel_parameters=("--dry-run")
fi
echo "Commands:"
parallel --jobs "$jobs" \
    "${parallel_parameters[@]}" \
    "awk -v OFS='\t' '{\$4=0-\$4; print}' {} > {.}.neg.bedgraph" \
    ::: "${extra_arguments[@]}"
echo
echo
if [[ "$dry_run" == true ]]; then
    echo "Dry-run mode enabled — commands not executed."
    exit 0
fi
