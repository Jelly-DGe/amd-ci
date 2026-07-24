---
name: amd-baremetal-apt
description: Install, align, and verify AMD Instinct bare-metal GPU drivers and ROCm on Ubuntu through APT and SSH. Use for remote server IP/password prompts, PCI GPU enumeration, AMDGPU DKMS version checks, controlled driver replacement, ROCm APT setup, or diagnosing AMD-SMI access on AMD GPU servers.
---

# AMD Bare-Metal APT

Use this skill for the validated Ubuntu 22.04 AMD Instinct baseline:

- AMDGPU repository `30.30.3`; `amdgpu-dkms` `6.16.13.30300300-2327507.22.04`.
- ROCm repository `7.2.3`; install the `rocm` meta package when ROCm is required.
- Reference host configuration: Ubuntu 22.04.5, kernel `6.8.0-124-generic`, AMDGPU DKMS `6.16.13`.

Read [references/apt-baseline.md](references/apt-baseline.md) before changing a host. Use [scripts/amd_baremetal_apt.sh](scripts/amd_baremetal_apt.sh) for interactive deployment.

## Workflow

1. Ask for the target IP, SSH account, and password. Do not persist credentials.
2. Run the script in check mode first. Confirm PCIe AMD accelerator count, active driver, DKMS package version, and blacklists.
3. If the driver package differs from the baseline, explain the detected version and request confirmation before purging it. Do not remove a Runfile-installed stack with `apt`; use its Runfile uninstaller first.
4. On approval, configure the AMD repositories, install the exact driver and firmware packages, then validate DKMS and `modinfo`.
5. Reboot only after explicit approval. After reconnecting, validate `amd-smi`, `rocminfo`, and user membership in `render` and `video`.

## Safety

- Never format disks or alter GPU firmware.
- Treat a missing `gcc-12` for a kernel built with GCC 12 as a DKMS build prerequisite, not a GPU failure.
- If `/etc/modprobe.d/blacklist-amdgpu.conf` exists, report it. Remove it only with explicit user approval because it changes boot behavior.
- Preserve unrelated DKMS packages such as Mellanox/DOCA components.
