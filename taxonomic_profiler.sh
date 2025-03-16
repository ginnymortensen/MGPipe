#!/bin/bash

# Genevieve Mortensen
# 09/11/2024
# This script runs Kraken2 for taxonomic profiling and Bracken for abundance estimation.

# Directories and files
INDIR="non_host"  # Full path to processed, non-host FASTQ files
OUTPUT_DIR="taxonomy_output"  # Directory to store Kraken2/Bracken output
KRAKEN2_DB="k2_standard_20240605"  # Full path to Kraken2 database
BRACKEN_DB="k2_standard_20240605"  # Bracken uses the same Kraken2 database
FINAL_DIR="output"  # Directory to store Phyloseq-compatible files
REPORT_DIR="reports"
NUM_THREADS=16  # Number of threads to use for Kraken2 and Bracken
PARALLEL_JOBS=4  # Number of parallel jobs to run simultaneously

# Create output directories if they don't exist
mkdir -p "$OUTPUT_DIR"
mkdir -p "$FINAL_DIR"
mkdir -p "$REPORT_DIR"

# Check if Kraken2 database exists
if [[ ! -f "${KRAKEN2_DB}/taxo.k2d" ]]; then
    echo "Kraken2 database not found at $KRAKEN2_DB." 
    echo "To download the most recent database, please reference https://benlangmead.github.io/aws-indexes/k2."
    echo "If the downloaded version is different from $KRAKEN2_DB, please change the associated paths in taxonomic_profiler.sh"
fi

# Function to process each sample
process_sample() {
    local R1_FILE="$1"
    local BASENAME=$(basename "$R1_FILE" | sed 's/_R1_non_host.fastq//')
    local R2_FILE="$INDIR/${BASENAME}_R2_non_host.fastq"

    if [[ -f "$R1_FILE" && -f "$R2_FILE" ]]; then
        echo "Processing sample $BASENAME..."

        # Run Kraken2 for taxonomic classification
        kraken2 --db "$KRAKEN2_DB" \
                --paired "$R1_FILE" "$R2_FILE" \
                --threads "$NUM_THREADS" \
                --report "$OUTPUT_DIR/${BASENAME}_kraken2_report.txt" \
                --output "$OUTPUT_DIR/${BASENAME}_kraken2_output.txt" \
                2> "$REPORT_DIR/${BASENAME}_kraken2.log"

        if [[ $? -eq 0 ]]; then
            echo "Kraken2 successfully processed $BASENAME."
            
            # Run Bracken for abundance estimation
            bracken -d "$BRACKEN_DB" \
                    -i "$OUTPUT_DIR/${BASENAME}_kraken2_report.txt" \
                    -o "$OUTPUT_DIR/${BASENAME}_bracken_output.txt" \
                    -r 150 -l S \
                    2> "$REPORT_DIR/${BASENAME}_bracken.log"

            if [[ $? -eq 0 ]]; then
                echo "Bracken successfully processed $BASENAME."
                
                # Prepare OTU and taxonomy tables for Phyloseq
                cut -f1,3 "$OUTPUT_DIR/${BASENAME}_bracken_output.txt" > "$FINAL_DIR/${BASENAME}_otu_table.txt"
                cut -f1,2 "$OUTPUT_DIR/${BASENAME}_bracken_output.txt" | \
                    awk 'BEGIN {FS="\t"; OFS="\t"} {split($2,tax,"|"); print $1,tax[1],tax[2],tax[3],tax[4],tax[5],tax[6]}' \
                    > "$FINAL_DIR/${BASENAME}_taxonomy_table.txt"

                echo "Finished processing sample $BASENAME."
            else
                echo "Error: Bracken failed for $BASENAME. Check the log for details."
            fi
        else
            echo "Error: Kraken2 failed for $BASENAME. Check the log for details."
        fi
    else
        echo "Warning: Paired-end files for $BASENAME not found or incomplete."
    fi
}

# Export functions and variables for parallel execution
export -f process_sample
export INDIR OUTPUT_DIR KRAKEN2_DB BRACKEN_DB FINAL_DIR REPORT_DIR NUM_THREADS

# Run sample processing in parallel using xargs
find "$INDIR" -name '*_R1_non_host.fastq' | xargs -n 1 -P "$PARALLEL_JOBS" -I {} bash -c 'process_sample "$@"' _ {}
