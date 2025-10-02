# wsl2-kernel

WSL2 kernel with my favorite configuration.

## build with singularity container

```bash
export LANG=C

# Check your current wsl2 kernel release. 
KERNELVERSION=$(uname -r | sed -e 's/-.*$//g')
echo "$KERNELVERSION"
# For example, it's `6.6.87.2` here.

# the configuration of stock kernel.
gzip -d -c /proc/config.gz > config.txt

# Download kernel source
curl -LO "https://github.com/microsoft/WSL2-Linux-Kernel/archive/refs/tags/linux-msft-wsl-${KERNELVERSION}.tar.gz"

# extract
tar xzf "linux-msft-wsl-${KERNELVERSION}.tar.gz"
# or
pv "linux-msft-wsl-${KERNELVERSION}.tar.gz" | tar xzf -

# build singularity image for bulding
echo 'Bootstrap: docker
From: ubuntu:24.04

%post
    apt-get update
    apt -y install build-essential flex bison libssl-dev libelf-dev libncurses-dev bc python3 dwarves cpio
    apt-get clean

%runscript
    exec /bin/bash
' > ubuntu2404.def
singularity build --fakeroot ubuntu2404.sif ubuntu2404.def

# open singularity shell
singularity shell ubuntu2404.sif

# configuration
cd WSL2-Linux-Kernel-linux-msft-wsl-6.6.87.2

cp config.txt .config
# or
 cp Microsoft/config-wsl .config

# customize
echo '
# Customization
CONFIG_XFS_FS=y
CONFIG_F2FS_FS=y
CONFIG_BLK_DEV_NBD=y
CONFIG_BCACHE=y
CONFIG_ANDROID=y
CONFIG_ANDROID_BINDER_IPC=y
CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"
' >> .config

make menuconfig
# then `Exit`

# branding
export KBUILD_BUILD_USER="aont"
export KBUILD_BUILD_HOST="aont"

# build
make -kj $(nproc)
# wait for a long time ...

# voila!
file arch/x86_64/boot/bzImage
# bzImage: Linux kernel x86 boot executable, bzImage, version 6.6.87.2-microsoft-standard-WSL2 (aont@aont) #1 SMP PREEMPT_DYNAMIC Thu Oct  2 21:51:48 JST 2025, RO-rootFS, Normal VGA, setup size 512*31, syssize 0xfcd00, jump 0x26c 0x8cd88ec0fc8cd239 instruction, protocol 2.15, from protected-mode code at offset 0x2cc 0xfb4a76 bytes gzip compressed, relocatable, handover offset 0xfc0854, legacy 64-bit entry point, can be above 4G, 64-bit EFI handoff entry point, EFI kexec boot support, xloadflags bit 5, max cmdline size 2047, init_size 0x3be7000
```

## `.wslconfig`

```
[wsl2]
kernel=C:\\Users\\aont\\wsl\\bzImage
# debugConsole=true
```
