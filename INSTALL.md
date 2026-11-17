# Installing SLAM-seq scripts on Alliance Canada

### Steps

1. [Installing of the scripts](#Installing-of-the-scripts)
    1. [Change directory to `project` folder](#Change-directory-to-project-folder)
    2. [Clone repository](#Clone-repository)
2. [Updating scripts](#Updating-scripts)
3. [Install dependencies](#Install-dependencies)
    1. [SlamDunk](#slamdunk)
    2. [Python environment](#python-environment)

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

### SlamDunk

```shell
wget -O slamdunk.sif https://g-88ccb6.6d81c.5898.data.globus.org/slamdunk/slamdunk-0.4.3-14270e5.sif
```

### Python environment

```shell
./create-env.sh
```
