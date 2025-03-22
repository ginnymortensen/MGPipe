#!/bin/bash

# Genevieve Mortensen
# 03/17/2025
# Use this script to remove host genome sequences from trimmed reads using bowtie2.

# Default directories and files
TRIMMED_DIR="../results/trimmed"     # Directory containing trimmed reads
OUTPUT_DIR="../results/no_host"      # Directory for non-host reads
DB_PATH="bowtie_indexes"             # Directory for Bowtie2 index
INDEX_NAME="grch38_1kgmaj"           # Name of the Bowtie2 index
INDEX_PATH="${DB_PATH}/${INDEX_NAME}"  # Path to Bowtie2 index
FASTA_PATH="${DB_PATH}/${INDEX_NAME}.fa"  # Path to host genome FASTA file
FASTA_URL="ftp://ftp.ccb.jhu.edu/pub/data/bowtie_indexes/${INDEX_NAME}.fa.gz"  # URL to download FASTA
REPORT_DIR="../reports"              # Directory for reports
LOG_FILE="$REPORT_DIR/mgpipe.log"    # Central log file for the entire pipeline
NUM_THREADS=8                        # Threads for Bowtie2, Samtools
PARALLEL_JOBS=4                      # How many samples to process in parallel

# Create output and report directories if they don't exist
mkdir -p "$OUTPUT_DIR" "$REPORT_DIR" "$DB_PATH"

echo "Step 2: Host removal started."

# Function to check if a command is installed
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "Error: '$1' is not installed or not in PATH. Please install it and try again."
        exit 1
    fi
}

# Check required tools
check_command bowtie2
check_command samtools
check_command bedtools

# Check the trimmed directory
if [[ ! -d "$TRIMMED_DIR" ]]; then
    echo "Error: Directory '$TRIMMED_DIR' does not exist. Please run the trimming step first."
    exit 1
fi

if [[ -z "$(ls -A "$TRIMMED_DIR")" ]]; then
    echo "Error: Directory '$TRIMMED_DIR' is empty. Please add trimmed sequence files."
    exit 1
fi

# Check or build Bowtie2 index
if [[ ! -f "${INDEX_PATH}.1.bt2" ]]; then
    echo "Bowtie2 index not found."

    # Check if the FASTA file exists
    if [[ ! -f "$FASTA_PATH" ]]; then
        echo "FASTA file not found. Downloading from $FASTA_URL..."
        if ! wget -O "$FASTA_PATH.gz" "$FASTA_URL"; then
            echo "Error: Failed to download FASTA file. Exiting."
            exit 1
        fi

        if ! gunzip "$FASTA_PATH.gz"; then
            echo "Error: Failed to unzip FASTA file. Exiting."
            exit 1
        fi

        echo "FASTA file downloaded and unzipped successfully."
    else
        echo "FASTA file found. Proceeding to build the Bowtie2 index."
    fi

    echo "Building Bowtie2 index from ${FASTA_PATH}..."
    if ! bowtie2-build "$FASTA_PATH" "$INDEX_PATH"; then
        echo "Error: Failed to build Bowtie2 index. Check disk space and memory."
        exit 1
    fi
    echo "Bowtie2 index successfully built."
else
    echo "Bowtie2 index found. Proceeding with alignment."
fi

