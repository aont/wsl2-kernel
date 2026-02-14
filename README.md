# WSL2 kernel — build with my favorite configuration

A short, practical guide for building a WSL2 kernel and configuring Windows to use it. This follows the workflow you provided: grab the running kernel config, download Microsoft’s WSL2 kernel source, customize `.config`, build, and point WSL to your `bzImage`.

---

## Why this works (brief)

* Microsoft publishes the WSL2 kernel source on GitHub, so you can download and build the exact kernel used by WSL. ([GitHub][1])
* A running Linux kernel often exposes its compiled configuration at `/proc/config.gz`, so extracting that gives you a good starting `.config`. ([Super User][2])
* To make WSL use your custom kernel, configure the `kernel` path in `%UserProfile%\.wslconfig`. `.wslconfig` is the supported global WSL2 configuration file. ([Microsoft Learn][4])
* The `user@host` string shown in `uname -v` / `/proc/version` is controlled by `KBUILD_BUILD_USER` and `KBUILD_BUILD_HOST` during the kernel build; exporting them changes what’s embedded in the resulting kernel. ([Kernel Document][5])

---

## Minimal prerequisites

* Windows with WSL2 enabled and working.
* Optional: a container runtime if you want an isolated build environment (details moved to `docs-singularity-reference.md`).
* Standard kernel build tools (gcc, make, libssl-dev, libelf-dev, ncurses-dev, bc, etc.) in your build environment.
* Enough CPU, RAM, and disk space for a kernel build.

---

## Quick recipe (condensed, matches your snippet)

1. **Grab the running kernel version and config on the machine you’ll base `.config` on:**

```bash
export LANG=C
KERNELVERSION=$(uname -r | sed -e 's/-.*$//g')
echo "$KERNELVERSION"
gzip -d -c /proc/config.gz > config.txt   # extract running config
```

<!-- (If `/proc/config.gz` isn’t present, use `scripts/extract-ikconfig` on a kernel image — many kernels embed the config.) ([Super User][2]) -->

2. **Download Microsoft’s WSL2 kernel source tarball for that version:**

```bash
curl -LO "https://github.com/microsoft/WSL2-Linux-Kernel/archive/refs/tags/linux-msft-wsl-${KERNELVERSION}.tar.gz"
tar xzf "linux-msft-wsl-${KERNELVERSION}.tar.gz"
```

<!-- (Or `git clone` the repo and checkout the matching tag.) ([GitHub][1]) -->

3. **Prepare build environment and run the automation script:**

Use a Linux environment that has the required build tools installed.

For Ubuntu/Debian, for example:

```bash
sudo apt-get install -y bc bison build-essential cpio dwarves flex libelf-dev libncurses-dev libssl-dev qemu-utils xz-utils
```

If you want to use Singularity/Apptainer, see `docs-singularity-reference.md`.

Run the automation script for kernel tree preparation and build steps:

```bash
./scripts/build-wsl2-kernel.sh -k "${KERNELVERSION}"
```

Optional branding values can still be set before execution:

```bash
export KBUILD_BUILD_USER="aont"
export KBUILD_BUILD_HOST="aont"
./scripts/build-wsl2-kernel.sh -k "${KERNELVERSION}"
```

The script expects `config.txt` and `WSL2-Linux-Kernel-linux-msft-wsl-${KERNELVERSION}` to exist in the working directory. It sets requested features as modules where possible and builds both `bzImage` and kernel modules.

4. **Place the kernel and configure Windows:**

* Copy `arch/x86/boot/bzImage` somewhere on Windows, e.g. `C:\Users\aont\wsl\bzImage`.
* Create or edit `%UserProfile%\.wslconfig` with:

```ini
[wsl2]
kernel=C:\\Users\\aont\\wsl\\bzImage
# debugConsole=true
```

Restart WSL (`wsl --shutdown`) and start your distro. `.wslconfig` is the correct global WSL config file to point WSL2 at a custom kernel. ([Microsoft Learn][4])

---

