#!/bin/bash
#SBATCH --account=def-bmartin
#SBATCH --time=03:00:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --output=multiqc-%A.out

set -euo pipefail

###############################################################################
# Load modules on Alliance clusters
###############################################################################

if [[ -n "${CC_CLUSTER:-}" ]]; then
    module purge
    module load StdEnv/2023
    module load python/3.12.4

    tmpdir="${SLURM_TMPDIR:-/tmp}"
    env="${tmpdir}/env"
    virtualenv --no-download "$env"
    source "${env}/bin/activate"
    pip install --no-index --upgrade pip
    pip install --no-index multiqc==1.25.2
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
Usage: $script_name [options] -- [extra args passed to multiqc]

Wrapper options:
  -d, --dry-run              Print commands but do not execute
  -h, --help                 Show this help

Everything after '--' or any unknown option is passed directly to multiqc.

Example:
  sbatch $script_name --outdir multiqc .
  $script_name --outdir multiqc .

END_OF_HELP
}

###############################################################################
# Default values
###############################################################################

dry_run=false

###############################################################################
# Manual argument parsing (safe, collision-free)
###############################################################################

extra_parameters=()

while [[ $# -gt 0 ]]; do
    case "$1" in
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

Dry-run:      $dry_run


END_OF_PARAMETER_LOG

###############################################################################
# Build multiqc command
###############################################################################

cmd=(
    multiqc
    "${extra_parameters[@]}"
)

###############################################################################
# Execute multiqc
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
