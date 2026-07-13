#!/bin/bash
#
# AIC8800 驱动一站式脚本：编译 → 校验 → 安装 → 加载 → 验证
#
# 用法:
#   sudo bash build_install.sh          # 全流程
#   bash build_install.sh --build-only  # 仅编译（无需 root）
#

set -e

KVER=$(uname -r)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRV_DIR="${SCRIPT_DIR}/drivers/aic8800"
FW_DIR="${SCRIPT_DIR}/fw/aic8800DC"
MODDESTDIR="/lib/modules/${KVER}/kernel/drivers/net/wireless/aic8800"

BUILD_ONLY=false
if [ "$1" = "--build-only" ]; then
    BUILD_ONLY=true
fi

echo "##################################################"
echo "# AIC8800 驱动编译安装 (内核: ${KVER})"
echo "##################################################"
echo ""

# ========== 1. 前置检查 ==========
echo "[1/7] 前置检查..."

if [ ! -d "/lib/modules/${KVER}/build" ]; then
    echo "  ❌ 内核头文件未安装！请执行:"
    echo "     sudo apt install linux-headers-${KVER} build-essential"
    exit 1
fi
echo "  内核头文件 ✅"

if ! command -v make &>/dev/null; then
    echo "  ❌ make 未安装！请执行: sudo apt install build-essential"
    exit 1
fi
echo "  make ✅"

if [ ! -d "${FW_DIR}" ]; then
    echo "  ❌ 固件目录不存在: ${FW_DIR}"
    exit 1
fi
echo "  固件文件 ✅"
echo ""

# ========== 2. 清理旧编译产物 ==========
echo "[2/7] 清理旧编译产物..."
(cd "${DRV_DIR}/aic_load_fw" && make clean >/dev/null 2>&1) || true
(cd "${DRV_DIR}/aic8800_fdrv" && make clean >/dev/null 2>&1) || true
echo "  已清理 ✅"
echo ""

# ========== 3. 编译 aic_load_fw ==========
echo "[3/7] 编译 aic_load_fw..."
(cd "${DRV_DIR}/aic_load_fw" && make 2>&1) | grep -iE "error:|warning:.*error" | head -5 || true
if [ ! -f "${DRV_DIR}/aic_load_fw/aic_load_fw.ko" ]; then
    echo "  ❌ aic_load_fw.ko 编译失败！"
    echo "  完整日志: cd ${DRV_DIR}/aic_load_fw && make"
    exit 1
fi
echo "  aic_load_fw.ko 生成成功 ✅"
echo ""

# ========== 4. 编译 aic8800_fdrv ==========
echo "[4/7] 编译 aic8800_fdrv..."
(cd "${DRV_DIR}/aic8800_fdrv" && make 2>&1) | grep -iE "error:|warning:.*error" | head -5 || true
if [ ! -f "${DRV_DIR}/aic8800_fdrv/aic8800_fdrv.ko" ]; then
    echo "  ❌ aic8800_fdrv.ko 编译失败！"
    echo "  完整日志: cd ${DRV_DIR}/aic8800_fdrv && make"
    exit 1
fi
echo "  aic8800_fdrv.ko 生成成功 ✅"
echo ""

# ========== 5. 校验 vermagic ==========
echo "[5/7] 校验模块 vermagic..."
EXPECTED="vermagic:.*${KVER}"
for ko in aic_load_fw/aic_load_fw.ko aic8800_fdrv/aic8800_fdrv.ko; do
    KO_PATH="${DRV_DIR}/${ko}"
    VMAGIC=$(modinfo "${KO_PATH}" 2>/dev/null | grep vermagic || echo "")
    if echo "${VMAGIC}" | grep -q "${KVER}"; then
        echo "  $(basename ${ko}): ${VMAGIC#vermagic:       } ✅"
    else
        echo "  ❌ $(basename ${ko}) vermagic 不匹配!"
        echo "     期望包含: ${KVER}"
        echo "     实际: ${VMAGIC}"
        exit 1
    fi
