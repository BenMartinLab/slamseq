#!/bin/bash
#SBATCH --account=def-bmartin
#SBATCH --time=1-00:00:00
#SBATCH --cpus-per-task=64
#SBATCH --mem=120G
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
    echo
    echo "Usage: $script_name [options] -- [extra args passed to slamdunk all]"
    echo
    echo "Wrapper options:"
    echo "  -S, --samplesheet FILE     Samplesheet CSV for SlamDunk (default: samplesheet.slamdunk.csv)"
    echo "  -o, --outputDir  DIR       Output directory (default: slamdunk)"
    echo "  -t, --threads    INT       Threads (default: SLURM_CPUS_PER_TASK)"
    echo "  -d, --dry-run              Print commands but do not execute"
    echo "  -h, --help                 Show this help"
    echo
    echo "Everything after '--' or any unknown option is passed directly to slamdunk all."
    echo
    echo "Do not specify FASTQ files; they are inferred from the samplesheet."
    echo
    echo "Example:"
    echo "  sbatch --cpus-per-task=8 $script_name --samplesheet samples.csv --reference hg38.fa --bed hg38-transcripts.bed"
    echo "  $script_name --samplesheet samples.csv --reference hg38.fa --bed hg38-transcripts.bed"
    echo
}

###############################################################################
# Default values
###############################################################################

samplesheet="samplesheet.slamdunk.csv"
output_dir="slamdunk"
threads="${SLURM_CPUS_PER_TASK:-1}"
dry_run=false

slamdunk_container="${script_dir}/slamdunk.sif"
workdir=${SLURM_TMPDIR:-${PWD}}

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
        -o|--outputDir)
            output_dir="$2"
            shift 2
            ;;
        --outputDir=*)
            output_dir="${1#--outputDir=}"
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
# Validate inputs
###############################################################################

if [[ ! -f "$samplesheet" ]]; then
    echo "Error: Samplesheet '$samplesheet' does not exist." >&2
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
# Logging + SLURM metadata + environment dump
###############################################################################

echo "------------------------------------------------------------"
echo "$script_name started at: $(date)"
echo "Host: $(hostname)"
echo "User: $USER"
echo "Script: $script_name"
echo
echo "SLURM metadata:"
echo "  Job ID:        ${SLURM_JOB_ID:-N/A}"
echo "  Array Task ID: ${SLURM_ARRAY_TASK_ID:-N/A}"
echo "  CPUs:          ${SLURM_CPUS_PER_TASK:-N/A}"
echo "  Node:          ${SLURM_NODELIST:-N/A}"
echo
echo "Environment dump:"
env | sort
echo "------------------------------------------------------------"
echo
echo "Samplesheet:  $samplesheet"
echo "Output dir:   $output_dir"
echo "Threads:      $threads"
echo "Dry-run:      $dry_run"
echo
echo

###############################################################################
# Build slamdunk all command
###############################################################################

cmd=(
    apptainer exec
    --containall
    --workdir "$workdir"
    --pwd /data
    --bind "$PWD:/data" \
    "$slamdunk_container"
    slamdunk all
    "${extra_parameters[@]}"
    --outputDir "$output_dir"
    --threads "$threads"
    "$samplesheet"
)

echo "Command:"
printf "  %q " "${cmd[@]}"
echo
echo

###############################################################################
# Execute slamdunk all
###############################################################################

if [[ "$dry_run" == true ]]; then
    echo "Dry-run mode enabled — command not executed."
    exit 0
fi
"${cmd[@]}"
mv "${output_dir}/count" "${output_dir}/count_onetcreadcount"
