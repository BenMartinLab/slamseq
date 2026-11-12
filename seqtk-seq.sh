#!/bin/bash
#SBATCH --account=def-bmartin
#SBATCH --time=03:00:00
#SBATCH --cpus-per-task=8
#SBATCH --mem=8G
#SBATCH --output=seqtk-seq-%A.out

set -euo pipefail

###############################################################################
# Load modules on Alliance clusters
###############################################################################

if [[ -n "${CC_CLUSTER:-}" ]]; then
    module purge
    module load StdEnv/2023
    module load seqtk/1.4
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
Usage: $script_name [options] -- [extra args passed to seqtk seq]

Wrapper options:
  --samplesheet FILE     Samplesheet CSV (default: samplesheet.csv)
  --output-dir DIR       Output directory (default: bbduk-rc)
  --fastq-dir  DIR       FASTQ directory (default: use paths in samplesheet)
  --jobs       INT       Number of jobslots for parallel (default: SLURM_CPUS_PER_TASK)
  --dry-run              Print commands but do not execute
  -h, --help             Show this help

Everything after '--' or any unknown option is passed directly to seqtk seq.

Do not specify FASTQ files; they are inferred from the samplesheet.

Example:
  sbatch --cpus-per-task=8 $script_name --samplesheet samples.csv -r
  $script_name --samplesheet samples.csv -r

END_OF_HELP
}

###############################################################################
# Default values
###############################################################################

samplesheet="samplesheet.csv"
output_dir="bbduk-rc"
fastq_dir=""
jobs="${SLURM_CPUS_PER_TASK:-1}"
dry_run=false

###############################################################################
# Manual argument parsing (safe, collision-free)
###############################################################################

extra_parameters=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --samplesheet)
            samplesheet="$2"
            shift 2
            ;;
        --samplesheet=*)
            samplesheet="${1#--samplesheet=}"
            shift
            ;;
        --output-dir)
            output_dir="$2"
            shift 2
            ;;
        --output-dir=*)
            output_dir="${1#--output-dir=}"
            shift
            ;;
        --fastq-dir)
            fastq_dir="$2"
            shift 2
            ;;
        --fastq-dir=*)
            fastq_dir="${1#--fastq-dir=}"
            shift
            ;;
        --jobs)
            jobs="$2"
            shift 2
            ;;
        --jobs=*)
            jobs="${1#--jobs=}"
            shift
            ;;
        --dry-run)
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

tmp_dir="${SLURM_TMPDIR:-${output_dir}}"

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

if [[ -n "$fastq_dir" ]]; then
  fastq_tmp=()
  for fq in "${fastq[@]}"; do
    fastq_tmp+=("${fastq_dir}/$(basename "$fq")")
  done
  fastq=("${fastq_tmp[@]}")
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

Samplesheet:  $samplesheet
FASTQ dir:    $fastq_dir
Output dir:   $output_dir
Jobs:         $jobs
Dry-run:      $dry_run


END_OF_PARAMETER_LOG

###############################################################################
# Build seqtk command
###############################################################################

cmd=(
    seqtk seq
    "${extra_parameters[@]}"
)

###############################################################################
# Seqtk execution block per FASTQ
###############################################################################

run_seqtk() {
    local _fastq="$1"

    IFS='|' read -r -a cmd <<< "$cmd_str"
    fastq_filename=$(basename "$_fastq")
    gunzip_cmd=(gunzip -c "$_fastq")
    gunzip_output="${tmp_dir}/${fastq_filename}.fastq"
    cmd=("${cmd[@]}" "$gunzip_output")
    seqtk_output="${tmp_dir}/${fastq_filename}_seqtk.fastq"
    gzip_cmd=(gzip -c "$seqtk_output")
    output="${output_dir}/${fastq_filename}"
    echo "Commands for fastq '$_fastq'"
    printf " %q " "${gunzip_cmd[@]}"
    printf " > "
    printf " %q " "$gunzip_output"
    echo
    printf " %q " "${cmd[@]}"
    printf " > "
    printf " %q " "$seqtk_output"
    echo
    printf " %q " "${gzip_cmd[@]}"
    printf " > "
    printf " %q " "$output"
    echo
    echo
    if [[ "$dry_run" == true ]]; then
        return
    fi
    rm -f "$gunzip_output"
    "${gunzip_cmd[@]}" > "$gunzip_output"
    rm -f "$seqtk_output"
    "${cmd[@]}" > "$seqtk_output"
    rm -f "$gunzip_output" "$output"
    "${gzip_cmd[@]}" > "$output"
    rm -f "$seqtk_output"
}
# Export for use with parallel.
export -f run_seqtk
cmd_str=$(printf "%s|" "${cmd[@]}")
export cmd_str
export output_dir
export tmp_dir
export dry_run

###############################################################################
# Execute seqtk
###############################################################################

if ! [[ "$dry_run" == true ]]; then
    mkdir -p "${output_dir}"
fi
parallel -j "$jobs" \
    --env run_seqtk,cmd_str,output_dir,tmp_dir,dry_run \
    run_seqtk ::: "${fastq[@]}"
echo
echo

if [[ "$dry_run" == true ]]; then
    echo "Dry-run mode enabled — command not executed."
    exit 0
fi
