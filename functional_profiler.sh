#!/bin/bash

# Genevieve Mortensen
# 09/23/2024
# Script to run HUMAnN3 for functional profiling of metagenomic data and prepare output for Phyloseq.

# Directories and files
INDIR="non_host"  # Full path to processed, non-host FASTQ files
OUTPUT_DIR="humann_output"  # Directory to store HUMAnN3 output
PHYLOSEQ_DIR="output"  # Directory to store Phyloseq-compatible files
LOG_DIR="humann_logs"  # Directory to store logs for each sample
DB_DIR="humann_databases"  # Path to HUMAnN3 database directory
CHOCOPHLAN_DB="$DB_DIR/chocophlan"  # ChocoPhlAn database path
UNIREF_DB="$DB_DIR/uniref"  # UniRef database path
NUM_THREADS=16  # Number of threads to use for HUMAnN3
PARALLEL_JOBS=4  # Number of parallel jobs to run simultaneously

# Create output directories if they don't exist
mkdir -p "$OUTPUT_DIR"
mkdir -p "$LOG_DIR"
mkdir -p "$PHYLOSEQ_DIR"

# Check if HUMAnN3 is installed
if ! command -v humann &> /dev/null; then
    echo "HUMAnN3 is not installed. Please refer to the GitHub repository for installation instructions:"
    echo "https://github.com/biobakery/humann"
fi

# Check and download ChocoPhlAn database if necessary
if [ ! -d "$CHOCOPHLAN_DB" ]; then
    echo "ChocoPhlAn database not found in $DB_DIR. Downloading the ChocoPhlAn database..."
    humann_databases --download chocophlan full "$CHOCOPHLAN_DB"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to download ChocoPhlAn database. Exiting."
    fi
else
    echo "ChocoPhlAn database found."
fi

# Check and download UniRef database if necessary
if [ ! -d "$UNIREF_DB" ]; then
    echo "UniRef90 database not found in $DB_DIR. Downloading the UniRef90 database..."
    humann_databases --download uniref uniref90_diamond "$UNIREF_DB"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to download UniRef90 database. Exiting."
    fi
else
    echo "UniRef90 database found."
fi

# Function to normalize and split tables for Phyloseq
process_phyloseq() {
    local BASENAME="$1"
    local GENEFAMILIES_FILE="$OUTPUT_DIR/${BASENAME}/${BASENAME}_concatenated_genefamilies.tsv"
    local PATHABUNDANCE_FILE="$OUTPUT_DIR/${BASENAME}/${BASENAME}_concatenated_pathabundance.tsv"

    echo "Normalizing and splitting gene families and pathways for $BASENAME..."

    # Normalize gene families
    humann_renorm_table --input "$GENEFAMILIES_FILE" \
                        --output "$PHYLOSEQ_DIR/${BASENAME}_genefamilies_renorm.tsv" \
                        --units relab

    # Normalize pathway abundances
    humann_renorm_table --input "$PATHABUNDANCE_FILE" \
                        --output "$PHYLOSEQ_DIR/${BASENAME}_pathabundance_renorm.tsv" \
                        --units relab

    # Split stratified and unstratified gene families
    humann_split_stratified_table --input "$PHYLOSEQ_DIR/${BASENAME}_genefamilies_renorm.tsv" \
                                  --output "$PHYLOSEQ_DIR/${BASENAME}_genefamilies_unstrat.tsv"

    # Split stratified and unstratified pathways
    humann_split_stratified_table --input "$PHYLOSEQ_DIR/${BASENAME}_pathabundance_renorm.tsv" \
                                  --output "$PHYLOSEQ_DIR/${BASENAME}_pathabundance_unstrat.tsv"

    echo "Phyloseq-compatible files generated for $BASENAME."
}

# Function to process each sample
process_sample() {
    local R1_FILE="$1"
    local BASENAME=$(basename "$R1_FILE" | sed 's/_R1_non_host.fastq//')
    local SAMPLE_OUTPUT_DIR="$OUTPUT_DIR/$BASENAME"
    local GENEFAMILIES_FILE="$SAMPLE_OUTPUT_DIR/${BASENAME}_concatenated_genefamilies.tsv"
    local PATHABUNDANCE_FILE="$SAMPLE_OUTPUT_DIR/${BASENAME}_concatenated_pathabundance.tsv"

    # Check if HUMAnN3 output already exists
    if [[ -f "$GENEFAMILIES_FILE" && -f "$PATHABUNDANCE_FILE" ]]; then
        echo "HUMAnN3 output already exists for $BASENAME. Proceeding to normalization and splitting."
        process_phyloseq "$BASENAME"
    else
        echo "HUMAnN3 output not found for $BASENAME. Running HUMAnN3..."

        local R2_FILE="$INDIR/${BASENAME}_R2_non_host.fastq"
        local CONCAT_FILE="$INDIR/${BASENAME}_concatenated.fastq"

        if [[ -f "$R1_FILE" && -f "$R2_FILE" ]]; then
            # Concatenate shotgun reads
            echo "Concatenating $R1_FILE and $R2_FILE into $CONCAT_FILE"
            cat "$R1_FILE" "$R2_FILE" > "$CONCAT_FILE"

            # Run HUMAnN3
            humann --input "$CONCAT_FILE" \
                   --output "$SAMPLE_OUTPUT_DIR" \
                   --threads "$NUM_THREADS" \
                   --protein-database "$UNIREF_DB" \
                   --remove-temp-output \
                   > "$LOG_DIR/${BASENAME}_humann.log" 2>&1

            if [[ $? -eq 0 ]]; then
                echo "HUMAnN3 successfully processed $BASENAME."
                process_phyloseq "$BASENAME"
            else
                echo "Error: HUMAnN3 failed for $BASENAME. Check the log for details."
            fi
        else
            echo "Warning: Paired-end files for $BASENAME not found or incomplete."
        fi
    fi
}


# Export functions and variables for parallel execution
export -f process_sample process_phyloseq
export INDIR OUTPUT_DIR PHYLOSEQ_DIR LOG_DIR DB_DIR CHOCOPHLAN_DB UNIREF_DB NUM_THREADS

# Run sample processing in parallel using xargs
find "$INDIR" -name '*_R1_non_host.fastq' | xargs -n 1 -P "$PARALLEL_JOBS" -I {} bash -c 'process_sample "$@"' _ {}

echo "All samples processed."

