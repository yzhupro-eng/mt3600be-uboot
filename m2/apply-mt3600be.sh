#!/bin/bash
#
# GL.iNet GL-MT3600BE → hanwckf/bl-mt798x 移植补丁应用脚本
#
# 用法（在 hanwckf/bl-mt798x 仓库根目录执行）：
#     bash apply-mt3600be.sh <本目录(m2)的绝对路径>
#
# 幂等：重复执行会提示 already applied 并跳过（除 configs/dts 覆盖写外）。
#
set -euo pipefail

SRC="${1:?usage: apply-mt3600be.sh <m2-dir>}"
ROOT="$(pwd)"

ATF=atf-20250711
UB=uboot-mtk-20250711
ATF_CFG_DIR=atf-20240117-bacca82a8/configs   # atf-20250711/configs 是指向它的符号链接
UB_CFG_DIR=$UB/configs

say() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
ok()  { printf '   \033[1;32m✔ %s\033[0m\n' "$*"; }

[ -f build.sh ] || { echo "错误：请在 hanwckf/bl-mt798x 仓库根目录执行"; exit 1; }
[ -d "$ATF/plat/mediatek/mt7987" ] || { echo "错误：找不到 $ATF/plat/mediatek/mt7987"; exit 1; }
[ -d "$UB/arch/arm/dts" ] || { echo "错误：找不到 $UB/arch/arm/dts"; exit 1; }

export SRC ROOT ATF UB ATF_CFG_DIR UB_CFG_DIR

###############################################################################
say "1/9 ATF: 新增 mt7987 bl2/Config.in（SPIM2 开关符号）"
###############################################################################
if [ -f "$ATF/plat/mediatek/mt7987/bl2/Config.in" ]; then
	ok "已存在，跳过"
else
	cp "$SRC/atf-bl2-Config.in" "$ATF/plat/mediatek/mt7987/bl2/Config.in"
	ok "已写入"
fi

###############################################################################
say "2/9 ATF: apsoc_common/Config.in 引入该 Config.in"
###############################################################################
python3 - <<'PY'
import os
p = os.path.join(os.environ['ATF'], 'plat/mediatek/apsoc_common/Config.in')
s = open(p, encoding='utf-8').read()
inc = 'source "plat/mediatek/mt7987/bl2/Config.in"\n'
if inc in s:
    print('   already applied'); raise SystemExit
anchor = 'menu "Advanced boot device configuration"'
assert anchor in s, 'anchor not found: ' + anchor
s = s.replace(anchor, inc + '\n' + anchor, 1)
open(p, 'w', encoding='utf-8').write(s)
print('   ok')
PY

###############################################################################
say "3/9 ATF: mt7987/bl2/bl2.mk —— 增加编译宏与 BL2 DTB 切换"
###############################################################################
python3 - <<'PY'
import os
p = os.path.join(os.environ['ATF'], 'plat/mediatek/mt7987/bl2/bl2.mk')
s = open(p, encoding='utf-8').read()
if 'SPIM_NAND_PREFER_SPI2' in s:
    print('   already applied'); raise SystemExit

src_line = 'BL2_SOURCES\t\t+=\t$(MTK_PLAT_SOC)/bl2/bl2_dev_spi_nand.c\n'
assert src_line in s, 'src line not found'
s = s.replace(src_line, src_line +
    'ifeq ($(SPIM_NAND_PREFER_SPI2),1)\n'
    'BL2_CPPFLAGS\t\t+=\t-DSPIM_NAND_PREFER_SPI2\n'
    'endif # END OF SPIM_NAND_PREFER_SPI2\n'
    'ifeq ($(SPIM_NAND_NO_RETRY),1)\n'
    'BL2_CPPFLAGS\t\t+=\t-DSPIM_NAND_NO_RETRY\n'
    'endif # END OF SPIM_NAND_NO_RETRY\n', 1)

dts_line = 'DTS_NAME\t\t:=\tmt7987-spi0\n'
assert dts_line in s, 'DTS_NAME line not found'
s = s.replace(dts_line,
    '# MT3600BE: 闪存在 SPIM2 → BL2 内嵌 DTB 必须是 mt7987-spi2（0x11009800）\n'
    'ifeq ($(SPIM_NAND_PREFER_SPI2),1)\n'
    'DTS_NAME\t\t:=\tmt7987-spi2\n'
    'else\n'
    'DTS_NAME\t\t:=\tmt7987-spi0\n'
    'endif # END OF SPIM_NAND_PREFER_SPI2\n', 1)
open(p, 'w', encoding='utf-8').write(s)
print('   ok')
PY

###############################################################################
say "4/9 ATF: bl2_dev_spi_nand.c —— GPIO pinmux 走 SPIM2"
###############################################################################
python3 - <<'PY'
import os
p = os.path.join(os.environ['ATF'], 'plat/mediatek/mt7987/bl2/bl2_dev_spi_nand.c')
s = open(p, encoding='utf-8').read()
if 'SPIM_NAND_PREFER_SPI2' in s:
    print('   already applied'); raise SystemExit