## Short notes & tips

* **Matching versions:** Build the source that matches the running WSL kernel version (or a close tag) if you want minimal surprises; Microsoft’s WSL kernel repo is the authoritative source. ([GitHub][1])
* **Config extraction:** `/proc/config.gz` is the easiest way to get a baseline `.config`; if it doesn’t exist, try `scripts/extract-ikconfig` against the kernel image. ([Super User][2])
* **Spaces in `.wslconfig` paths:** `.wslconfig` parsing can be picky about escaping; prefer paths without spaces or use exact documented formatting if necessary. (Windows `%UserProfile%\.wslconfig` is the right file.) ([Microsoft Learn][4])
* **Reproducibility:** If you need reproducible or machine-independent builds, set `KBUILD_BUILD_USER`, `KBUILD_BUILD_HOST`, and consider `-fdebug-prefix-map` / other kbuild flags as documented. ([Kernel Document][6])

---

## GitHub Actions workflow (YAML description)

This repository includes `.github/workflows/build-and-release.yml`, which builds a WSL2 kernel and publishes release assets automatically.

```yaml
name: Build and Release WSL2 Kernel

on:
  workflow_dispatch:
    inputs:
      kernel_tag:
        description: "WSL2 kernel tag from microsoft/WSL2-Linux-Kernel"
        required: true
        default: linux-msft-wsl-6.6.114.1
      release_tag:
        description: "Optional release tag in this repository (defaults to {commit date}-{commit id}-{kernel_tag})"
        required: false
  push:
    tags:
      - "linux-msft-wsl-*"

permissions:
  contents: write

jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
      - name: Resolve tags
        run: |
          # derive kernel_version and release_tag (default: {commit date}-{commit id}-{kernel_tag})
      - name: Install build dependencies
        run: |
          # apt-get install toolchain + kernel build deps
      - name: Download WSL2 kernel source
        run: |
          # fetch https://github.com/microsoft/WSL2-Linux-Kernel tag tarball
      - name: Prepare base config
        run: |
          # copy Microsoft/config-wsl (or arch/x86/configs/config-wsl) to config.txt
      - name: Build kernel and modules
        run: |
          ./scripts/build-wsl2-kernel.sh -k "${KERNEL_VERSION}"
      - name: Collect artifacts
        run: |
          # outputs: bzImage-<kernelrelease>, modules-<kernelrelease>.vhdx, SHA256SUMS
      - uses: actions/upload-artifact@v4
      - uses: softprops/action-gh-release@v2
```

In short: trigger manually (or by pushing a `linux-msft-wsl-*` tag), build kernel + modules from the selected Microsoft tag, upload CI artifacts, and create/update a GitHub Release containing `bzImage`, modules VHDX, and checksums.

---

## Useful references

* Microsoft WSL2 kernel repo (source & tags). ([GitHub][1])
* How to obtain kernel config from a running kernel (`/proc/config.gz`). ([Super User][2])
* Microsoft / community guides on building WSL custom kernels. ([Microsoft Learn][7])
* Singularity / Apptainer notes are moved to `docs-singularity-reference.md`.
* kbuild docs: `KBUILD_BUILD_USER` and `KBUILD_BUILD_HOST`. ([Kernel Document][5])

[1]: https://github.com/microsoft/WSL2-Linux-Kernel "microsoft/WSL2-Linux-Kernel: The source for ..."
[2]: https://superuser.com/questions/287371/how-to-obtain-kernel-config-from-currently-running-linux-system "How to obtain kernel config from currently running Linux ..."
[4]: https://learn.microsoft.com/en-us/windows/wsl/wsl-config "Advanced settings configuration in WSL"
[5]: https://docs.kernel.org/kbuild/kbuild.html "Kbuild"
[6]: https://docs.kernel.org/kbuild/reproducible-builds.html "Reproducible builds"
[7]: https://learn.microsoft.com/en-us/community/content/wsl-user-msft-kernel-v6 "How to use the Microsoft Linux kernel v6 on WSL2"
