#!/usr/bin/env bash
set -euo pipefail

# Run this script *inside* the Singularity/Apptainer container.
# Expected layout in the current directory:
# - config.txt
# - WSL2-Linux-Kernel-linux-msft-wsl-<version>/

usage() {
  cat <<'USAGE'
Usage:
  build-wsl2-kernel.sh [-k <kernel_version>] [-w <workdir>]

Options:
  -k <kernel_version>  Kernel version suffix used in source directory name.
                       Default: uname -r stripped after the first '-'.
  -w <workdir>         Directory containing config.txt and source tree.
                       Default: current directory.

Outputs:
  - arch/x86/boot/bzImage
  - modules-<kernelrelease>.vhdx (generated via Microsoft/scripts/gen_modules_vhdx.sh)

Environment variables:
  KBUILD_BUILD_USER    Optional build user branding.
  KBUILD_BUILD_HOST    Optional build host branding.
USAGE
}

KERNEL_VERSION="$(uname -r | sed -e 's/-.*$//g')"
WORKDIR="$(pwd)"

while getopts ":k:w:h" opt; do
  case "$opt" in
    k) KERNEL_VERSION="$OPTARG" ;;
    w) WORKDIR="$OPTARG" ;;
    h)
      usage
      exit 0
      ;;
    :) echo "Error: option -$OPTARG requires an argument" >&2; usage; exit 1 ;;
    \?) echo "Error: invalid option -$OPTARG" >&2; usage; exit 1 ;;
  esac
done

SOURCE_DIR="${WORKDIR}/WSL2-Linux-Kernel-linux-msft-wsl-${KERNEL_VERSION}"
BASE_CONFIG="${WORKDIR}/config.txt"

if [[ ! -f "$BASE_CONFIG" ]]; then
  echo "Error: config file not found: $BASE_CONFIG" >&2
  exit 1
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Error: source directory not found: $SOURCE_DIR" >&2
  exit 1
fi

cd "$SOURCE_DIR"
cp "$BASE_CONFIG" .config

set_module_or_enable() {
  local symbol="$1"

  if ./scripts/config --file .config --module "$symbol" >/dev/null 2>&1; then
    echo "set $symbol=m"
  else
    ./scripts/config --file .config --enable "$symbol"
    echo "set $symbol=y"
  fi
}

set_module_or_enable CONFIG_XFS_FS
set_module_or_enable CONFIG_F2FS_FS
set_module_or_enable CONFIG_BLK_DEV_NBD
set_module_or_enable CONFIG_BCACHE
set_module_or_enable CONFIG_ANDROID
set_module_or_enable CONFIG_ANDROID_BINDER_IPC
./scripts/config --file .config --set-str CONFIG_ANDROID_BINDER_DEVICES "binder,hwbinder,vndbinder"
set_module_or_enable CONFIG_ANDROID_BINDERFS
set_module_or_enable CONFIG_NETFILTER
set_module_or_enable CONFIG_NETFILTER_ADVANCED
set_module_or_enable CONFIG_IP_NF_IPTABLES
set_module_or_enable CONFIG_IP_NF_FILTER
set_module_or_enable CONFIG_IP_NF_MANGLE
set_module_or_enable CONFIG_IP_NF_RAW
set_module_or_enable CONFIG_IP_NF_TARGET_REJECT
set_module_or_enable CONFIG_IP_NF_TARGET_LOG
set_module_or_enable CONFIG_IP_NF_TARGET_MASQUERADE
set_module_or_enable CONFIG_IP_NF_TARGET_REDIRECT
set_module_or_enable CONFIG_IP_NF_MATCH_ADDRTYPE
set_module_or_enable CONFIG_IP_NF_MATCH_IPRANGE
set_module_or_enable CONFIG_IP_NF_MATCH_MAC
set_module_or_enable CONFIG_IP_NF_MATCH_MULTIPORT
set_module_or_enable CONFIG_IP_NF_MATCH_TTL
set_module_or_enable CONFIG_NF_NAT
set_module_or_enable CONFIG_NF_TABLES
set_module_or_enable CONFIG_NF_NAT_IPV4
set_module_or_enable CONFIG_NF_CONNTRACK_IPV4
set_module_or_enable CONFIG_IP_NF_NAT
set_module_or_enable CONFIG_NETFILTER_XT_TARGET_CHECKSUM
set_module_or_enable CONFIG_NETFILTER_XTABLES
set_module_or_enable CONFIG_NETFILTER_XT_MATCH_ADDRTYPE
set_module_or_enable CONFIG_NETFILTER_XT_TARGET_REDIRECT
set_module_or_enable CONFIG_NETFILTER_XT_TARGET_NETMAP
set_module_or_enable CONFIG_NETFILTER_XT_MATCH_CONNTRACK
set_module_or_enable CONFIG_BRIDGE
set_module_or_enable CONFIG_BRIDGE_NETFILTER
set_module_or_enable CONFIG_STAGING
set_module_or_enable CONFIG_NFT_CHAIN_NAT
set_module_or_enable CONFIG_NFT_COMPAT
set_module_or_enable CONFIG_NFT_REDIR
set_module_or_enable CONFIG_NFT_CT

make olddefconfig

echo "KBUILD_BUILD_USER=${KBUILD_BUILD_USER:-<not set>}"
echo "KBUILD_BUILD_HOST=${KBUILD_BUILD_HOST:-<not set>}"

make -j"$(nproc)" bzImage modules
file arch/x86/boot/bzImage

KERNEL_RELEASE="$(make -s kernelrelease)"
MODULES_STAGE_DIR="$(mktemp -d)"
MODULES_VHDX_PATH="${SOURCE_DIR}/modules-${KERNEL_RELEASE}.vhdx"
VHDX_SCRIPT_PATH="${SOURCE_DIR}/Microsoft/scripts/gen_modules_vhdx.sh"

trap 'rm -rf "${MODULES_STAGE_DIR}"' EXIT

if [[ ! -x "$VHDX_SCRIPT_PATH" ]]; then
  echo "Error: Microsoft modules VHDX script not found or not executable: $VHDX_SCRIPT_PATH" >&2
  exit 1
fi

make INSTALL_MOD_PATH="$MODULES_STAGE_DIR" modules_install
"$VHDX_SCRIPT_PATH" "$MODULES_STAGE_DIR" "$KERNEL_RELEASE" "$MODULES_VHDX_PATH"

echo
echo "Done. Kernel image: ${SOURCE_DIR}/arch/x86/boot/bzImage"
echo "Done. Kernel modules are built in: ${SOURCE_DIR}"
echo "Done. Kernel modules VHDX: ${MODULES_VHDX_PATH}"