old = '\t/* config GPIO pinmux to spi mode */\n\tmtk_spi_gpio_init(SPIM0);\n'
assert old in s, 'gpio init block not found'
new = ('#ifdef SPIM_NAND_PREFER_SPI2\n'
       '\t/* MT3600BE: SPI-NAND 在 SPIM2（GPIO25-30 / 0x11009800） */\n'
       '\tmtk_spi_gpio_init(SPIM2);\n'
       '#else\n'
       '\t/* config GPIO pinmux to spi mode */\n'
       '\tmtk_spi_gpio_init(SPIM0);\n'
       '#endif\n')
s = s.replace(old, new, 1)
open(p, 'w', encoding='utf-8').write(s)
print('   ok')
PY

###############################################################################
say "5/9 ATF: platform.mk —— 登记新的 make 依赖（GEN_DEP_RULES + MAKE_DEP 成对）"
###############################################################################
python3 - <<'PY'
import os
p = os.path.join(os.environ['ATF'], 'plat/mediatek/mt7987/platform.mk')
s = open(p, encoding='utf-8').read()
if 'SPIM_NAND_PREFER_SPI2' in s:
    print('   already applied'); raise SystemExit

old = '$(call GEN_DEP_RULES,bl2,emicfg bl2_boot_ram bl2_boot_nand_nmbm bl2_dev_mmc bl2_plat_init bl2_plat_setup mt7987_gpio dtb)\n'
assert old in s, 'GEN_DEP_RULES line not found'
new = old.replace(' bl2_dev_mmc ', ' bl2_dev_mmc bl2_dev_spi_nand ')
s = s.replace(old, new, 1)

s += ('\n# MT3600BE port: SPIM-NAND on SPI2 (see uboot移植项目-hanwckf/m2)\n'
      '$(call MAKE_DEP,bl2,bl2_dev_spi_nand,BOOT_DEVICE SPIM_NAND_PREFER_SPI2 SPIM_NAND_NO_RETRY)\n')
open(p, 'w', encoding='utf-8').write(s)
print('   ok')
PY

###############################################################################
say "6/9 板级 defconfig（ATF + U-Boot，必须同名）"
###############################################################################
cp "$SRC/atf-configs-mt7987_glinet_gl-mt3600be_defconfig" \
   "$ATF_CFG_DIR/mt7987_glinet_gl-mt3600be_defconfig"
cp "$SRC/uboot-configs-mt7987_glinet_gl-mt3600be_defconfig" \
   "$UB_CFG_DIR/mt7987_glinet_gl-mt3600be_defconfig"
ok "已写入 $ATF_CFG_DIR 与 $UB_CFG_DIR"

###############################################################################
say "7/9 U-Boot 设备树（board dts + u-boot glue）"
###############################################################################
cp "$SRC/mt7987a-glinet-gl-mt3600be.dts"        "$UB/arch/arm/dts/"
cp "$SRC/mt7987a-glinet-gl-mt3600be-u-boot.dtsi" "$UB/arch/arm/dts/"
ok "已写入 $UB/arch/arm/dts/"

###############################################################################
say "8/9 注册 DTB 到 arch/arm/dts/Makefile（原树没有 mt7987 条目）"
###############################################################################
python3 - <<'PY'
import os
p = os.path.join(os.environ['UB'], 'arch/arm/dts/Makefile')
s = open(p, encoding='utf-8').read()
name = 'mt7987a-glinet-gl-mt3600be.dtb'
if name in s:
    print('   already applied'); raise SystemExit
anchor = 'dtb-$(CONFIG_ARCH_MEDIATEK) += \\\n'
assert anchor in s, 'anchor not found'
s = s.replace(anchor, anchor + '\t' + name + ' \\\n', 1)
open(p, 'w', encoding='utf-8').write(s)
print('   ok')
PY

###############################################################################
say "9/9 RAM 启动变体（给 mtk_uartboot ramboot 用；不写 flash 验证）"
###############################################################################
# ATF 侧用 _BOOT_DEVICE_RAM + _RAM_BOOT_RAM_BOOT_UART_DL（UART 收 FIP）
cp "$SRC/atf-configs-mt7987_glinet_gl-mt3600be-ram_defconfig" \
   "$ATF_CFG_DIR/mt7987_glinet_gl-mt3600be-ram_defconfig"
# U-Boot 侧同名配置存在即可（build.sh 要求同名；内容与主配置一致）
cp "$SRC/uboot-configs-mt7987_glinet_gl-mt3600be_defconfig" \
   "$UB_CFG_DIR/mt7987_glinet_gl-mt3600be-ram_defconfig"
ok "已写入 ram 变体（ATF + U-Boot）"

###############################################################################
say "额外：build.sh 指向 20250711 的 ATF/U-Boot 树"
###############################################################################
python3 - <<'PY'
import os, re
p = 'build.sh'
s = open(p, encoding='utf-8').read()
s = re.sub(r'^UBOOT_DIR=.*$', 'UBOOT_DIR=uboot-mtk-20250711', s, count=1, flags=re.M)
s = re.sub(r'^ATF_DIR=.*$',   'ATF_DIR=atf-20250711',        s, count=1, flags=re.M)
open(p, 'w', encoding='utf-8').write(s)
print('   UBOOT_DIR=uboot-mtk-20250711 / ATF_DIR=atf-20250711')
PY

say "完成。构建命令："
echo "    SOC=mt7987 BOARD=glinet_gl-mt3600be ./build.sh"
echo "    SOC=mt7987 BOARD=glinet_gl-mt3600be-ram ./build.sh   # ramboot 用 BL2"
