# DDN Lustre Client Runbook

## Target assumptions

- Client OS: Ubuntu with kernel `6.8.0-124-generic`.
- Client Lustre build: DDN `2.14.0-ddn154`.
- MGS/NIDs: `169.254.5.200@o2ib,169.254.6.200@o2ib`.
- Mount source for this deployment: `169.254.5.200@o2ib,169.254.6.200@o2ib:/fs00/amd`.
- Mount point: `/ddn`.
- Lustre traffic must use the 200G IPoIB interfaces with `169.254.5.x/24` and `169.254.6.x/24`, not the 400G `192.168.10.x` Ethernet interfaces.

## Pre-check commands

```bash
uname -r
dpkg -l | grep -E 'lustre|linux-headers|module-assistant|ofed|mlnx' || true
ip -br addr
ibstat
ibv_devinfo
lsmod | grep -E 'lustre|lnet|ko2iblnd|ksocklnd|libcfs|ib_core|mlx5_ib' || true
grep -nE 'lustre|ddn|fs00|169.254' /etc/fstab || true
```

Confirm the 200G IPoIB interfaces before writing LNet config. Interface names can differ by host, for example `ibs109,ibs113` on one server but other names on another server.

Use correct `ip` syntax:

```bash
ip -br addr show dev ibs109
ip -br addr show dev ibs113
```

Do not use `ip -br addr show ibs109 ibs113`; `ip` treats the second name as invalid syntax.

## Install package set

The package directory must contain:

```text
lustre-client-utils_2.14.0-ddn154-1_amd64.deb
lustre-client-modules-6.8.0-124-generic_2.14.0-ddn154-1_amd64.deb
lustre-dev_2.14.0-ddn154-1_amd64.deb
```

Install manually:

```bash
cd /home/amd/debs
sudo dpkg -i \
  ./lustre-client-utils_2.14.0-ddn154-1_amd64.deb \
  ./lustre-client-modules-6.8.0-124-generic_2.14.0-ddn154-1_amd64.deb \
  ./lustre-dev_2.14.0-ddn154-1_amd64.deb
```

If dependencies are missing and the server has APT access, run:

```bash
sudo apt-get -f install
```

## LNet configuration

Write the confirmed IPoIB interfaces:

```bash
sudo tee /etc/modprobe.d/lnet.conf >/dev/null <<'EOF'
options lnet networks="o2ib(ibs109,ibs113)"
EOF
```

This file only affects `lnet` when the module is first loaded. If `lnet` is already loaded with wrong networks, either unload cleanly or reboot.

Clean unload is safe only when no Lustre filesystem is mounted and no stale MGC/OSC/MDC devices are active:

```bash
mount | grep lustre || true
sudo lctl dl 2>/dev/null || true
sudo /usr/sbin/lustre_rmmod
```

If `lustre_rmmod` reports `Module lustre is in use`, do not force it on a production host. Reboot during a maintenance window.

## Validate LNet

```bash
sudo modprobe ko2iblnd
sudo lctl list_nids
sudo lnetctl net show
sudo lnetctl ping 169.254.5.200@o2ib
sudo lnetctl ping 169.254.6.200@o2ib
```

Expected NID shape:

```text
169.254.5.xxx@o2ib
169.254.6.xxx@o2ib
```

If the output shows `192.168.10.x@tcp`, LNet picked the wrong network. Remove any automatic TCP config, write the static `lnet.conf`, and reload/reboot.

If `lctl list_nids` reports `IOC_LIBCFS_GET_NI error 100: Network is down`, `lnet` is loaded without active networks. This usually means `ko2iblnd` or `lnet` was loaded before the correct `/etc/modprobe.d/lnet.conf` took effect.

## fstab and mount

Create mount point and append fstab:

```bash
sudo mkdir -p /ddn
echo '169.254.5.200@o2ib,169.254.6.200@o2ib:/fs00/amd /ddn lustre defaults 0 0' | sudo tee -a /etc/fstab
```

Mount and verify:

```bash
sudo mount -v -a
mount | grep -E 'lustre|/ddn'
df -hT /ddn
sudo lctl dl | head -80
```

`mount -v -a` will print `/ddn : ignored` if the fstab line contains `noauto`.

## Common failures

- `modinfo ko2iblnd` not found: the module deb is not installed for the running kernel, or `depmod -a` has not run.
- `modprobe ko2iblnd` unknown symbols: OFED/RDMA modules and the Lustre module were built against different RDMA headers. Rebuild the module deb against the same OFED stack.
- LNet ping succeeds but mount hangs: collect `dmesg`, `lctl dl`, and `lnetctl net show`. The issue is beyond basic LNet and may involve MGS config, returned MDT/OST NIDs, or server-side reachability.
- `169.524...` ping fails: this is a typo. The correct link-local prefix is `169.254`.
