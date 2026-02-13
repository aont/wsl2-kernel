#!/usr/bin/env bash
set -euo pipefail

# Run this script *inside* the Singularity/Apptainer container.
# Expected layout in the current directory:
# - config.txt
# - WSL2-Linux-Kernel-linux-msft-wsl-<version>/

usage() {
  cat <<'USAGE'
Usage:
  build-wsl2-kernel-in-singularity.sh [-k <kernel_version>|latest-tag-date] [-w <workdir>]

Options:
  -k <kernel_version>  Kernel version suffix used in source directory name.
                       Default: uname -r stripped after the first '-'.
                       Special value: latest-tag-date (resolve newest upstream
                       linux-msft-wsl-* tag by tag date).
  -w <workdir>         Directory containing config.txt and source tree.
                       Default: current directory.

Environment variables:
  KBUILD_BUILD_USER    Optional build user branding.
  KBUILD_BUILD_HOST    Optional build host branding.
USAGE
}

resolve_latest_tag_by_date() {
  local workdir="$1"
  local repo_url="https://github.com/microsoft/WSL2-Linux-Kernel.git"
  local repo_dir
  local candidate

  for candidate in \
    "$workdir/WSL2-Linux-Kernel" \
    "$workdir/WSL2-Linux-Kernel.git" \
    "$workdir/.wsl2-kernel-tags-repo"; do
    if [[ -d "$candidate/.git" ]]; then
      repo_dir="$candidate"
      break
    fi
  done

  if [[ -z "${repo_dir:-}" ]]; then
    repo_dir="$workdir/.wsl2-kernel-tags-repo"
    mkdir -p "$repo_dir"
    git -C "$repo_dir" init -q
    if ! git -C "$repo_dir" remote get-url origin >/dev/null 2>&1; then
      git -C "$repo_dir" remote add origin "$repo_url"
    fi
  fi

  git -C "$repo_dir" fetch -q --tags origin

  git -C "$repo_dir" for-each-ref \
    --sort=-creatordate \
    --format='%(refname:strip=2)' \
    'refs/tags/linux-msft-wsl-*' \
    | sed -E 's/^linux-msft-wsl-//' \
    | head -n 1
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

if [[ "$KERNEL_VERSION" == "latest-tag-date" ]]; then
  KERNEL_VERSION="$(resolve_latest_tag_by_date "$WORKDIR")"
  if [[ -z "$KERNEL_VERSION" ]]; then
    echo "Error: failed to resolve latest linux-msft-wsl-* tag by date." >&2
    exit 1
  fi
  echo "Resolved latest kernel version by tag date: ${KERNEL_VERSION}"
fi

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

echo "Converting all module (=m) configs to built-in (=y) in .config ..."
mapfile -t MODULE_SYMBOLS < <(awk -F= '/^CONFIG_[A-Za-z0-9_]+=m$/ {print $1}' .config)

if [[ "${#MODULE_SYMBOLS[@]}" -gt 0 ]]; then
  MODULE_ENABLE_ARGS=()
  for sym in "${MODULE_SYMBOLS[@]}"; do
    MODULE_ENABLE_ARGS+=(--enable "$sym")
  done
  ./scripts/config --file .config "${MODULE_ENABLE_ARGS[@]}"
  echo "Converted ${#MODULE_SYMBOLS[@]} config symbols from module to built-in."
else
  echo "No module config symbols found in baseline .config."
fi

./scripts/config --file .config \
  --enable CONFIG_XFS_FS \
  --enable CONFIG_F2FS_FS \
  --enable CONFIG_BLK_DEV_NBD \
  --enable CONFIG_BCACHE \
  --enable CONFIG_ANDROID \
  --enable CONFIG_ANDROID_BINDER_IPC \
  --set-str CONFIG_ANDROID_BINDER_DEVICES "binder,hwbinder,vndbinder" \
  --enable CONFIG_ANDROID_BINDERFS \
  --enable CONFIG_NETFILTER \
  --enable CONFIG_NETFILTER_ADVANCED \
  --enable CONFIG_IP_NF_IPTABLES \
  --enable CONFIG_IP_NF_FILTER \
  --enable CONFIG_IP_NF_MANGLE \
  --enable CONFIG_IP_NF_RAW \
  --enable CONFIG_IP_NF_TARGET_REJECT \
  --enable CONFIG_IP_NF_TARGET_LOG \
  --enable CONFIG_IP_NF_TARGET_MASQUERADE \
  --enable CONFIG_IP_NF_TARGET_REDIRECT \
  --enable CONFIG_IP_NF_MATCH_ADDRTYPE \
  --enable CONFIG_IP_NF_MATCH_IPRANGE \
  --enable CONFIG_IP_NF_MATCH_MAC \
  --enable CONFIG_IP_NF_MATCH_MULTIPORT \
  --enable CONFIG_IP_NF_MATCH_TTL \
  --enable CONFIG_NF_NAT \
  --enable CONFIG_NF_TABLES \
  --enable CONFIG_NF_NAT_IPV4 \
  --enable CONFIG_NF_CONNTRACK_IPV4 \
  --enable CONFIG_IP_NF_NAT \
  --enable CONFIG_NETFILTER_XT_TARGET_CHECKSUM \
  --enable CONFIG_NETFILTER_XTABLES \
  --enable CONFIG_NETFILTER_XT_MATCH_ADDRTYPE \
  --enable CONFIG_NETFILTER_XT_TARGET_REDIRECT \
  --enable CONFIG_NETFILTER_XT_TARGET_NETMAP \
  --enable CONFIG_NETFILTER_XT_MATCH_CONNTRACK \
  --enable CONFIG_BRIDGE \
  --enable CONFIG_BRIDGE_NETFILTER \
  --enable CONFIG_STAGING \
  --enable CONFIG_NFT_CHAIN_NAT \
  --enable CONFIG_NFT_COMPAT \
  --enable CONFIG_NFT_REDIR \
  --enable CONFIG_NFT_CT

make olddefconfig

echo "KBUILD_BUILD_USER=${KBUILD_BUILD_USER:-<not set>}"
echo "KBUILD_BUILD_HOST=${KBUILD_BUILD_HOST:-<not set>}"

make -j"$(nproc)"
file arch/x86/boot/bzImage

echo
echo "Done. Kernel image: ${SOURCE_DIR}/arch/x86/boot/bzImage"
