#!/bin/bash

# Genevieve Mortensen
# 03/21/2025
# Script to run HUMAnN3 for functional profiling of metagenomic data and prepare output for Phyloseq.

# ----------------------------
#   Configuration
# ----------------------------
INDIR="../results/no_host"  # Directory containing non-host FASTQ files
FUNC_DIR="../results/functional_profile"  # Main output directory for HUMAnN3 results
SAMPLE_DIR="$FUNC_DIR/sample_tables"  
RENORM_DIR="$FUNC_DIR/renormalized_tables"
RESTRAT_DIR="$FUNC_DIR/restratified_tables"
COMBINED_DIR="$FUNC_DIR/combined_tables"
DB_DIR="humann_databases"  # Modify this path if needed
CHOCOPHLAN_DB="$DB_DIR/chocophlan"
UNIREF_DB="$DB_DIR/uniref"
REPORT_DIR="../reports"
NUM_THREADS=8
PARALLEL_JOBS=4
LOG_FILE="$REPORT_DIR/mgpipe.log"

# Create output/report/db directories if needed
mkdir -p "$FUNC_DIR" "$SAMPLE_DIR" "$RENORM_DIR" "$COMBINED_DIR" "$REPORT_DIR" "$DB_DIR" "$RESTRAT_DIR"

echo "Step 4: Functional profiling started."

# ----------------------------
#   Check HUMAnN3
# ----------------------------
if ! command -v humann &> /dev/null; then
    echo "Error: HUMAnN3 is not installed or not in PATH. Please install and try again."
    echo "Refer to: https://github.com/biobakery/humann"
    exit 1
fi

# ----------------------------
#   Check or Download Databases
# ----------------------------
if [[ ! -d "$CHOCOPHLAN_DB" ]]; then
    echo "ChocoPhlAn database not found. Downloading..."
    humann_databases --download chocophlan full "$CHOCOPHLAN_DB" >> "$LOG_FILE" 2>&1
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to download ChocoPhlAn. Exiting."
        exit 1
    fi
    echo "ChocoPhlAn database downloaded successfully."
else
    echo "ChocoPhlAn database found."
fi

if [[ ! -d "$UNIREF_DB" ]]; then
    echo "UniRef90 database not found. Downloading..."
    humann_databases --download uniref uniref90_diamond "$UNIREF_DB" >> "$LOG_FILE" 2>&1
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to download UniRef90. Exiting."
        exit 1
    fi
    echo "UniRef90 database downloaded successfully."
else
    echo "UniRef90 database found."
fi

# ----------------------------
#   Functions
# ----------------------------

# Normalizes and splits tables for Phyloseq
process_tables() {
    local BASENAME="$1"
    local GENEFAMILIES_FILE="$SAMPLE_DIR/${BASENAME}_concatenated_genefamilies.tsv"
    local PATHABUNDANCE_FILE="$SAMPLE_DIR/${BASENAME}_concatenated_pathabundance.tsv"

    echo "Normalizing/splitting gene families & pathways for $BASENAME..."

    # Normalize gene families
    humann_renorm_table --input "$SAMPLE_DIR/${BASENAME}_concatenated_genefamilies.tsv" \
                        --output "$RENORM_DIR/${BASENAME}_genefamilies_relab.tsv" \
                        --units relab >> "$LOG_FILE" 2>&1

    # Normalize pathway abundances
    humann_renorm_table --input "$SAMPLE_DIR/${BASENAME}_concatenated_pathabundance.tsv" \
                        --output "$RENORM_DIR/${BASENAME}_pathabundance_relab.tsv" \
                        --units relab >> "$LOG_FILE" 2>&1

    # Split stratified vs unstratified gene families
    humann_split_stratified_table --input "$RENORM_DIR/${BASENAME}_genefamilies_relab.tsv" \
                                  --output "$RESTRAT_DIR" \
                                  >> "$LOG_FILE" 2>&1

    humann_split_stratified_table --input "$RENORM_DIR/${BASENAME}_pathabundance_relab.tsv" \
                                  --output "$RESTRAT_DIR" \
                                  >> "$LOG_FILE" 2>&1

    echo "Renormalized & restratified files for $BASENAME done."
}

