# MGPipe
## _MetaGenomics Pipeline_

This shotgun metagenomics pipeline processes raw short read paired-end reads into usable microbiome data, suitable for postprocessing. The pipeline performs quality control of sequences (trimming via FASTP and host removal via bowtie2), taxonomic profiling (via Kraken2 and Bracken), and functional profiling (via HUMAnN3).

### Set-Up Instructions:

To use MGPipe, you need to have conda installed, MGPipe cloned locally, Kraken2/Bracken databases downloaded, and HUMAnN3 installed. 

#### 1) Install conda:
If you already have conda installed, change the `CONDAPATH` variable in `mgpipe.sh` to point to the path of your conda installation. This will allow you to run MGPipe in non-interactive shells.<br>
`mkdir ./bin` <br>
`wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ./bin/miniconda.sh` <br>
When prompted, enter: <br>
`./bin/miniconda3` as your installation path and say yes to everything when prompted.<br>
Change the `CONDAPATH` variable in `mgpipe.sh` to point to your conda installation.

#### 2) Clone MGPipe locally:
Ensure you have a folder named `MGPipe` in your working environment with all mgpipe related scripts in it.

#### 3) Download Kraken2/Bracken databases:
Kraken2/Bracken updates its standard reference database. <br>
To download the most recent database, please reference https://benlangmead.github.io/aws-indexes/k2. <br>
This command was run to download the most recent database: <br>
`curl --header 'Host: genome-idx.s3.amazonaws.com' --header 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36' --header 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7' --header 'Accept-Language: en-US,en;q=0.9' --header 'Referer: https://benlangmead.github.io/' 'https://genome-idx.s3.amazonaws.com/kraken/k2_standard_20240605.tar.gz' -L -o 'k2_standard_20240605.tar.gz'` <br>
To unzip the file, run: <br>
`tar -xzvf k2_standard_20240605.tar.gz` <br>
Move this database folder into the `MGPipe` folder. The location of this database is referenceable by `taxonomic_profiler.sh` in the `KRAKEN2_DB` variable.

#### 4) Install HUMAnN3:
HUMAnN is updated every so often. <br>
Reference https://github.com/biobakery/humann for installation. <br>
Download the latest tarball via: <br>
`curl --header 'Host: files.pythonhosted.org' --header 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36' --header 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7' --header 'Accept-Language: en-US,en;q=0.9' --header 'Referer: https://pypi.org/' 'https://files.pythonhosted.org/packages/b2/8f/0d908a2a43f89f03e4d1f22baf80b77a4bce342b721552737173c4da74cd/humann-3.9.tar.gz' -L -o 'humann-3.9.tar.gz'` <br>
Follow the installation instructions for HUMAnN after download is complete. <br>
The databases for HUMAnN are installed via `humann_databases --download chocophlan full $INSTALL_LOCATION` as described in the installation instructions for HUMAnN. <br>
The `$INSTALL LOCATION` should be set to `MGPipe/humann_databases`. The location of this database is referenceable by `functional_profiler.sh` in the `DB_DIR` variable.

### Utilization Instructions:

#### 1) Directory Structure and Input
Your directory should be arranged such that paired-end, short read sequences are placed in a directory called `raw` at the same level as the `MGPipe` directory.<br>
Your sequences should be in `fastq.gz` format and follow conventional nomenclature for paired-end sequences, for example, Illumina reads follow the standard naming convention `<sample_name>_R1_001.fastq.gz`. <br>
Your directory should have this structure prior to your initial run: <br>
.
├── MGPipe
│   ├── humann_databases/
│   │   ├── chocophlan/
│   │   └── uniref/
│   ├── k2_standard_20240605/
│   ├── functional_profiler.sh
│   ├── host_remover.sh
│   ├── mgpipe_env.yaml
│   ├── mgpipe.sh
│   ├── README.md
│   ├── taxonomic_profiler.sh
│   └── trimmer.sh
└── raw/
<br>

#### Running the pipeline
Navigate to MGPipe `cd MGPipe` <br>
Source the wrapper script `. mgpipe.sh` <br>
MGPipe will run and log all errors. MGPipe checks to see if bowtie2 indexes are installed, if they are not, MGPipe automatically downloads the GRCh38 human reference genome FASTA and builds these indexes within the MGPipe directory. This step will take a significant amount of time to run. <br>
If you already have bowtie2 indexes available, simply change the path and index name accordingly in the `host_remover.sh` script via the `DB_DIR` and `INDEX_NAME` variables such that it points to your indexes.
<br>
After your initial run, your directory structure will look like this, where sample-specific directory names will follow fastq.gz filename patterning (e.g. samplename1, samplename2, etc.): <br>
.
├── MGPipe
│   ├── bowtie_indexes
│   ├── humann_databases
│   │   ├── chocophlan
│   │   └── uniref
│   └── k2_standard_20240605
├── raw
├── reports
│   ├── samplename1
│   └── samplename2
└── results
    ├── functional_profile
    │   ├── combined_tables
    │   ├── renormalized_tables
    │   ├── restratified_tables
    │   └── sample_tables
    ├── no_host
    ├── taxonomic_profile
    │   ├── combined_tables
    │   ├── kraken2_bracken_output
    │   └── sample_tables
    └── trimmed
<br>
