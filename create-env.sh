#!/bin/bash

set -euo pipefail

###############################################################################
# Load modules on Alliance clusters
###############################################################################

if [[ -n "$CC_CLUSTER" ]]
then
  module purge
  module load StdEnv/2023
  module load python/3.13
fi

###############################################################################
# Script name detection
###############################################################################

script_path="${BASH_SOURCE[0]}"
if [[ "$(basename "$script_path")" == "slurm_script" && -n "${SLURM_JOB_ID:-}" ]]; then
    script_path="$(scontrol show job "$SLURM_JOB_ID" \
        | awk -F= '/Command=/ {print $2; exit}')"
fi
script_dir="$(dirname "$script_path")"

###############################################################################
# Create python virtual environment
###############################################################################

cd "$script_dir"
rm -rf slamseq-env
python -m venv slamseq-env
source slamseq-env/bin/activate
python -m pip install --upgrade pip
python -m pip install pysam==0.23.3