# Processes a single sample with HUMAnN3
process_sample() {
    local R1_FILE="$1"
    local BASENAME
    BASENAME=$(basename "$R1_FILE" | sed 's/_R1_no_host.fastq//')
    local SAMPLE_REPORT_DIR="$REPORT_DIR/$BASENAME"
    local GENEFAMILIES_FILE="$SAMPLE_DIR/${BASENAME}_concatenated_genefamilies.tsv"
    local PATHABUNDANCE_FILE="$SAMPLE_DIR/${BASENAME}_concatenated_pathabundance.tsv"

    mkdir -p "$SAMPLE_REPORT_DIR"

    # Check if output already exists
    if [[ -f "$GENEFAMILIES_FILE" && -f "$PATHABUNDANCE_FILE" ]]; then
        echo "HUMAnN3 output found for $BASENAME. Skipping HUMAnN3 run."
        process_tables "$BASENAME"
    else
        echo "Running HUMAnN3 for $BASENAME..."

        local R2_FILE="$INDIR/${BASENAME}_R2_no_host.fastq"
        local CONCAT_FILE="$INDIR/${BASENAME}_concatenated.fastq"

        if [[ -f "$R1_FILE" && -f "$R2_FILE" ]]; then
            # Concatenate read pairs
            echo "Concatenating $R1_FILE + $R2_FILE -> $CONCAT_FILE"
            cat "$R1_FILE" "$R2_FILE" > "$CONCAT_FILE"

            # Run HUMAnN
            humann --input "$CONCAT_FILE" \
                   --output "$SAMPLE_DIR" \
                   --threads "$NUM_THREADS" \
                   --protein-database "$UNIREF_DB" \
                   --remove-temp-output \
                   >> "$SAMPLE_REPORT_DIR/humann.log" 2>&1

            if [[ $? -eq 0 ]]; then
                echo "HUMAnN3 finished for $BASENAME."
                process_tables "$BASENAME"
            else
                echo "Error: HUMAnN3 failed for $BASENAME. Check $SAMPLE_REPORT_DIR/humann.log."
            fi
        else
            echo "Warning: R2 not found for $BASENAME. Skipping."
        fi
    fi
}

# ----------------------------
#   Parallel Execution
# ----------------------------
declare -a pids=()
failed=0

# Validate input directory first
if [[ ! -d "$INDIR" ]]; then
    echo "Error: Input directory $INDIR does not exist."
    exit 1
fi

# Get list of input files
input_files=("$INDIR"/*_R1_no_host.fastq)
if [[ ${#input_files[@]} -eq 0 ]]; then
    echo "Error: No input files found in $INDIR"
    exit 1
fi

# Process files in parallel
for R1_FILE in "${input_files[@]}"; do
    # Skip invalid files
    [[ -f "$R1_FILE" ]] || continue

    # Process sample in background
    process_sample "$R1_FILE" &
    pids+=("$!")

    # Limit number of parallel jobs
    if [[ ${#pids[@]} -ge $PARALLEL_JOBS ]]; then
        # Wait for oldest job to finish
        if wait "${pids[0]}"; then
            # Remove finished PID from array
            pids=("${pids[@]:1}")
        else
            ((failed++))
        fi
    fi
done

# Wait for remaining jobs
for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
        ((failed++))
    fi
done

# Handle failures
if (( failed > 0 )); then
    echo "Error: $failed samples failed processing"
    exit 1
fi

echo "HUMAnN3 processing completed successfully."

# ----------------------------
#   Combine Final Results
# ----------------------------
echo "Combining gene families/pathways into single tables..."

humann_join_tables --input "$RESTRAT_DIR" \
                   --output "$COMBINED_DIR/combined_genefamilies_relab_unstratified.tsv" \
                   --file_name "genefamilies_relab_unstratified" \
                   >> "$LOG_FILE" 2>&1

humann_join_tables --input "$RESTRAT_DIR" \
                   --output "$COMBINED_DIR/combined_pathabundance_relab_unstratified.tsv" \
                   --file_name "pathabundance_relab_unstratified" \
                   >> "$LOG_FILE" 2>&1

echo "Combined tables in $COMBINED_DIR."
echo "Step 4: Functional profiling completed."