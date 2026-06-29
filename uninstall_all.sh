#!/bin/bash
#
# AIC8800 驱动彻底清理脚本
# 用法: sudo bash uninstall_all.sh
#

if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 sudo 运行: sudo bash uninstall_all.sh"
    exit 1
fi

KVER=$(uname -r)
MODDESTDIR="/lib/modules/${KVER}/kernel/drivers/net/wireless/aic8800"

echo "##################################################"
echo "# AIC8800 驱动彻底清理 (内核: ${KVER})"
echo "##################################################"

# 1. 卸载已加载的模块
echo "[1/5] 卸载内核模块..."
rmmod aic8800_fdrv 2>/dev/null && echo "  已卸载 aic8800_fdrv" || echo "  aic8800_fdrv 未加载"
rmmod aic_load_fw 2>/dev/null && echo "  已卸载 aic_load_fw" || echo "  aic_load_fw 未加载"
rmmod cfg80211 2>/dev/null && echo "  已卸载 cfg80211" || echo "  cfg80211 被其他模块依赖，保留"

# 2. 删除已安装的 .ko 模块文件
echo "[2/5] 删除已安装的模块文件..."
if [ -d "${MODDESTDIR}" ]; then
    rm -rfv "${MODDESTDIR}"
    echo "  已删除 ${MODDESTDIR}"
else
    echo "  模块目录不存在"
fi

# 3. 删除固件文件 (所有可能的目录)
echo "[3/5] 删除固件文件..."
for fwdir in /lib/firmware/aic8800D80 /lib/firmware/aic8800DC /lib/firmware/aic8800 /lib/firmware/aic8800D80X2; do
    if [ -d "${fwdir}" ]; then
        rm -rfv "${fwdir}"
        echo "  已删除 ${fwdir}"
    fi
done

# 4. 删除 udev 规则
echo "[4/5] 删除 udev 规则..."
for rule in /etc/udev/rules.d/aic.rules /lib/udev/rules.d/aic.rules; do
    if [ -f "${rule}" ]; then
        rm -fv "${rule}"
        echo "  已删除 ${rule}"
    fi
done
udevadm control --reload 2>/dev/null || true

# 5. 更新模块依赖
echo "[5/5] 更新模块依赖..."
depmod -a "${KVER}" 2>/dev/null && echo "  depmod 完成" || echo "  depmod 有警告(可忽略)"

echo ""
echo "=== 验证清理结果 ==="
echo "--- 已加载模块 ---"
lsmod | grep -iE "aic|cfg80211" && echo "  (仍有残留)" || echo "  无 aic 模块残留 ✅"
echo "--- 模块文件 ---"
find /lib/modules/${KVER} -iname "aic*.ko" 2>/dev/null && echo "  (仍有残留)" || echo "  无 aic .ko 文件 ✅"
echo "--- 固件目录 ---"
ls -d /lib/firmware/aic8800* 2>/dev/null && echo "  (仍有残留)" || echo "  无 aic 固件残留 ✅"
echo "--- udev 规则 ---"
ls /etc/udev/rules.d/aic* 2>/dev/null && echo "  (仍有残留)" || echo "  无 aic udev 规则 ✅"

echo ""
echo "##################################################"
echo "# 清理完成！"
echo "##################################################"