done
echo ""

if [ "$BUILD_ONLY" = true ]; then
    echo "##################################################"
    echo "# 编译校验完成（--build-only 模式，跳过安装）"
    echo "# 如需安装: sudo bash ${BASH_SOURCE[0]}"
    echo "##################################################"
    exit 0
fi

# ========== 以下需要 root 权限 ==========
if [ "$(id -u)" -ne 0 ]; then
    echo "编译校验完成，需要 root 权限执行安装。重新以 sudo 运行..."
    exec sudo bash "$0" "$@"
fi

# ========== 6. 卸载旧模块 + 安装 ==========
echo "[6/7] 安装..."

# 卸载已加载的旧模块
echo "  卸载旧模块..."
rmmod aic8800_fdrv 2>/dev/null && echo "    aic8800_fdrv 已卸载" || echo "    aic8800_fdrv 未加载"
rmmod aic_load_fw 2>/dev/null && echo "    aic_load_fw 已卸载" || echo "    aic_load_fw 未加载"
rmmod cfg80211 2>/dev/null && echo "    cfg80211 已卸载" || echo "    cfg80211 保留"

# 安装固件
echo "  安装固件..."
rm -rf /lib/firmware/aic8800DC /lib/firmware/aic8800D80 2>/dev/null || true
cp -rf "${FW_DIR}" /lib/firmware/

# 安装 udev 规则
cp "${SCRIPT_DIR}/tools/aic.rules" /etc/udev/rules.d/ 2>/dev/null || true
udevadm control --reload 2>/dev/null || true
udevadm trigger 2>/dev/null || true

# 安装模块
echo "  安装内核模块..."
mkdir -p "${MODDESTDIR}"
install -p -m 644 "${DRV_DIR}/aic_load_fw/aic_load_fw.ko" "${MODDESTDIR}/"
install -p -m 644 "${DRV_DIR}/aic8800_fdrv/aic8800_fdrv.ko" "${MODDESTDIR}/"
depmod -a "${KVER}" 2>/dev/null || true
echo "  安装完成 ✅"
echo ""

# ========== 7. 加载并验证 ==========
echo "[7/7] 加载驱动并验证..."
modprobe cfg80211 2>/dev/null || true
modprobe aic_load_fw 2>/dev/null || true
modprobe aic8800_fdrv 2>/dev/null || true
sleep 1

echo ""
echo "--- 模块加载状态 ---"
if lsmod | grep -q aic8800_fdrv; then
    echo "  aic8800_fdrv  已加载 ✅"
else
    echo "  aic8800_fdrv  加载失败 ❌ (查看: dmesg | grep -i aic)"
fi
lsmod | grep -iE "aic|cfg80211"

echo ""
echo "--- 无线网卡接口 ---"
WIFI_IF=$(ip link show 2>/dev/null | grep -oE "wlx[a-f0-9]{12}|wlan[0-9]" | head -1)
if [ -n "${WIFI_IF}" ]; then
    echo "  ${WIFI_IF} 已创建 ✅"
    ip link show "${WIFI_IF}" | head -2
else
    echo "  未发现无线接口 ❌"
    echo "  排查: sudo dmesg | grep -i aic"
fi

echo ""
echo "--- USB 设备 ---"
lsusb 2>/dev/null | grep -iE "2604|tenda|aic" || echo "  (未检测到 AIC USB 设备)"

echo ""
echo "--- 开机自动加载 ---"
if [ -f /etc/modules-load.d/aic8800.conf ]; then
    echo "  已配置 ✅"
else
    echo "  未配置，执行以下命令配置:"
    echo "  sudo tee /etc/modules-load.d/aic8800.conf > /dev/null << 'EOF'"
    echo "  aic8800_fdrv"
    echo "  aic_load_fw"
    echo "  EOF"
fi

echo ""
echo "##################################################"
echo "# 完成！内核 ${KVER} 驱动已就绪"
echo "# 如遇问题: sudo dmesg | grep -i aic"
echo "##################################################"
