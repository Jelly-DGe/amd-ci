#!/usr/bin/env bash
set -u

section() {
  printf '\n==== %s ====\n' "$1"
}

run() {
  printf '+ %s\n' "$*"
  "$@" 2>&1 || true
}

section "Host"
run hostname
run date
run uname -a

section "Packages"
dpkg -l 2>/dev/null | grep -E 'lustre|linux-headers|module-assistant|ofed|mlnx|rdma' || true

section "Network"
run ip -br addr
run ip route

section "InfiniBand"
command -v ibstat >/dev/null 2>&1 && run ibstat || echo "ibstat not found"
command -v ibv_devinfo >/dev/null 2>&1 && run ibv_devinfo || echo "ibv_devinfo not found"

section "Kernel modules"
lsmod | grep -E 'lustre|lnet|ko2iblnd|ksocklnd|libcfs|ib_core|mlx5_ib|rdma_cm' || true
run modinfo ko2iblnd

section "LNet"
command -v lctl >/dev/null 2>&1 && run lctl --version || echo "lctl not found"
command -v lctl >/dev/null 2>&1 && run sudo lctl list_nids || true
command -v lnetctl >/dev/null 2>&1 && run sudo lnetctl net show || true

section "Mount configuration"
run grep -nE 'lustre|ddn|fs00|169.254' /etc/fstab
mount | grep -E 'lustre|/ddn' || true

section "Recent kernel log"
sudo dmesg -T 2>/dev/null | grep -Ei 'lustre|lnet|o2ib|ko2ib|MGC|MDS|MDT|OST|rdma|mlx|timeout|error' | tail -160 || true
