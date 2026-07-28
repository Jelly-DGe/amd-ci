# Ubuntu 22.04 AMDGPU APT 安装手册

本目录用于在 Ubuntu 22.04 裸机上通过 APT 安装和校验 AMD Instinct 驱动。已经在 8 卡 MI308X 主机上验证过。

## 固定版本

| 组件 | 版本 |
| --- | --- |
| AMDGPU 仓库 | `30.30.3` |
| `amdgpu-dkms` | `1:6.16.13.30300300-2327507.22.04` |
| `amdgpu-dkms-firmware` | `30.30.3.0.30300300-2327507.22.04` |
| ROCm 仓库 | `7.2.3` |

适用基线：Ubuntu 22.04.5 LTS，HWE 内核 `6.8.0-124-generic`。其他 `6.8` 内核也可以使用，但必须安装与当前运行内核完全匹配的 headers。

## 安装前检查

```bash
uname -r
lspci -Dnn | grep -Ei 'VGA|3D|Display|Processing accelerators'
dkms status | grep amdgpu || true
modinfo amdgpu | grep -E '^(filename|version|vermagic):' || true
grep -RniE '(^|[^[:alnum:]_])(blacklist|install)[[:space:]]+amdgpu' \
  /etc/modprobe.d /usr/lib/modprobe.d 2>/dev/null || true
```

最后一条若显示 `blacklist amdgpu`，驱动即使已经安装也不会自动加载。确认不是业务需要后，删除对应的黑名单文件并执行 `sudo update-initramfs -u -k all`，然后重启。

## 直接在目标机器安装

先写入 AMD 的 APT 源与签名密钥：

```bash
sudo install -d -m 0755 /etc/apt/keyrings /etc/apt/preferences.d
wget -qO- https://repo.radeon.com/rocm/rocm.gpg.key | \
  sudo gpg --dearmor --yes -o /etc/apt/keyrings/rocm.gpg

printf '%s\n' \
  'deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/amdgpu/30.30.3/ubuntu jammy main' | \
  sudo tee /etc/apt/sources.list.d/amdgpu.list >/dev/null

printf '%s\n' \
  'deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.2.3 jammy main' \
  'deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/7.2.3/ubuntu jammy main' | \
  sudo tee /etc/apt/sources.list.d/rocm.list >/dev/null

printf '%s\n' 'Package: *' 'Pin: release o=repo.radeon.com' 'Pin-Priority: 600' | \
  sudo tee /etc/apt/preferences.d/rocm-pin-600 >/dev/null
```

安装与当前内核匹配的编译环境、驱动和固件：

```bash
sudo apt update
sudo rm -f /var/crash/amdgpu-dkms.0.crash
sudo apt install -y "linux-headers-$(uname -r)" gcc-12 \
  amdgpu-dkms=1:6.16.13.30300300-2327507.22.04 \
  amdgpu-dkms-firmware=30.30.3.0.30300300-2327507.22.04
sudo reboot
```

`gcc-12` 是必要依赖。若 DKMS 日志中出现 `gcc-12: not found` 或 `cannot detect CFLAGS`，安装它后运行 `sudo dpkg --configure -a`，再重启。

ROCm 用户态按需安装：

```bash
sudo apt install -y rocm rocminfo
sudo usermod -aG render,video "$USER"
```

执行 `usermod` 后需要退出当前 SSH 会话并重新登录，组权限才会生效。

## 重启后的校验

```bash
lsmod | grep '^amdgpu'
dkms status | grep amdgpu
modinfo amdgpu | grep -E '^(filename|version|vermagic):'
amd-smi
rocminfo
```

预期 `modinfo amdgpu` 的路径含有 `updates/dkms/amdgpu.ko`，并且 `amd-smi` 能列出所有 PCIe GPU。

## 远程交互脚本

在一台 Linux 跳板机或管理机上运行：

```bash
chmod +x scripts/amd_baremetal_apt.sh
./scripts/amd_baremetal_apt.sh --check-only
./scripts/amd_baremetal_apt.sh
./scripts/amd_baremetal_apt.sh --with-rocm
```

脚本会询问目标 IP、SSH 用户和密码，先输出 GPU 数量、驱动版本、DKMS 状态和黑名单，再逐步询问是否卸载不匹配的 APT 驱动、安装目标版本、安装 ROCm、重启。密码仅存在于运行时环境变量中，不写入磁盘。

## 避免混装

若机器曾使用 ROCm Runfile 安装器，请先用**同一份 Runfile**卸载它的 ROCm 用户态，再通过 APT 安装 `rocm`。不要将 Runfile ROCm 与 APT ROCm 混用。

APT 安装的 `amdgpu-dkms` 可以单独保留。只有在需要更换 APT 驱动版本时，才在确认后执行：

```bash
sudo apt purge -y amdgpu-dkms amdgpu-dkms-firmware
```
