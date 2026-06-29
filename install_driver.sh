#!/bin/bash
#
# AIC8800 驱动一键安装脚本 (Linux 7.0 内核)
# 用法: sudo bash install_driver.sh
#

set -e

KVER=$(uname -r)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODDESTDIR="/lib/modules/${KVER}/kernel/drivers/net/wireless/aic8800"

if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 sudo 运行: sudo bash install_driver.sh"
    exit 1
fi

echo "##################################################"
echo "# AIC8800 驱动安装  (内核: ${KVER})"
echo "##################################################"

# 1. 安装固件和 udev 规则
echo "[1/6] 安装固件和 udev 规则..."
cp -rf "${SCRIPT_DIR}/fw/aic8800DC" /lib/firmware/
cp "${SCRIPT_DIR}/tools/aic.rules" /etc/udev/rules.d/
udevadm control --reload 2>/dev/null || true
udevadm trigger 2>/dev/null || true
if [ -L /dev/aicudisk ]; then
    eject /dev/aicudisk 2>/dev/null || true
fi

# 2. 安装 aic_load_fw 模块
echo "[2/6] 安装 aic_load_fw 模块..."
mkdir -p "${MODDESTDIR}"
install -p -m 644 "${SCRIPT_DIR}/drivers/aic8800/aic_load_fw/aic_load_fw.ko" "${MODDESTDIR}/"

# 3. 安装 aic8800_fdrv 模块
echo "[3/6] 安装 aic8800_fdrv 模块..."
install -p -m 644 "${SCRIPT_DIR}/drivers/aic8800/aic8800_fdrv/aic8800_fdrv.ko" "${MODDESTDIR}/"

# 4. 更新模块依赖
echo "[4/6] 更新模块依赖 (depmod)..."
depmod -a "${KVER}"

# 5. 加载驱动
echo "[5/6] 加载驱动..."
modprobe cfg80211
modprobe aic_load_fw
modprobe aic8800_fdrv

# 6. 验证
echo "[6/6] 验证安装结果..."
echo ""
echo "--- 已加载的 aic 模块 ---"
lsmod | grep -E "aic|cfg80211"
echo ""
echo "--- 无线网卡接口 ---"
ip link show | grep -A1 -iE "wlan|wlx" || echo "(未发现无线接口，请检查 dmesg)"
echo ""
echo "--- USB 设备识别 ---"
lsusb | grep -i aic || echo "(未在 lsusb 中发现 aic 设备)"
echo ""
echo "--- 内核日志 (最近 aic 相关) ---"
dmesg | grep -i aic | tail -15

echo ""
echo "##################################################"
echo "# 安装完成！"
echo "# 如需查看完整日志: dmesg | grep -i aic"
echo "# 如驱动未识别，请检查 USB 网卡是否已插入"
echo "##################################################"
