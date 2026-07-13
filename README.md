# AIC8800 Linux Driver

AIC8800 WiFi 驱动程序。

## 概述

本驱动在原版基础上修复了 Linux Kernel 7.0 内核下的编译与运行问题：

- **`in_irq()` 编译错误**：Linux 5.18 起移除了 `in_irq()` 宏，7.0 内核中彻底不存在，编译报 `implicit declaration of function 'in_irq'`。已替换为等价的 `in_hardirq()`。
- **modpost 符号链接错误**：`aic8800_fdrv` 引用 `aic_load_fw` 通过 `EXPORT_SYMBOL` 导出的符号，单独编译时 modpost 报 undefined。已在 Makefile 中添加 `KBUILD_MODPOST_WARN=1` 降级为警告。
- **固件不匹配**：原项目自带的 `aic8800D80` 固件文件名与代码期望的 `8800dc` 命名不匹配，导致 probe 失败。已替换为 [idawnlight/AIC8800DC](https://github.com/idawnlight/AIC8800DC) 项目的 `aic8800DC` 固件。

## 测试环境

- **平台**: Pop!_OS 24.04 LTS
- **内核版本**: Linux 7.0.11-76070011-generic
- **网卡**: Tenda AIC8800DC (VID:PID = 2604:0014)

> 亦兼容 Arch Linux 6.17 内核。

## 致谢

本项目参考了以下资源:

- [绿联官方 AX300 驱动](https://www.ugreen.com/)
- [sqlwwx/aic8800](https://github.com/sqlwwx/aic8800) 项目中的适配工作
- [idawnlight/AIC8800DC](https://github.com/idawnlight/AIC8800DC) 提供的 `aic8800DC` 固件文件
- [BLUEMOON233/AIC8800-Linux-Driver](https://github.com/BLUEMOON233/AIC8800-Linux-Driver) 原始项目

## 编译安装

> **每次内核升级后必须重新编译安装**，因为内核模块的 vermagic 必须与运行内核完全匹配。

### 一键编译安装（推荐）

```bash
cd AIC8800-Linux-Driver

# 编译 → 校验 → 安装 → 加载 → 验证（全自动）
sudo bash build_install.sh

# 仅编译校验（不需要 root）
bash build_install.sh --build-only
```

脚本自动完成 7 个步骤：前置检查 → 清理 → 编译 aic_load_fw → 编译 aic8800_fdrv → 校验 vermagic → 安装固件和模块 → 加载验证。

### 手动安装

```bash
# 安装固件和 udev 规则
sudo cp -rf fw/aic8800DC /lib/firmware/
sudo cp tools/aic.rules /etc/udev/rules.d/
sudo udevadm control --reload
sudo udevadm trigger

# 编译安装 aic_load_fw（须先于 aic8800_fdrv）
cd drivers/aic8800/aic_load_fw
make
sudo make install
sudo depmod -a

# 编译安装 aic8800_fdrv
cd ../aic8800_fdrv
make
sudo make install
sudo depmod -a

# 加载驱动
sudo modprobe cfg80211
sudo modprobe aic_load_fw
sudo modprobe aic8800_fdrv

# 配置开机自动加载（仅首次）
sudo tee /etc/modules-load.d/aic8800.conf > /dev/null << 'EOF'
aic8800_fdrv
aic_load_fw
EOF
```

## 卸载

```bash
# 一键卸载
sudo bash uninstall_all.sh
```

## 注意事项

- 编译需要内核头文件：`sudo apt install linux-headers-$(uname -r) build-essential`
- **内核更新后需重新编译安装**，因为内核模块与内核版本严格绑定（vermagic 必须匹配）
- `depmod` 报 `zstd: Data corruption` 警告是 Pop!_OS 内核的已知问题，不影响驱动使用
