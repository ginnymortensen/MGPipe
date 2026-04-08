# MGPipe: _MetaGenomics Pipeline_

This shotgun metagenomics pipeline processes raw short read paired-end reads into usable microbiome data, suitable for postprocessing. The pipeline performs quality control of sequences, host genome sequence removal, taxonomic profiling, and functional profiling. This pipeline is meant to provide beginners with a seamless tool to achieve basic microbiome analyses.

All downstream scripts used to created the figures in our paper are located in `analysis`.

**Please cite: [Metagenomic profiling and predictive modeling of the gut microbiome reveal signatures of gestational disease](https://doi.org/10.1128/spectrum.03155-25)**

## Table of Contents
- [Installation](#installation)
- [Usage](#usage)
- [Documentation](#documentation)

## Installation:

To use MGPipe, you need to have conda installed, MGPipe cloned locally, Kraken2/Bracken databases downloaded, and HUMAnN3 installed. <br><br>

### Prerequisites:
- Unix-based system (Linux/macOS)
- Minimum 16GB RAM (32GB recommended)
- 100GB+ free disk space

### Install conda:
```bash
mkdir -p ./bin
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ./bin/miniconda.sh
bash ./bin/miniconda.sh -b -p ./bin/miniconda3
```
**Important:** Update `CONDAPATH` in `mgpipe.sh` to match your installation path, _especially_ if you have conda installed already:
```bash
CONDAPATH="./bin/miniconda3"  # Modify this path if needed
```
### Clone MGPipe locally:
```bash
git clone https://github.com/ginnymortensen/MGPipe.git
```
### Download Kraken2 database:
Kraken2/Bracken updates its standard reference database. <br>
To download the most recent database, please reference https://benlangmead.github.io/aws-indexes/k2. <br>
```bash
cd MGPipe
curl --header 'Host: genome-idx.s3.amazonaws.com' --header 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36' --header 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7' --header 'Accept-Language: en-US,en;q=0.9' --header 'Referer: https://benlangmead.github.io/' 'https://genome-idx.s3.amazonaws.com/kraken/k2_standard_20240605.tar.gz' -L -o 'k2_standard_20240605.tar.gz'
tar -xzvf k2_standard_20240605.tar.gz
```
**Notice:** Update `KRAKEN2_DB` in `taxonomic_profiler.sh` to match your installation path if you already have the Kraken2 database installed:
```bash
KRAKEN2_DB="k2_standard_20240605"  # Modify this path if needed
```
### Install HUMAnN3:
HUMAnN is updated every so often. <br>
Reference https://github.com/biobakery/humann for installation instructions. <br>
```bash
curl --header 'Host: files.pythonhosted.org' --header 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36' --header 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7' --header 'Accept-Language: en-US,en;q=0.9' --header 'Referer: https://pypi.org/' 'https://files.pythonhosted.org/packages/b2/8f/0d908a2a43f89f03e4d1f22baf80b77a4bce342b721552737173c4da74cd/humann-3.9.tar.gz' -L -o 'humann-3.9.tar.gz'
```
Follow the installation instructions for HUMAnN after download is complete. The databases for HUMAnN are installed via:<br>
```bash
cd MGPipe
humann_databases --download chocophlan full humann_databases
humann_databases --download uniref uniref90_diamond humann_databases
```
**Notice** Update `DB_DIR` in `functional_profiler.sh` to match your HUMAnN3 database installation path if you already have them installed:
``` bash
DB_DIR="humann_databases"  # Modify this path if needed
```

### *(Optional)* Install Bowtie2 Indexes:
MGPipe will automatically install bowtie2 indexes from ftp://ftp.ccb.jhu.edu/pub/data/bowtie_indexes/grch38_1kgmaj.fa.gz if it does not find them in the default directory during its initial execution. This step takes a significant amount of time to run.<br><br>
If you already have bowtie2 indexes installed, update `DB_DIR` and `INDEX_NAME` in `host_remover.sh` to match your bowtie2 indexes installation path and index name.

```bash
DB_PATH="bowtie_indexes"    # Modify this path if needed
INDEX_NAME="grch38_1kgmaj"  # Modify this index name if needed
```

## Usage:

### Input
- Create a directory called `raw` at the same directory tree level as `MGPipe`
```bash
mkdir raw
```
- Ensure sequences are in `fastq.gz` format
- Place paired-end FASTQs in `raw/` with standard short read naming convention: `*_R1_001.fastq.gz` and `*_R2_001.fastq.gz`

### Directory Structure
Your directory should have this structure prior to your initial run: <br>
```bash
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
    ├── sample1_R1_001.fastq.gz
    ├── sample1_R2_001.fastq.gz
    └── ...
```
<br>

### Running MGPipe

``` bash
cd MGPipe
. mgpipe.sh
```
If you'd like to skip taxonomic profiling and/or functional profiling steps:
```bash
. mgpipe.sh --skip taxonomic_profiler,functional_profiler
```
### Output Structure
When running natively, your output directory will have this structure:

``` bash
.
├── MGPipe
│   ├── bowtie_indexes
│   ├── humann_databases
│   │   ├── chocophlan
│   │   └── uniref
│   └── k2_standard_20240605
├── raw
├── reports
│   ├── sample1
│   └── ...
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
```

## Documentation

### Help Documentation
``` bash
. mgpipe.sh --help
```

### Pipeline Architecture
| Script | Purpose | Key Tools | Tool Documentation |
|--------|---------|-----------|--------------------|
| `trimmer.sh` | Quality control & adapter trimming | [FASTP](https://github.com/OpenGene/fastp) | [FASTP Manual](https://github.com/OpenGene/fastp#readme) |
| `host_remover.sh` | Host DNA removal | [bowtie2](http://bowtie-bio.sourceforge.net/bowtie2/index.shtml) | [bowtie2 Manual](http://bowtie-bio.sourceforge.net/bowtie2/manual.shtml) |
| `taxonomic_profiler.sh` | Species-level profiling | [Kraken2](https://ccb.jhu.edu/software/kraken2/)<br>[Bracken](https://ccb.jhu.edu/software/bracken/) | [Kraken2 Wiki](https://github.com/DerrickWood/kraken2/wiki)<br>[Bracken Paper](https://peerj.com/articles/cs-104/) |
| `functional_profiler.sh` | Metabolic pathway analysis | [HUMAnN3](https://github.com/biobakery/humann) | [HUMAnN3 Docs](https://github.com/biobakery/humann#documentation) |

### Integrated Tools Reference
#### Quality Control
- **FASTP**  
  Official documentation: https://github.com/OpenGene/fastp

#### Host DNA Removal
- **bowtie2**  
  User manual: http://bowtie-bio.sourceforge.net/bowtie2/manual.shtml  
  Index building command used:
  ```bash
  bowtie2-build --threads $THREADS $REF_FASTA $INDEX_NAME
  ```

#### Taxonomic Profiling
- **Kraken2**  
  Configuration guide: https://github.com/DerrickWood/kraken2/blob/master/docs/MANUAL.markdown  
  Database requirements:
  ```bash
  KRAKEN2_DB="path/to/standard_db"
  kraken2 --db $KRAKEN2_DB --threads $THREADS --paired $INPUT_FILES
  ```

- **Bracken**  
  Abundance estimation methodology:  
  https://ccb.jhu.edu/software/bracken/

#### Functional Profiling
- **HUMAnN3**  
  Full documentation: https://github.com/biobakery/humann#humann-30  
  Critical database files:
  ```bash
  # ChocoPhlAn database
  humann_databases --download chocophlan full humann_databases
  
  # UniRef90 database
  humann_databases --download uniref uniref90_diamond humann_databases
  ```
