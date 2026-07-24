#!/usr/bin/env bash
set -euo pipefail

DEB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../assets/debs" 2>/dev/null && pwd || true)"
INTERFACES=""
MOUNTPOINT="/ddn"
SOURCE="169.254.5.200@o2ib,169.254.6.200@o2ib:/fs00/amd"
WRITE_FSTAB=1
DO_MOUNT=1
ALLOW_RELOAD=0

usage() {
  cat <<'EOF'
Usage:
  sudo bash install_ddn_lustre_client.sh --deb-dir /home/amd/debs --interfaces ibs109,ibs113 [options]

Required:
  --interfaces IFACE1,IFACE2   Confirmed 200G IPoIB interfaces for Lustre.

Options:
  --deb-dir DIR                Directory containing DDN Lustre .deb packages.
  --mountpoint PATH            Mount point. Default: /ddn
  --source SOURCE              Lustre source. Default:
                               169.254.5.200@o2ib,169.254.6.200@o2ib:/fs00/amd
  --no-fstab                   Do not write /etc/fstab.
  --no-mount                   Do not mount after install.
  --allow-reload               Try lustre_rmmod if LNet/Lustre modules are already loaded.
  -h, --help                   Show this help.

This script installs DDN Lustre 2.14.0-ddn154 client debs, writes
/etc/modprobe.d/lnet.conf, verifies o2ib NIDs, and optionally mounts the FS.
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

info() {
  echo "[INFO] $*"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --deb-dir)
      DEB_DIR="$2"
      shift 2
      ;;
    --interfaces)
      INTERFACES="$2"
      shift 2
      ;;
    --mountpoint)
      MOUNTPOINT="$2"
      shift 2
      ;;
    --source)
      SOURCE="$2"
      shift 2
      ;;
    --no-fstab)
      WRITE_FSTAB=0
      shift
      ;;
    --no-mount)
      DO_MOUNT=0
      shift
      ;;
    --allow-reload)
      ALLOW_RELOAD=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ "$(id -u)" -eq 0 ]] || die "Run as root: sudo bash $0 ..."
[[ -n "$INTERFACES" ]] || die "--interfaces is required. Confirm the IB names first, for example ibs109,ibs113."
[[ -d "$DEB_DIR" ]] || die "Deb directory not found: $DEB_DIR"

KERNEL="$(uname -r)"
MODULE_DEB="$DEB_DIR/lustre-client-modules-${KERNEL}_2.14.0-ddn154-1_amd64.deb"
UTILS_DEB="$DEB_DIR/lustre-client-utils_2.14.0-ddn154-1_amd64.deb"
DEV_DEB="$DEB_DIR/lustre-dev_2.14.0-ddn154-1_amd64.deb"

[[ -f "$UTILS_DEB" ]] || die "Missing $UTILS_DEB"
[[ -f "$DEV_DEB" ]] || die "Missing $DEV_DEB"
[[ -f "$MODULE_DEB" ]] || die "Missing $MODULE_DEB. The module package must match the running kernel: $KERNEL"

info "Checking IPoIB interfaces: $INTERFACES"
IFS=',' read -r -a IFACES <<< "$INTERFACES"
for iface in "${IFACES[@]}"; do
  [[ -d "/sys/class/net/$iface" ]] || die "Interface not found: $iface"
  ip -br addr show dev "$iface" || true
done

info "Installing DDN Lustre packages for kernel $KERNEL"
dpkg -i "$UTILS_DEB" "$MODULE_DEB" "$DEV_DEB"
depmod -a

info "Writing /etc/modprobe.d/lnet.conf"
cat >/etc/modprobe.d/lnet.conf <<EOF
options lnet networks="o2ib(${INTERFACES})"
EOF
cat /etc/modprobe.d/lnet.conf

if mount | grep -q ' type lustre '; then
  echo
  echo "A Lustre filesystem is already mounted. Not reloading modules."
  echo "The new lnet.conf will apply after reboot or a safe maintenance-window unload."
  exit 20
fi

if lsmod | grep -qE '^(lustre|lnet|ko2iblnd|ksocklnd|libcfs) '; then
  if [[ "$ALLOW_RELOAD" -eq 1 ]]; then
    info "Lustre/LNet modules are loaded; trying a clean unload because --allow-reload was set"
    /usr/sbin/lustre_rmmod || die "Could not unload modules cleanly. Reboot before verification."
  else
    echo
    echo "Lustre/LNet modules are already loaded."
    echo "Reboot is recommended so /etc/modprobe.d/lnet.conf is applied from a clean state."
    echo "To try a clean unload instead, rerun with --allow-reload when no Lustre mount is active."
    exit 21
  fi
fi

info "Loading ko2iblnd"
modprobe ko2iblnd

info "Checking LNet NIDs"
lctl --version
lctl list_nids
lnetctl net show

if ! lctl list_nids | grep -qE '^169\.254\.(5|6)\.[0-9]+@o2ib$'; then
  echo
  echo "WARNING: Expected 169.254.5.x@o2ib and/or 169.254.6.x@o2ib NIDs were not detected."
  echo "Check interface address ordering and make sure $INTERFACES are the correct 200G IPoIB links."
fi

info "Testing MGS LNet reachability"
lnetctl ping 169.254.5.200@o2ib
lnetctl ping 169.254.6.200@o2ib

mkdir -p "$MOUNTPOINT"

if [[ "$WRITE_FSTAB" -eq 1 ]]; then
  FSTAB_LINE="$SOURCE $MOUNTPOINT lustre defaults 0 0"
  info "Writing /etc/fstab entry if missing"
  cp -a /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d%H%M%S)"
  grep -F "$SOURCE $MOUNTPOINT lustre" /etc/fstab >/dev/null || echo "$FSTAB_LINE" >> /etc/fstab
  grep -nE 'lustre|ddn|fs00|169.254' /etc/fstab || true
fi

if [[ "$DO_MOUNT" -eq 1 ]]; then
  info "Mounting $SOURCE at $MOUNTPOINT"
  mount -v "$MOUNTPOINT"
  mount | grep -E "lustre|$MOUNTPOINT" || true
  df -hT "$MOUNTPOINT"
fi

info "Done"
