# Installing SLAM-seq scripts on Alliance Canada

### Steps

1. [Installing of the scripts](#Installing-of-the-scripts)
    1. [Change directory to `project` folder](#Change-directory-to-project-folder)
    2. [Clone repository](#Clone-repository)
2. [Updating scripts](#Updating-scripts)
3. [Install dependencies](#Install-dependencies)
   1. [Install SlamDunk and UCSC utilities](#Install SlamDunk and UCSC utilities)

## Installing of the scripts

### Change directory to project folder

```shell
cd /project/def-bmartin/scripts
```

### Clone repository

```shell
git clone https://github.com/BenMartinLab/slamseq.git
```

## Updating scripts

Go to the slamseq scripts folder and run `git pull`.

```shell
cd /project/def-bmartin/scripts/slamseq
git pull
```

## Install dependencies

Move to slamseq scripts directory.

```shell
cd /project/def-bmartin/scripts/slamseq
```

### UCSC utilities

```shell
wget -O bedGraphToBigWig https://hgdownload.soe.ucsc.edu/admin/exe/linux.x86_64.v479/bedGraphToBigWig
chmod 755 bedGraphToBigWig
wget -O bigWigMerge https://hgdownload.soe.ucsc.edu/admin/exe/linux.x86_64.v479/bigWigMerge
chmod 755 bigWigMerge
wget -O bigWigToBedGraph https://hgdownload.soe.ucsc.edu/admin/exe/linux.x86_64.v479/bigWigToBedGraph
chmod 755 bigWigToBedGraph
```

### Install SlamDunk

```shell
wget -O slamdunk.sif https://g-88ccb6.6d81c.5898.data.globus.org/slamdunk/slamdunk-0.4.3-14270e5.sif
```
