# Ubuntu 22.04 AMD Instinct APT Baseline

面向直接执行的中文操作说明见 [../README.md](../README.md)。

Validated reference configuration:

```text
Ubuntu 22.04.5 LTS
Kernel: 6.8.0-124-generic
AMDGPU: amdgpu-dkms 1:6.16.13.30300300-2327507.22.04
Firmware: amdgpu-dkms-firmware 30.30.3.0.30300300-2327507.22.04
ROCm: 7.2.3
```

Repository configuration:

```text
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/amdgpu/30.30.3/ubuntu jammy main
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.2.3 jammy main
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/7.2.3/ubuntu jammy main
```

Required package commands after registering the repositories:

```bash
sudo apt-get install -y "linux-headers-$(uname -r)" gcc-12 \
  amdgpu-dkms=1:6.16.13.30300300-2327507.22.04 \
  amdgpu-dkms-firmware=30.30.3.0.30300300-2327507.22.04

sudo apt-get install -y rocm
```

For a Runfile ROCm installation, uninstall its ROCm user space with the matching Runfile before installing APT ROCm. Do not purge a working APT `amdgpu-dkms` package merely because ROCm user space is being migrated.
