###############################################################################
# Extract sample names from samplesheet
###############################################################################

collect_samples() {
    local samplesheet="$1"
    local -n out_samples="$2"

    sample_column=$(awk -F ',' \
        'NR == 1 {for (i = 1; i <= NF; i++) if (gensub(/[[:cntrl:]\n]/, "", "g", $i) == "sample") {print i; exit(0)}}' \
        "$samplesheet")
    mapfile -t out_samples < <(
        awk -F ',' -v sample_column="${sample_column}" \
        'NR>1 {gsub(/[[:cntrl:]]/, "", $sample_column); print $sample_column}' "$samplesheet"
    )
}


###############################################################################
# Extract FASTQ files from samplesheet
###############################################################################

collect_fastq() {
    local samplesheet="$1"
    local -n out_fastq="$2"

    fastq1_column=$(awk -F ',' \
        'NR == 1 {for (i = 1; i <= NF; i++) if (gensub(/[[:cntrl:]\n]/, "", "g", $i) == "fastq_1") {print i; exit(0)}}' \
        "$samplesheet")
    fastq2_column=$(awk -F ',' \
        'NR == 1 {for (i = 1; i <= NF; i++) if (gensub(/[[:cntrl:]\n]/, "", "g", $i) == "fastq_2") {print i; exit(0)}}' \
        "$samplesheet")
    mapfile -t out_fastq < <(
        awk -F ',' -v fastq1_column="${fastq1_column}" \
        'NR>1 {gsub(/[[:cntrl:]]/, "", $fastq1_column); print $fastq1_column}' "$samplesheet"
    )
    if [[ -n "$fastq2_column" ]]; then
        mapfile -t fastq2 < <(
            awk -F ',' -v fastq2_column="${fastq2_column}" \
            'NR>1 {gsub(/[[:cntrl:]]/, "", $fastq2_column); if ($fastq2_column != "") print $fastq2_column}' "$samplesheet"
        )
        out_fastq+=("${fastq2[@]}")
    fi
}
