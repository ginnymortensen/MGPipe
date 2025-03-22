#!/bin/bash

# Genevieve Mortensen
# 03/17/2025
# Wrapper script to run various metagenomic processing scripts with conda environment setup.
# Allows the user to skip taxonomic profiling and functional profiling steps.

# Change this so it points to your conda installation
CONDAPATH="/home/gamorten/bin/miniconda3/etc/profile.d/conda.sh"
source "$CONDAPATH"  # Load conda functions
# Default behavior: don't skip anything
SKIP_TAXONOMIC_PROFILER=false
SKIP_FUNCTIONAL_PROFILER=false
ENV_NAME="mgpipe_env"
ENV_YAML="mgpipe_env.yaml"  # Path to the YAML file to create the environment
REPORT_DIR="../reports"  # Directory for fastp reports
LOG_FILE="$REPORT_DIR/mgpipe.log"

mkdir -p "$REPORT_DIR"  # Create the reports directory if it doesn't exist

# Redirect all output to the log file
exec > >(tee -a "$LOG_FILE") 2>&1

# Function to display help message
display_help() {
    echo "Usage: $0 [--skip stage1,stage2]"
    echo "Options:"
    echo "  --skip stage1,stage2   Skip specific stages of the pipeline."
    echo "                         Valid stages: taxonomic_profiler, functional_profiler"
    echo "  --help                 Display this help message."
}


# Function to deactivate current conda environment if active
deactivate_conda_env() {
    if [[ -n "$CONDA_PREFIX" ]]; then
        echo "Deactivating the current Conda environment: $CONDA_PREFIX"
        conda deactivate
    fi
}

# Function to check and create mgpipe environment if it doesn't exist
setup_conda_env() {
    if ! conda info --envs | grep -q "^$ENV_NAME"; then
        echo "Conda environment '$ENV_NAME' not found. Creating it..."
        if [[ -f "$ENV_YAML" ]]; then
            conda env create --name "$ENV_NAME" --file "$ENV_YAML"
            if [[ $? -ne 0 ]]; then
                echo "Error: Failed to create Conda environment '$ENV_NAME'. Check the log file for details."
                exit 1
            fi
        else
            echo "Error: Environment YAML file '$ENV_YAML' not found."
            exit 1
        fi
    else
        echo "Conda environment '$ENV_NAME' already exists."
    fi

    # Activate the mgpipe environment
    echo "Activating the Conda environment: $ENV_NAME"
    conda activate "$ENV_NAME"
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to activate Conda environment '$ENV_NAME'. Check the log file for details."
        exit 1
    fi

    # Debugging: Output PATH and conda environment info
    echo "Current PATH after activation: $PATH"
    echo "Conda environment info:"
    conda info
    echo "Conda environment packages:"
    conda list

    # Explicitly export PATH and conda variables for subshells
    export PATH
    export CONDA_PREFIX
    export CONDA_DEFAULT_ENV="$ENV_NAME"
}

# Function to parse the --skip argument
parse_skip() {
    IFS=',' read -ra SKIP <<< "$1"  # Split the argument into an array based on commas
    for skip_stage in "${SKIP[@]}"; do
        case "$skip_stage" in
            taxonomic_profiler)
                SKIP_TAXONOMIC_PROFILER=true
                ;;
            functional_profiler)
                SKIP_FUNCTIONAL_PROFILER=true
                ;;
            *)
                echo "Error: Invalid skip option: '$skip_stage'. Use one or more of: taxonomic_profiler, functional_profiler"
                exit 1
                ;;
        esac
    done
}

# Function to check if a script exists and is executable
check_script() {
    local script_name="$1"
    if [[ ! -f "$script_name" || ! -x "$script_name" ]]; then
        echo "Error: Script '$script_name' not found or not executable."
        exit 1
    fi
}

# Function to run trimmer.sh and handle the raw directory
run_trimmer() {
    # Check if the 'raw' directory exists
    if [[ -d "../raw" ]]; then
        echo "Found 'raw' directory. Using it for input."
        RAW_DIR="../raw"
    else
        # If 'raw' directory is not found, prompt the user to provide one
        echo "'raw' directory not found. Please provide the path to the raw sequence directory:"
        read -rp "Enter the raw sequence directory: " RAW_DIR

        # Check if the provided directory exists
        if [[ ! -d "$RAW_DIR" ]]; then
            echo "Error: Provided directory '$RAW_DIR' does not exist."
            exit 1
        fi
    fi

    # Check if the raw directory contains valid input files
    if [[ -z "$(ls -A "$RAW_DIR"/*_R1_*.fastq.gz 2>/dev/null)" ]]; then
        echo "Error: No valid R1 files found in '$RAW_DIR'. Please ensure naming conventions are of the standard pattern *_R1_*.fastq.gz."
        exit 1
    fi

    # Check if the trimmer script exists and is executable
    check_script "./trimmer.sh"

    # Run the trimmer.sh script with the detected or provided raw directory
    echo "Running trimming stage..."
    # Use bash to execute the script and capture exit status
    bash "./trimmer.sh" "$RAW_DIR"
    if [[ $? -ne 0 ]]; then
        echo "Error: Trimming stage failed. Check the log file for details."
        exit 1
    fi
}

# Function to run host_remover.sh
run_host_remover() {
    # Check if the host_remover script exists and is executable
    check_script "./host_remover.sh"

    echo "Running host removal stage..."
    bash "./host_remover.sh"
    if [[ $? -ne 0 ]]; then
        echo "Error: Host removal stage failed. Check the log file for details."
        exit 1
    fi
}

# Function to run taxonomic_profiler.sh
run_taxonomic_profiler() {
    if [[ "$SKIP_TAXONOMIC_PROFILER" = true ]]; then
        echo "Skipping taxonomic profiling stage..."
        return
    fi

    # Check if the taxonomic_profiler script exists and is executable
    check_script "./taxonomic_profiler.sh"

    echo "Running taxonomic profiling stage..."
    bash "./taxonomic_profiler.sh"
    if [[ $? -ne 0 ]]; then
        echo "Error: Taxonomic profiling stage failed. Check the log file for details."
        exit 1
    fi
}

# Function to run functional_profiler.sh
run_functional_profiler() {
    if [[ "$SKIP_FUNCTIONAL_PROFILER" = true ]]; then
        echo "Skipping functional profiling stage..."
        return
    fi

    # Check if the functional_profiler script exists and is executable
    check_script "./functional_profiler.sh"

    echo "Running functional profiling stage..."
    bash "./functional_profiler.sh"
    if [[ $? -ne 0 ]]; then
        echo "Error: Functional profiling stage failed. Check the log file for details."
        exit 1
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip)
            if [[ -z "$2" ]]; then
                echo "Error: --skip requires a comma-separated list of stages (e.g., taxonomic_profiler,functional_profiler)"
                exit 1
            fi
            parse_skip "$2"
            shift 2
            ;;
        --help)
            display_help
            return 0 2>/dev/null || true
            ;;
        *)
            echo "Error: Invalid argument: '$1'. Use --help for usage information."
            exit 1
            ;;
    esac
done

# Start pipeline
echo "MGPipe started."

# Deactivate current conda environment if active and set up mgpipe environment
deactivate_conda_env
setup_conda_env

# Execute pipeline steps in order
run_trimmer
run_host_remover
run_taxonomic_profiler
run_functional_profiler

echo "MGPipe completed successfully."