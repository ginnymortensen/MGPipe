#!/bin/bash

# Genevieve Mortensen
# 03/17/2025
# Use this script on raw Illumina paired-end reads to trim and filter fastq.gz sequence files using fastp.

# Default settings
RAW_DIR="${1:-raw}"  # Directory containing raw sequence files (default: "raw")
OUTPUT_DIR="../results/trimmed"  # Directory for trimmed output
REPORT_DIR="../reports"  # Directory for fastp reports
LOG_FILE="$REPORT_DIR/mgpipe.log"  # Central log file for the entire pipeline
THREADS=4  # Number of threads to use for fastp

# Create output and report directories if they don't exist
mkdir -p "$OUTPUT_DIR" "$REPORT_DIR"

# Log the start of the trimming step
echo "Step 1: Trimming started."

# Function to check if a command is installed
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "Error: '$1' is not installed or not in PATH. Please install it and try again."
        exit 1
    fi
}

# Check if fastp is installed
check_command fastp

# Check if the raw directory exists and is not empty
if [[ ! -d "$RAW_DIR" ]]; then
    echo "Error: Directory '$RAW_DIR' does not exist. Please create it and place your raw sequence files there."
    exit 1
fi

if [[ -z "$(ls -A "$RAW_DIR")" ]]; then
    echo "Error: Directory '$RAW_DIR' is empty. Please add your raw sequence files."
    exit 1
fi

# Check if output directories are writable
if [[ ! -w "$OUTPUT_DIR" || ! -w "$REPORT_DIR" ]]; then
    echo "Error: No write permissions for output or report directories."
    exit 1
fi

# Function to find paired-end files
find_paired_files() {
    local r1_file="$1"
    local r2_file

    # Try multiple naming patterns for R2 files
    r2_file="${r1_file/_R1_001/_R2_001}"  # Default Illumina naming convention
    if [[ ! -f "$r2_file" ]]; then
        r2_file="${r1_file/_R1/_R2}"  # Alternative naming convention
    fi

    if [[ -f "$r2_file" ]]; then
        echo "$r2_file"
    else
        echo ""
    fi
}

# Loop over all R1 files in the directory
for R1_FILE in "$RAW_DIR"/*_R1*.fastq.gz; do
    # Extract base filename for R1 and R2
    BASENAME=$(basename "$R1_FILE" | sed 's/_R1.*//')
    R2_FILE=$(find_paired_files "$R1_FILE")

    # Create sample-level report directory
    SAMPLE_REPORT_DIR="$REPORT_DIR/$BASENAME"
    mkdir -p "$SAMPLE_REPORT_DIR"

    # Check if both R1 and R2 files exist
    if [[ -z "$R2_FILE" || ! -f "$R2_FILE" ]]; then
        echo "Error: Paired-end files for $BASENAME not found or incomplete. Skipping..."
        continue
    fi

    # Check if input files are valid FASTQ files
    if ! gunzip -t "$R1_FILE" || ! gunzip -t "$R2_FILE"; then
        echo "Error: Invalid or corrupted FASTQ files for $BASENAME. Skipping..."
        continue
    fi

    # Define output files for trimmed data and reports
    OUT_R1="$OUTPUT_DIR/${BASENAME}_R1_trimmed.fastq.gz"
    OUT_R2="$OUTPUT_DIR/${BASENAME}_R2_trimmed.fastq.gz"
    HTML_REPORT="$SAMPLE_REPORT_DIR/trimming.html"
    JSON_REPORT="$SAMPLE_REPORT_DIR/trimming.json"

    # Check if output files already exist
    if [[ -f "$OUT_R1" || -f "$OUT_R2" || -f "$HTML_REPORT" || -f "$JSON_REPORT" ]]; then
        echo "Warning: Output files for $BASENAME already exist. Please delete files if reprocessing is intended. Skipping to prevent overwriting..."
        continue
    fi

    # Run fastp on the paired-end files
    echo "Processing $BASENAME..."
    fastp -i "$R1_FILE" -I "$R2_FILE" \
          -o "$OUT_R1" -O "$OUT_R2" \
          --html "$HTML_REPORT" --json "$JSON_REPORT" \
          --thread "$THREADS" 2>> "$SAMPLE_REPORT_DIR/trimming.log"

    # Check if fastp succeeded
    if [[ $? -ne 0 ]]; then
        echo "Error: fastp failed for $BASENAME. Check $SAMPLE_REPORT_DIR/trimming.log for details."
        exit 1
    fi

    # Check if output files were generated
    if [[ ! -f "$OUT_R1" || ! -f "$OUT_R2" || ! -f "$HTML_REPORT" || ! -f "$JSON_REPORT" ]]; then
        echo "Error: Output files for $BASENAME not generated. Check fastp logs."
        exit 1
    fi

    echo "Finished trimming $BASENAME."
done

echo "Step 1: Trimming completed."