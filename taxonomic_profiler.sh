#!/bin/bash

# Genevieve Mortensen
# 03/17/2025
# This script runs Kraken2 for taxonomic profiling, Bracken for species-level reestimation,
# and generates combined BIOM tables for both Kraken2 and Bracken output.

# ----------------------------
#   Configuration
# ----------------------------
INDIR="../results/no_host"           # Directory containing non-host FASTQ files
TAX_DIR="../results/taxonomic_profile"
COMBINED_DIR="$TAX_DIR/combined_tables"
SAMPLE_DIR="$TAX_DIR/sample_tables"
KRAKEN_BRACKEN_DIR="$TAX_DIR/kraken2_bracken_output"
KRAKEN2_DB="k2_standard_20240605"  # Modify this as needed
BRACKEN_DB="$KRAKEN2_DB"           # Bracken DB uses the same Kraken2 DB
REPORT_DIR="../reports"
NUM_THREADS=16               # Threads for Kraken2 & Bracken
PARALLEL_JOBS=4             # Number of parallel samples
LOG_FILE="$REPORT_DIR/mgpipe.log"

# Create output/log directories if they don't exist
mkdir -p "$TAX_DIR" "$COMBINED_DIR" "$SAMPLE_DIR" "$KRAKEN_BRACKEN_DIR" "$REPORT_DIR"

echo "Step 3: Taxonomic profiling started."

# ----------------------------
#   Command Check
# ----------------------------
check_command() {
    if ! command -v "$1" &>/dev/null; then
        echo "Error: '$1' is not installed or not in PATH. Please install it."
        exit 1
    fi
}

check_command kraken2
check_command bracken
check_command kraken-biom

# ----------------------------
#   Validate Input Directory
# ----------------------------
if [[ ! -d "$INDIR" ]]; then
    echo "Error: Directory '$INDIR' does not exist. Please run host removal first."
    exit 1
fi

if [[ -z "$(ls -A "$INDIR")" ]]; then
    echo "Error: Directory '$INDIR' is empty. No no-host reads."
    exit 1
fi

# Check Kraken2 DB
if [[ ! -f "${KRAKEN2_DB}/taxo.k2d" ]]; then
    echo "Error: Kraken2 database not found at $KRAKEN2_DB."
    echo "Please reference https://benlangmead.github.io/aws-indexes/k2 for downloads."
    exit 1
fi

# ----------------------------
#   process_sample function
# ----------------------------
process_sample() {
    local R1_FILE="$1"
    local BASENAME
    BASENAME=$(basename "$R1_FILE" | sed 's/_R1_no_host.fastq//')
    local R2_FILE="$INDIR/${BASENAME}_R2_no_host.fastq"
    local SAMPLE_REPORT_DIR="$REPORT_DIR/$BASENAME"

    mkdir -p "$SAMPLE_REPORT_DIR"
    
    # Check if output files already exist
    if [[ -s "$KRAKEN_BRACKEN_DIR/${BASENAME}_kraken2_output.txt" && \
          -s "$KRAKEN_BRACKEN_DIR/${BASENAME}_bracken_output.txt" ]]; then
        echo "Warning: Kraken2 and Bracken output files for $BASENAME already exist. Please delete the files or move them if reprocessing is not needed. Skipping..."
        return 0
    fi

    if [[ -f "$R1_FILE" && -f "$R2_FILE" ]]; then
        echo "Processing sample $BASENAME..."

        # Run Kraken2
        kraken2 --db "$KRAKEN2_DB" \
                --paired "$R1_FILE" "$R2_FILE" \
                --threads "$NUM_THREADS" \
                --report "$KRAKEN_BRACKEN_DIR/${BASENAME}_kraken2_report.txt" \
                --output "$KRAKEN_BRACKEN_DIR/${BASENAME}_kraken2_output.txt" \
                2>> "$SAMPLE_REPORT_DIR/kraken2.log"

        if [[ $? -ne 0 ]]; then
            echo "Error: Kraken2 failed for $BASENAME. Check $SAMPLE_REPORT_DIR/kraken2.log."
            return 1
        fi
        echo "Kraken2 successfully processed $BASENAME."

        # Run Bracken
        bracken \
          -d "$BRACKEN_DB" \
          -i "$KRAKEN_BRACKEN_DIR/${BASENAME}_kraken2_report.txt" \
          -o "$KRAKEN_BRACKEN_DIR/${BASENAME}_bracken_output.txt" \
          -r 150 -l S \
          2>> "$SAMPLE_REPORT_DIR/bracken.log"

        if [[ $? -ne 0 ]]; then
            echo "Error: Bracken failed for $BASENAME. See $SAMPLE_REPORT_DIR/bracken.log."
            return 1
        fi
        echo "Bracken successfully processed $BASENAME."

        # Prepare OTU + taxonomy tables
        cut -f1,3 "$KRAKEN_BRACKEN_DIR/${BASENAME}_bracken_output.txt" \
          > "$SAMPLE_DIR/${BASENAME}_otu_table.txt"

        cut -f1,2 "$KRAKEN_BRACKEN_DIR/${BASENAME}_bracken_output.txt" | \
            awk 'BEGIN {FS="\t"; OFS="\t"} {split($2,tax,"|"); print $1,tax[1],tax[2],tax[3],tax[4],tax[5],tax[6]}' \
          > "$SAMPLE_DIR/${BASENAME}_taxonomy_table.txt"

        echo "Finished processing sample $BASENAME."
    else
        echo "Warning: Paired-end files for $BASENAME not found or incomplete."
    fi
}

