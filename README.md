# WSL2 kernel — build with my favorite configuration

A short, practical guide for building a WSL2 kernel (using a Singularity/Apptainer container) and configuring Windows to use it. This follows the workflow you provided: grab the running kernel config, download Microsoft’s WSL2 kernel source, customize `.config`, build inside a container, and point WSL to your `bzImage`.

---

## Why this works (brief)

* Microsoft publishes the WSL2 kernel source on GitHub, so you can download and build the exact kernel used by WSL. ([GitHub][1])
* A running Linux kernel often exposes its compiled configuration at `/proc/config.gz`, so extracting that gives you a good starting `.config`. ([Super User][2])
* Building inside an isolated container (Singularity/Apptainer) keeps the host clean; Singularity supports `--fakeroot` builds which let you perform root-like operations when the host supports the required features. ([Sylabs][3])
* To make WSL use your custom kernel, configure the `kernel` path in `%UserProfile%\.wslconfig`. `.wslconfig` is the supported global WSL2 configuration file. ([Microsoft Learn][4])
* The `user@host` string shown in `uname -v` / `/proc/version` is controlled by `KBUILD_BUILD_USER` and `KBUILD_BUILD_HOST` during the kernel build; exporting them changes what’s embedded in the resulting kernel. ([Kernel Document][5])

---

## Minimal prerequisites

* Windows with WSL2 enabled and working.
* `singularity` / `apptainer` installed on the Linux machine that will run the build (or build on a Linux VM). (Singularity docs for definition files / `--fakeroot` are helpful). ([Sylabs][3])
* Standard kernel build tools (gcc, make, libssl-dev, libelf-dev, ncurses-dev, bc, etc.) inside the build container.
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

3. **Build image/prepare container (example Singularity def):**

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

Build and enter:

```bash
singularity build --fakeroot ubuntu2404.sif ubuntu2404.def
singularity shell ubuntu2404.sif
```

Singularity `--fakeroot` allows non-root users to run builds that require root-like operations (subject to host support). ([Sylabs][3])

4. **Prepare the kernel tree and `.config`:**

```bash
cd WSL2-Linux-Kernel-linux-msft-wsl-${KERNELVERSION}
cp config.txt .config          # use running config as baseline
# or: cp Microsoft/config-wsl .config
# append your custom options
echo '
CONFIG_XFS_FS=y
CONFIG_F2FS_FS=y
CONFIG_BLK_DEV_NBD=y
CONFIG_BCACHE=y
CONFIG_ANDROID=y
CONFIG_ANDROID_BINDER_IPC=y
CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"
' >> .config
# Keep the existing .config while filling in any new Kconfig options introduced in the tree with their default values, without requiring user interaction.
make olddefconfig
```

5. **Branding / build identity (optional):**

```bash
export KBUILD_BUILD_USER="aont"
export KBUILD_BUILD_HOST="aont"
```

Setting those overrides what the kernel embeds for the build-user and -host. ([Kernel Document][5])

6. **Build:**

```bash
make -j$(nproc)
# artifacts: arch/x86/boot/bzImage (for WSL use)
file arch/x86/boot/bzImage
```

After a successful build you’ll see `bzImage` and other artifacts; the version string will include `KBUILD_BUILD_USER@KBUILD_BUILD_HOST` if set.

7. **Place the kernel and configure Windows:**

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
* **Singularity vs Docker:** You used Singularity which is fine — it can build images from definition files and supports `--fakeroot`. If you prefer Docker, a similar approach (container with build tools) will also work, but Singularity often fits HPC / multi-user systems better. ([Sylabs][3])
* **Spaces in `.wslconfig` paths:** `.wslconfig` parsing can be picky about escaping; prefer paths without spaces or use exact documented formatting if necessary. (Windows `%UserProfile%\.wslconfig` is the right file.) ([Microsoft Learn][4])
* **Reproducibility:** If you need reproducible or machine-independent builds, set `KBUILD_BUILD_USER`, `KBUILD_BUILD_HOST`, and consider `-fdebug-prefix-map` / other kbuild flags as documented. ([Kernel Document][6])

---

## Useful references

* Microsoft WSL2 kernel repo (source & tags). ([GitHub][1])
* How to obtain kernel config from a running kernel (`/proc/config.gz`). ([Super User][2])
* Microsoft / community guides on building WSL custom kernels. ([Microsoft Learn][7])
* Singularity / Apptainer definition files and `--fakeroot` build docs. ([Sylabs][3])
* kbuild docs: `KBUILD_BUILD_USER` and `KBUILD_BUILD_HOST`. ([Kernel Document][5])

[1]: https://github.com/microsoft/WSL2-Linux-Kernel "microsoft/WSL2-Linux-Kernel: The source for ..."
[2]: https://superuser.com/questions/287371/how-to-obtain-kernel-config-from-currently-running-linux-system "How to obtain kernel config from currently running Linux ..."
[3]: https://docs.sylabs.io/guides/4.1/user-guide/build_a_container.html "Build a Container — SingularityCE User Guide 4.1 ..."
[4]: https://learn.microsoft.com/en-us/windows/wsl/wsl-config "Advanced settings configuration in WSL"
[5]: https://docs.kernel.org/kbuild/kbuild.html "Kbuild"
[6]: https://docs.kernel.org/kbuild/reproducible-builds.html "Reproducible builds"
[7]: https://learn.microsoft.com/en-us/community/content/wsl-user-msft-kernel-v6 "How to use the Microsoft Linux kernel v6 on WSL2"
