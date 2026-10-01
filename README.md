# mt3600be-uboot

GL.iNet **GL-MT3600BE**（MediaTek MT7987A）的 U-Boot/ATF 移植**编译仓库**。

- 移植目标上游：`hanwckf/bl-mt798x` @ `abe158087c80ed1896f2c281e2dae5e43ffbee41`（2026-09-08）
- 产物：`output/mt7987_glinet_gl-mt3600be-fip-fixed-parts.bin` → 刷到 **FIP** 分区（0x580000, 2MB）
- `m2/`：板级 defconfig ×2、U-Boot DTS ×2、ATF 的 SPIM2 补丁、一键应用脚本
- `.github/workflows/build-mt3600be.yml`：手动触发编译（Actions → build-mt3600be → Run workflow）

## 为什么需要补丁

本机 SPI-NAND 挂在 **SPIM2**（`0x11009800` / GPIO25-30），
而 hanwckf 的 ATF 把 SPIM-NAND 启动写死成 **SPIM0**（GPIO15-20）→
不打补丁 BL2 读不到 FIP。详见 `m2/README.md`。

本仓库只用于编译，不改上游代码：workflow 会 clone 上游 → 应用 `m2/` → 编译 → 上传产物。
