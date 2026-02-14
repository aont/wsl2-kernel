#!/usr/bin/env bash
set -euxo pipefail

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

config_args=(--file .config)

add_enable_config() {
  local symbol="$1"

  config_args+=(--enable "$symbol")
}

add_module_config() {
  local symbol="$1"

  config_args+=(--module "$symbol")
}

add_module_config CONFIG_XFS_FS
add_module_config CONFIG_F2FS_FS
add_module_config CONFIG_BLK_DEV_NBD
add_module_config CONFIG_BCACHE
add_enable_config CONFIG_ANDROID
add_module_config CONFIG_ANDROID_BINDER_IPC
config_args+=(--set-str CONFIG_ANDROID_BINDER_DEVICES "binder,hwbinder,vndbinder")
add_module_config CONFIG_ANDROID_BINDERFS
add_enable_config CONFIG_NETFILTER
add_enable_config CONFIG_NETFILTER_ADVANCED
add_module_config CONFIG_IP_NF_IPTABLES
add_module_config CONFIG_IP_NF_FILTER
add_module_config CONFIG_IP_NF_MANGLE
add_module_config CONFIG_IP_NF_RAW
add_module_config CONFIG_IP_NF_TARGET_REJECT
add_module_config CONFIG_IP_NF_TARGET_LOG
add_module_config CONFIG_IP_NF_TARGET_MASQUERADE
add_module_config CONFIG_IP_NF_TARGET_REDIRECT
add_module_config CONFIG_IP_NF_MATCH_ADDRTYPE
add_module_config CONFIG_IP_NF_MATCH_IPRANGE
add_module_config CONFIG_IP_NF_MATCH_MAC
add_module_config CONFIG_IP_NF_MATCH_MULTIPORT
add_module_config CONFIG_IP_NF_MATCH_TTL
add_module_config CONFIG_NF_NAT
add_module_config CONFIG_NF_TABLES
add_module_config CONFIG_NF_NAT_IPV4
add_module_config CONFIG_NF_CONNTRACK_IPV4
add_module_config CONFIG_IP_NF_NAT
add_module_config CONFIG_NETFILTER_XT_TARGET_CHECKSUM
add_module_config CONFIG_NETFILTER_XTABLES
add_module_config CONFIG_NETFILTER_XT_MATCH_ADDRTYPE
add_module_config CONFIG_NETFILTER_XT_TARGET_REDIRECT
add_module_config CONFIG_NETFILTER_XT_TARGET_NETMAP
add_module_config CONFIG_NETFILTER_XT_MATCH_CONNTRACK
add_module_config CONFIG_BRIDGE
add_module_config CONFIG_BRIDGE_NETFILTER
add_enable_config CONFIG_STAGING
add_module_config CONFIG_NFT_CHAIN_NAT
add_module_config CONFIG_NFT_COMPAT
add_module_config CONFIG_NFT_REDIR
add_module_config CONFIG_NFT_CT
add_enable_config CONFIG_MODULE_COMPRESS
add_enable_config CONFIG_MODULE_COMPRESS_XZ

./scripts/config "${config_args[@]}"

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

# gen_modules_vhdx.sh uses losetup and requires elevated privileges on
# GitHub-hosted runners.
if command -v sudo >/dev/null 2>&1; then
  sudo "$VHDX_SCRIPT_PATH" "$MODULES_STAGE_DIR" "$KERNEL_RELEASE" "$MODULES_VHDX_PATH"
  sudo chown "$(id -u):$(id -g)" "$MODULES_VHDX_PATH"
else
  "$VHDX_SCRIPT_PATH" "$MODULES_STAGE_DIR" "$KERNEL_RELEASE" "$MODULES_VHDX_PATH"
fi

echo
echo "Done. Kernel image: ${SOURCE_DIR}/arch/x86/boot/bzImage"
echo "Done. Kernel modules are built in: ${SOURCE_DIR}"
echo "Done. Kernel modules VHDX: ${MODULES_VHDX_PATH}"
