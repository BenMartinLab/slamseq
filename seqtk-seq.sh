#SBATCH --account=def-bmartin
#SBATCH --time=03:00:00
#SBATCH --cpus-per-task=4
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
    echo
    echo "Usage: $script_name [options] -- [extra args passed to seqtk seq]"
    echo
    echo "Wrapper options:"
    echo "  --samplesheet FILE     Samplesheet CSV (default: samplesheet.csv)"
    echo "  --output-dir DIR       Output directory (default: bbduk-rv)"
    echo "  --fastq-dir  DIR       FASTQ directory (default: use paths in samplesheet)"
    echo "  --threads    INT       Threads (default: SLURM_CPUS_PER_TASK)"
    echo "  --dry-run              Print commands but do not execute"
    echo "  -h, --help             Show this help"
    echo
    echo "Everything after '--' or any unknown option is passed directly to seqtk seq."
    echo
    echo "Do not specify FASTQ files; they are inferred from the samplesheet."
    echo
    echo "Example:"
    echo "  sbatch --cpus-per-task=8 $script_name --samplesheet samples.csv -r"
    echo "  $script_name --samplesheet samples.csv -r"
    echo
}

###############################################################################
# Default values
###############################################################################

samplesheet="samplesheet.csv"
output_dir="bbduk-rv"
fastq_dir=""
threads="${SLURM_CPUS_PER_TASK:-1}"
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
        --threads)
            threads="$2"
            shift 2
            ;;
        --threads=*)
            threads="${1#--threads=}"
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
        --*=*)
            # Long option with equals: --option=value
            extra_parameters+=("$1")
            shift
            ;;
        -*)
            # Unknown short option → passthrough to kallisto
            extra_parameters+=("$1")
            shift
            ;;
        *)
            # Positional argument → passthrough
            extra_parameters+=("$1")
            shift
            ;;
    esac
done

tmp_dir="${SLURM_TMPDIR:-${output_dir}}"

###############################################################################
# Validate inputs
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
  # shellcheck disable=SC2178
  fastq=fastq_tmp
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

###############################################################################
# Build seqtk command
###############################################################################

cmd=(
    seqtk seq
    "${extra_parameters[@]}"
)

###############################################################################
# Dry-run mode
###############################################################################

echo "Samplesheet:  $samplesheet"
echo "FASTQ dir:    $fastq_dir"
echo "Output dir:   $output_dir"
echo "Threads:      $threads"
echo "Dry-run:      $dry_run"
echo
echo

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
    if [[ "$dry_run" == true ]]; then
        echo "Commands:"
        printf "  %q > %s" "${gunzip_cmd[@]}" "$gunzip_output"
        printf "  %q > %s" "${cmd[@]}" "$seqtk_output"
        printf "  %q > %s" "${gzip_cmd[@]}" "$output"
        return
    fi
    rm -f "$gunzip_output"
    "${gunzip_cmd[@]}" > "$gunzip_output"
    rm -f "$seqtk_output"
    "${cmd[@]}" > "$seqtk_output"
    rm -f "$output"
    "${gzip_cmd[@]}" > "$output"
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

mkdir -p "${output_dir}"
if [[ "$dry_run" == true ]]; then
    echo "Dry-run mode enabled — command not executed."
fi
parallel -j "$threads" \
    --env run_seqtk,cmd_str,output_dir,tmp_dir,dry_run \
    run_seqtk ::: "${fastq[@]}"
