#!/bin/bash
#SBATCH --account=def-bmartin
#SBATCH --time=3:00:00
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --output=slamdunk-%A.out

set -euo pipefail

###############################################################################
# Load modules on Alliance clusters
###############################################################################

if [[ -n "${CC_CLUSTER:-}" ]]; then
    module purge
    module load StdEnv/2023
    module load apptainer/1
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
Usage: $script_name [options] -- [extra args passed to slamdunk]

SlamDunk mode:
  mode             MODE      SlamDunk mode (ex: all, count) (required)

Wrapper options:
  -t, --threads    INT       Threads (default: SLURM_CPUS_PER_TASK)
  -d, --dry-run              Print commands but do not execute
  -h, --help                 Show this help

Everything after '--' or any unknown option is passed directly to slamdunk.

Example:
  sbatch --cpus-per-task=8 $script_name all --reference hg38.fa --bed hg38-transcripts.bed samplesheet.slamdunk.csv
  $script_name all --threads 8 --reference hg38.fa --bed hg38-transcripts.bed samplesheet.slamdunk.csv

END_OF_HELP
}

###############################################################################
# Default values
###############################################################################

threads="${SLURM_CPUS_PER_TASK:-1}"
dry_run=false

slamdunk_container="${script_dir}/slamdunk.sif"
workdir=${SLURM_TMPDIR:-${PWD}}

###############################################################################
# Manual argument parsing (safe, collision-free)
###############################################################################

mode="${1:-}"
shift

extra_parameters=()

while [[ $# -gt 0 ]]; do
    case "$1" in
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

if [[ -z "$mode" ]] || [[ "$mode" == -* ]]; then
    echo "Error: Mode '$mode' is invalid." >&2
    exit 1
fi

###############################################################################
# Copy slamdunk container to SLURM_TMPDIR for speed
###############################################################################

if [[ -n "${SLURM_TMPDIR:-}" ]]; then
    cp "$slamdunk_container" "$SLURM_TMPDIR"
    slamdunk_container="${SLURM_TMPDIR}/$(basename "$slamdunk_container")"
fi

###############################################################################
# Number of jobs for 'all' and 'map' modes
###############################################################################

jobs=1
threads_per_job=$threads
if [[ "$mode" == all ]] || [[ "$mode" == map ]]; then
    threads_per_job=2
    jobs=$(((threads + threads_per_job - 1) / threads_per_job))
    samplesheet="${extra_parameters[-1]}"
    if ! [[ -f "$samplesheet" ]] || [[ "$samplesheet" == *.gz ]]; then
        echo "Error: Samplesheet '$samplesheet' does not exist or is not a samplesheet." >&2
        exit 1
    fi
    n_samples=$(grep -c '[^[:space:]]' "$samplesheet")
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

Mode:             $mode
Threads:          $threads
Jobs:             $jobs
Threads per job:  $threads_per_job
Dry-run:          $dry_run


END_OF_PARAMETER_LOG

###############################################################################
# Build command
###############################################################################

cmd=(
    apptainer exec
    --containall
    --workdir "$workdir"
    --pwd /data
    --bind "$PWD:/data" \
    "$slamdunk_container"
    slamdunk "$mode"
    --threads "$threads_per_job"
)

###############################################################################
# Execute command
###############################################################################

if [[ "$mode" == "all" ]] || [[ "$mode" == "map" ]]; then
    parallel_parameters=("--verbose")
    if [[ "$dry_run" == true ]]; then
        parallel_parameters=("--dry-run")
    fi
    echo "Commands:"
    parallel --jobs "$jobs" \
        "${parallel_parameters[@]}" \
        "${cmd[@]}" --sample-index {} "${extra_parameters[@]}" \
        ::: $(seq 1 "$n_samples")
    echo
    echo
    if [[ "$dry_run" == true ]]; then
        echo "Dry-run mode enabled — commands not executed."
        exit 0
    fi
else
    cmd+=("${extra_parameters[@]}")
    echo "Command:"
    printf "  %q " "${cmd[@]}"
    echo
    echo
    if [[ "$dry_run" == true ]]; then
        echo "Dry-run mode enabled — command not executed."
        exit 0
    fi
    "${cmd[@]}"
fi
