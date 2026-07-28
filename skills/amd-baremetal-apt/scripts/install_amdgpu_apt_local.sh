#!/usr/bin/env bash
# Install the validated AMDGPU APT baseline on the local Ubuntu 22.04 host.
set -euo pipefail

DRIVER_VERSION="6.16.13.30300300-2327507.22.04"
FIRMWARE_VERSION="30.30.3.0.30300300-2327507.22.04"
DRIVER_APT_VERSION="1:${DRIVER_VERSION}"
WITH_ROCM=false
ASSUME_YES=false
REPLACE_DRIVER=false

usage() {
  cat <<EOF
Usage: sudo $0 [--with-rocm] [--yes] [--replace-driver]

Install AMDGPU ${DRIVER_VERSION} from AMD's Ubuntu 22.04 APT repository.

Options:
  --with-rocm       Install ROCm 7.2.3 and rocminfo after the driver.
  --yes             Do not prompt for confirmation.
  --replace-driver  Purge an existing, different APT amdgpu-dkms version first.
  -h, --help        Show this help text.

Batch deployment on a fresh Ubuntu 22.04 bare-metal host:
  sudo bash $0 --with-rocm --yes
EOF
}

while (($#)); do
  case "$1" in
    --with-rocm) WITH_ROCM=true ;;
    --yes) ASSUME_YES=true ;;
    --replace-driver) REPLACE_DRIVER=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if ((EUID != 0)); then
  echo "Run this script as root, for example: sudo bash $0 --with-rocm --yes" >&2
  exit 1
fi

if [[ ! -r /etc/os-release ]]; then
  echo "Cannot identify the operating system." >&2
  exit 1
fi
. /etc/os-release
if [[ "$ID" != "ubuntu" || "$VERSION_ID" != "22.04" ]]; then
  echo "This baseline supports Ubuntu 22.04 only. Detected: ${PRETTY_NAME}" >&2
  exit 1
fi

GPU_COUNT=$(lspci -Dnn | awk '/(VGA compatible controller|3D controller|Display controller|Processing accelerators).*\[1002:/{n++} END{print n+0}')
if [[ "$GPU_COUNT" == "0" ]]; then
  echo "No AMD GPU or accelerator PCIe devices were found. Stop." >&2
  exit 1
fi

KERNEL=$(uname -r)
INSTALLED_DRIVER=$(dpkg-query -W -f='${Version}' amdgpu-dkms 2>/dev/null || true)

echo "Host: $(hostname)"
echo "OS: ${PRETTY_NAME}"
echo "Kernel: ${KERNEL}"
echo "AMD PCIe GPU count: ${GPU_COUNT}"
echo "Target amdgpu-dkms: ${DRIVER_APT_VERSION}"
echo "Installed amdgpu-dkms: ${INSTALLED_DRIVER:-not installed}"

if [[ -n "$INSTALLED_DRIVER" && "$INSTALLED_DRIVER" != "$DRIVER_APT_VERSION" ]]; then
  if ! $REPLACE_DRIVER; then
    echo "A different AMDGPU APT package is installed. Refusing to replace it automatically." >&2
    echo "Review the host and rerun with --replace-driver only when replacement is intended." >&2
    exit 1
  fi
  if ! $ASSUME_YES; then
    read -r -p "Purge ${INSTALLED_DRIVER} and replace it with ${DRIVER_APT_VERSION}? [y/N]: " answer
    [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]] || { echo "No changes made."; exit 0; }
  fi
  export DEBIAN_FRONTEND=noninteractive
  apt-get purge -y amdgpu-dkms amdgpu-dkms-firmware
fi

if ! $ASSUME_YES; then
  read -r -p "Install or repair AMDGPU ${DRIVER_APT_VERSION} on this host? [y/N]: " answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]] || { echo "No changes made."; exit 0; }
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y wget gpg
install -d -m 0755 /etc/apt/keyrings /etc/apt/preferences.d
wget -qO- https://repo.radeon.com/rocm/rocm.gpg.key | gpg --dearmor --yes -o /etc/apt/keyrings/rocm.gpg

cat > /etc/apt/sources.list.d/amdgpu.list <<'EOF'
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/amdgpu/30.30.3/ubuntu jammy main
EOF
cat > /etc/apt/sources.list.d/rocm.list <<'EOF'
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.2.3 jammy main
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/7.2.3/ubuntu jammy main
EOF
cat > /etc/apt/preferences.d/rocm-pin-600 <<'EOF'
Package: *
Pin: release o=repo.radeon.com
Pin-Priority: 600
EOF

apt-get update
rm -f /var/crash/amdgpu-dkms.0.crash
apt-get install -y "linux-headers-${KERNEL}" gcc-12 \
  "amdgpu-dkms=${DRIVER_APT_VERSION}" \
  "amdgpu-dkms-firmware=${FIRMWARE_VERSION}"

if $WITH_ROCM; then
  apt-get install -y rocm rocminfo
fi

echo
echo "== Installation complete: reboot required =="
dkms status | grep amdgpu || true
modinfo amdgpu 2>/dev/null | grep -E '^(filename|version|vermagic):' || true
echo "Reboot the host, then verify with: amd-smi"