# -------------------------------
# Define the function to process a single sample
# -------------------------------
process_sample() {
    local R1_FILE="$1"
    local BASENAME
    BASENAME=$(basename "$R1_FILE" | sed 's/_R1_trimmed.fastq.gz//')
    local R2_FILE="$TRIMMED_DIR/${BASENAME}_R2_trimmed.fastq.gz"
    local SAMPLE_REPORT_DIR="$REPORT_DIR/$BASENAME"

    mkdir -p "$SAMPLE_REPORT_DIR"

    if [[ -f "$R1_FILE" && -f "$R2_FILE" ]]; then
        echo "Processing sample $BASENAME..."

        # Validate input FASTQ
        if ! gunzip -t "$R1_FILE" || ! gunzip -t "$R2_FILE"; then
            echo "Error: Invalid or corrupted FASTQ files for $BASENAME. Skipping..."
            return 1
        fi

        # Check if output files already exist
        if [[ -s "$OUTPUT_DIR/${BASENAME}_R1_no_host.fastq" && \
              -s "$OUTPUT_DIR/${BASENAME}_R2_no_host.fastq" ]]; then
            echo "Warning: Output files for $BASENAME already exist. Skipping..."
            return 0
        fi

        # Align to host
        bowtie2 -x "$INDEX_PATH" \
                -1 "$R1_FILE" -2 "$R2_FILE" \
                --very-sensitive \
                -p "$NUM_THREADS" \
                --met-file "$SAMPLE_REPORT_DIR/bowtie2_metrics.txt" \
                -S "$OUTPUT_DIR/${BASENAME}_human_mapped.sam"

        if [[ $? -ne 0 ]]; then
            echo "Error: Bowtie2 failed for $BASENAME."
            return 1
        fi

        # Convert SAM to BAM
        samtools view -bS "$OUTPUT_DIR/${BASENAME}_human_mapped.sam" \
          -o "$OUTPUT_DIR/${BASENAME}_human_mapped.bam" -@ "$NUM_THREADS"

        if [[ $? -ne 0 ]]; then
            echo "Error: Failed to convert SAM to BAM for $BASENAME."
            return 1
        fi

        # Extract unmapped (non-host) reads
        samtools view -b -f 12 -F 256 "$OUTPUT_DIR/${BASENAME}_human_mapped.bam" \
          -o "$OUTPUT_DIR/${BASENAME}_non_human.bam" -@ "$NUM_THREADS"

        if [[ $? -ne 0 ]]; then
            echo "Error: Failed to extract non-host reads for $BASENAME."
            return 1
        fi

        # Convert non-host BAM to FASTQ
        bedtools bamtofastq \
          -i "$OUTPUT_DIR/${BASENAME}_non_human.bam" \
          -fq "$OUTPUT_DIR/${BASENAME}_R1_no_host.fastq" \
          -fq2 "$OUTPUT_DIR/${BASENAME}_R2_no_host.fastq"

        if [[ $? -ne 0 ]]; then
            echo "Error: Failed to convert BAM to FASTQ for $BASENAME."
            return 1
        fi

        # Check if output files are empty
        if [[ ! -s "$OUTPUT_DIR/${BASENAME}_R1_no_host.fastq" || \
              ! -s "$OUTPUT_DIR/${BASENAME}_R2_no_host.fastq" ]]; then
            echo "Error: Output files for $BASENAME are empty."
            return 1
        fi

        # Clean up
        rm -f "$OUTPUT_DIR/${BASENAME}_human_mapped.sam"
        rm -f "$OUTPUT_DIR/${BASENAME}_human_mapped.bam"

        echo "Finished processing sample $BASENAME."
    else
        echo "Error: Paired-end files for $BASENAME not found or incomplete."
        return 1
    fi
}

# ------------------------------------
# Process all R1 files in parallel
# ------------------------------------
# Track background job PIDs and overall exit status
declare -a PIDS
FAILED=0

for R1_FILE in "$TRIMMED_DIR"/*_R1_trimmed.fastq.gz; do
    # Skip if there's no matching file
    [[ -f "$R1_FILE" ]] || continue

    # Launch process_sample in the background
    process_sample "$R1_FILE" &
    PIDS+=("$!")  # Store PID of the background job

    # Limit the number of parallel jobs
    if [[ "${#PIDS[@]}" -ge "$PARALLEL_JOBS" ]]; then
        # Wait for all current jobs to finish
        for PID in "${PIDS[@]}"; do
            wait "$PID" || ((FAILED++))
        done
        PIDS=()  # Reset PIDs array
    fi
done

# Wait for any remaining jobs
for PID in "${PIDS[@]}"; do
    wait "$PID" || ((FAILED++))
done

# Exit with error if any job failed
if [[ "$FAILED" -gt 0 ]]; then
    echo "Error: $FAILED sample(s) failed during host removal."
    exit 1
fi

echo "Step 2: Host removal completed."