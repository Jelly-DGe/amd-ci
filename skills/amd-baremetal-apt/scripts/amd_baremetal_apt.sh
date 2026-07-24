#!/usr/bin/env bash
# Interactive, confirmation-gated installer for the validated AMD Ubuntu APT baseline.
set -euo pipefail

DRIVER_VERSION="6.16.13.30300300-2327507.22.04"
FIRMWARE_VERSION="30.30.3.0.30300300-2327507.22.04"
TARGET_APT_VERSION="1:${DRIVER_VERSION}"
CHECK_ONLY=false
WITH_ROCM=false

usage() {
  cat <<'EOF'
Usage: amd_baremetal_apt.sh [--check-only] [--with-rocm]

Prompt for target IP/hostname, SSH account, and password. Check first, then
ask before purging, installing, or rebooting. --with-rocm offers ROCm 7.2.3.
EOF
}

while (($#)); do
  case "$1" in
    --check-only) CHECK_ONLY=true ;;
    --with-rocm) WITH_ROCM=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

confirm() {
  local answer
  read -r -p "$1 [y/N]: " answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

read -r -p "Target IP or hostname: " TARGET_HOST
read -r -p "SSH username: " TARGET_USER
read -r -s -p "SSH password: " SSH_PASSWORD
printf '\n'

if [[ ! "$TARGET_HOST" =~ ^[A-Za-z0-9._-]+$ ]] || [[ ! "$TARGET_USER" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Invalid host or username." >&2
  exit 2
fi

ASKPASS_FILE=$(mktemp)
cleanup() { rm -f "$ASKPASS_FILE"; unset SSH_PASSWORD; }
trap cleanup EXIT
cat > "$ASKPASS_FILE" <<'EOF'
#!/bin/sh
printf '%s\n' "$AMD_BAREMETAL_SSH_PASSWORD"
EOF
chmod 700 "$ASKPASS_FILE"
export AMD_BAREMETAL_SSH_PASSWORD="$SSH_PASSWORD"
export SSH_ASKPASS="$ASKPASS_FILE"
export SSH_ASKPASS_REQUIRE=force
export DISPLAY="amd-baremetal:0"

ssh_base() {
  ssh -o BatchMode=no -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 \
    "$TARGET_USER@$TARGET_HOST" "$@"
}

remote() { ssh_base "$1"; }

remote_root() {
  local encoded
  encoded=$(printf '%s' "$1" | base64 | tr -d '\n')
  { printf '%s\n' "$SSH_PASSWORD"; printf '%s' "$encoded"; } |
    ssh_base "sudo -S -p '' bash -c 'base64 -d | bash'"
}

echo "== Hardware and driver check =="
PRECHECK=$(remote 'bash -s' <<'REMOTE'
set -e
echo "HOSTNAME=$(hostname)"
echo "OS=$(. /etc/os-release; printf '%s' "$PRETTY_NAME")"
echo "KERNEL=$(uname -r)"
echo "GPU_LIST_BEGIN"
lspci -Dnn | awk '/(VGA compatible controller|3D controller|Display controller|Processing accelerators).*\[1002:/{print}'
echo "GPU_LIST_END"
echo "GPU_COUNT=$(lspci -Dnn | awk '/(VGA compatible controller|3D controller|Display controller|Processing accelerators).*\[1002:/{n++} END{print n+0}')"
echo "LOADED_AMDGPU=$(test -d /sys/module/amdgpu && echo yes || echo no)"
echo "MODULE_PATH=$(modinfo -n amdgpu 2>/dev/null || true)"
echo "MODULE_VERSION=$(modinfo -F version amdgpu 2>/dev/null || true)"
echo "APT_DRIVER_VERSION=$(dpkg-query -W -f='${Version}' amdgpu-dkms 2>/dev/null || true)"
echo "DKMS_STATUS_BEGIN"
dkms status 2>/dev/null | grep amdgpu || true
echo "DKMS_STATUS_END"
echo "BLACKLIST_BEGIN"
grep -RniE '(^|[^[:alnum:]_])(blacklist|install)[[:space:]]+amdgpu' /etc/modprobe.d /usr/lib/modprobe.d 2>/dev/null || true
echo "BLACKLIST_END"
REMOTE
)
printf '%s\n' "$PRECHECK"

GPU_COUNT=$(awk -F= '/^GPU_COUNT=/{print $2}' <<<"$PRECHECK")
if [[ "$GPU_COUNT" == "0" ]]; then
  echo "No AMD GPU/accelerator PCI devices found. Stop here." >&2
  exit 1
fi

INSTALLED_DRIVER=$(awk -F= '/^APT_DRIVER_VERSION=/{print $2}' <<<"$PRECHECK")
echo "Target driver package: $TARGET_APT_VERSION"
echo "Detected driver package: ${INSTALLED_DRIVER:-not installed}"

if $CHECK_ONLY; then
  echo "Check-only mode complete."
  exit 0
fi

if [[ -n "$INSTALLED_DRIVER" && "$INSTALLED_DRIVER" != "$TARGET_APT_VERSION" ]]; then
  echo "A different APT AMDGPU driver is installed."
  if ! confirm "Purge the detected APT AMDGPU driver before installing the target version?"; then
    echo "No changes made."
    exit 0
  fi
  remote_root 'export DEBIAN_FRONTEND=noninteractive; apt-get purge -y amdgpu-dkms amdgpu-dkms-firmware'
elif [[ -z "$INSTALLED_DRIVER" ]]; then
  echo "No APT AMDGPU driver package is installed."
else
  echo "The target APT AMDGPU package is already installed."
fi

if ! confirm "Configure AMD repositories and install/repair AMDGPU DKMS $DRIVER_VERSION?"; then
  echo "Driver installation skipped."
  exit 0
fi

remote_root "set -euo pipefail
install -d -m 0755 /etc/apt/keyrings /etc/apt/preferences.d
wget -qO- https://repo.radeon.com/rocm/rocm.gpg.key | gpg --dearmor --yes -o /etc/apt/keyrings/rocm.gpg
printf '%s\\n' 'deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/amdgpu/30.30.3/ubuntu jammy main' > /etc/apt/sources.list.d/amdgpu.list
printf '%s\\n' 'deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.2.3 jammy main' 'deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/7.2.3/ubuntu jammy main' > /etc/apt/sources.list.d/rocm.list
printf '%s\\n' 'Package: *' 'Pin: release o=repo.radeon.com' 'Pin-Priority: 600' > /etc/apt/preferences.d/rocm-pin-600
export DEBIAN_FRONTEND=noninteractive
apt-get update
rm -f /var/crash/amdgpu-dkms.0.crash
apt-get install -y \"linux-headers-\$(uname -r)\" gcc-12 amdgpu-dkms=$TARGET_APT_VERSION amdgpu-dkms-firmware=$FIRMWARE_VERSION
"

if $WITH_ROCM && confirm "Install ROCm 7.2.3 from APT?"; then
  remote_root 'export DEBIAN_FRONTEND=noninteractive; apt-get install -y rocm'
fi

echo "== Post-install validation =="
remote 'bash -s' <<'REMOTE'
set -e
echo "KERNEL=$(uname -r)"
dkms status | grep amdgpu || true
modinfo amdgpu 2>/dev/null | grep -E '^(filename|version|vermagic):' || true
grep -RniE '(^|[^[:alnum:]_])(blacklist|install)[[:space:]]+amdgpu' /etc/modprobe.d /usr/lib/modprobe.d 2>/dev/null || true
REMOTE

if confirm "Reboot the target now to load the new AMDGPU driver?"; then
  remote_root 'reboot'
  echo "Reboot requested. Reconnect after the host is available and run: amd-smi"
else
  echo "Reboot is required before relying on the new kernel driver."
fi