# ----------------------------
#   Parallel Execution
# ----------------------------
# We'll replicate the "job_count + wait" approach from the host removal script
# ----------------------------
#   Parallel Execution
# ----------------------------
run_parallel() {
    local failed=0
    local pids=()
    local files=("$INDIR"/*_R1_no_host.fastq)

    for R1_FILE in "${files[@]}"; do
        # Limit parallel jobs
        if [[ ${#pids[@]} -ge $PARALLEL_JOBS ]]; then
            wait "${pids[0]}"
            if [[ $? -ne 0 ]]; then
                ((failed++))
            fi
            pids=("${pids[@]:1}") # Remove finished PID
        fi

        process_sample "$R1_FILE" &
        pids+=("$!")
    done

    # Wait for remaining jobs
    for pid in "${pids[@]}"; do
        wait "$pid"
        if [[ $? -ne 0 ]]; then
            ((failed++))
        fi
    done

    if [[ $failed -gt 0 ]]; then
        echo "Error: Failed processing $failed samples"
        return 1
    fi
}

if ! run_parallel; then
    exit 1
fi

# ----------------------------
#   Combine Results
# ----------------------------
echo "Combining OTU tables into a single file..."
paste "$SAMPLE_DIR"/*_otu_table.txt > "$COMBINED_DIR/combined_otu_table.txt"
echo "Combined OTU table saved to $COMBINED_DIR/combined_otu_table.txt."

echo "Combining taxonomy tables into a single file..."
paste "$SAMPLE_DIR"/*_taxonomy_table.txt > "$COMBINED_DIR/combined_taxonomy_table.txt"
echo "Combined taxonomy table saved to $COMBINED_DIR/combined_taxonomy_table.txt."

echo "Converting Kraken2 reports to BIOM format..."
kraken-biom "$KRAKEN_BRACKEN_DIR"/*_kraken2_report.txt \
            -o "$COMBINED_DIR/kraken2_combined.biom"
echo "Kraken2 BIOM table saved to $COMBINED_DIR/kraken2_combined.biom."

echo "Converting Bracken reports to BIOM format..."
kraken-biom "$KRAKEN_BRACKEN_DIR"/*_bracken_output.txt \
            -o "$COMBINED_DIR/bracken_combined.biom"
echo "Bracken BIOM table saved to $COMBINED_DIR/bracken_combined.biom."

echo "Step 3: Taxonomic profiling completed."