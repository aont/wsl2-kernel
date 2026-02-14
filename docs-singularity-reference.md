# Singularity / Apptainer Reference Notes

This file contains Singularity/Apptainer-specific supplemental notes extracted from `README.md`.
For the core WSL2 kernel workflow, see the main README.

## Prerequisites

- `singularity` / `apptainer` is available on your Linux environment.
- Standard kernel build tools are installed inside the container (gcc, make, libssl-dev, libelf-dev, ncurses-dev, bc, etc.).

## Example definition file

```text
Bootstrap: docker
From: ubuntu:24.04

%post
    apt-get update
    apt-get install -y build-essential flex bison libssl-dev libelf-dev libncurses-dev bc python3 dwarves cpio
    apt-get clean

%runscript
    exec /bin/bash
```

## Build and enter the container

```bash
singularity build --fakeroot ubuntu2404.sif ubuntu2404.def
singularity shell ubuntu2404.sif
```

`--fakeroot` allows non-root users to perform root-like operations during builds when supported by host features.

## Notes

- Singularity can build images from a definition file.
- Docker can also provide a similar build environment, but Singularity is often preferred in HPC / multi-user environments.

## Reference link

- Singularity / Apptainer definition files and `--fakeroot` build docs. ([Sylabs][1])

[1]: https://docs.sylabs.io/guides/4.1/user-guide/build_a_container.html "Build a Container — SingularityCE User Guide 4.1 ..."
