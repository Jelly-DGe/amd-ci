---
name: ddn-lustre-client
description: Install and validate DDN/EXAScaler Lustre client packages on Ubuntu servers using prebuilt debs, configure LNet o2ib over IPoIB interfaces, write fstab entries, mount DDN Lustre filesystems, and troubleshoot cases such as missing ko2iblnd, wrong IB interface names, Network is down, stale LNet state, or incorrect 169.254 o2ib NIDs. Use when the user says DDN, EXAScaler, Lustre client, lnetctl, ko2iblnd, o2ib, /home/amd/debs, 2.14.0-ddn154, or asks to install the compiled DDN driver on another server.
---

# DDN Lustre Client

Use this skill to help install the compiled DDN/EXAScaler Lustre client packages on another Ubuntu server and verify that the client mounts the filesystem through the 200G IPoIB links.

The expected package set is DDN Lustre `2.14.0-ddn154` for kernel `6.8.0-124-generic`:

- `lustre-client-utils_2.14.0-ddn154-1_amd64.deb`
- `lustre-client-modules-6.8.0-124-generic_2.14.0-ddn154-1_amd64.deb`
- `lustre-dev_2.14.0-ddn154-1_amd64.deb`

Place those files in `assets/debs/` when bundling the skill, or copy them to the target server and pass `--deb-dir`.

## Workflow

1. Inspect the target server before changing it:
   - Check kernel: `uname -r` must match the module deb suffix.
   - Check existing packages: `dpkg -l | grep -E 'lustre|lnet|ddn'`.
   - Check IPoIB links and addresses: `ip -br addr`, `ibstat`, `ibv_devinfo`.
   - Confirm which IB interfaces are the 200G Lustre links. Do not assume `ibs109,ibs113`; ask the user to confirm when names differ.
2. Install packages with `scripts/install_ddn_lustre_client.sh`.
3. Configure `/etc/modprobe.d/lnet.conf` with the confirmed IPoIB interfaces:
   `options lnet networks="o2ib(<iface1>,<iface2>)"`
4. Verify that LNet NIDs use the `169.254.5.x@o2ib` and `169.254.6.x@o2ib` format.
5. Add an `/etc/fstab` entry and mount:
   `169.254.5.200@o2ib,169.254.6.200@o2ib:/fs00/amd /ddn lustre defaults 0 0`
6. If LNet was already loaded with wrong networks, prefer a reboot after writing `lnet.conf`. A reload is acceptable only when no Lustre mount or kernel module reference is active.

## Scripts

- Use `scripts/ddn_lustre_check.sh` for read-only discovery and validation.
- Use `scripts/install_ddn_lustre_client.sh` for package install, LNet config, optional fstab write, and mount verification.
- Use `scripts/package_skill.ps1` on Windows to copy debs into `assets/debs/` and create a zip bundle.

Example:

```bash
sudo bash scripts/ddn_lustre_check.sh

sudo bash scripts/install_ddn_lustre_client.sh \
  --deb-dir /home/amd/debs \
  --interfaces ibs109,ibs113 \
  --mountpoint /ddn \
  --source 169.254.5.200@o2ib,169.254.6.200@o2ib:/fs00/amd
```

Bundle the skill with debs after copying the debs to the local machine:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/package_skill.ps1 `
  -DebDir C:\path\to\debs `
  -OutputZip C:\Users\Dell\Documents\ib\ddn-lustre-client-skill.zip
```

## Troubleshooting

Read `references/runbook.md` when the install fails, the server has different IB interface names, `lctl list_nids` says `Network is down`, `modprobe ko2iblnd` fails, or the mount hangs after LNet ping succeeds.
