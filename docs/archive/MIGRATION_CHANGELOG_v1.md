# HX1P35A 第一版迁移改动清单

> 来源：提交 `455778f`。

## 已迁移并接入

- 从旧工程 `rgb2yuv.v` 与 `yuv2rgb.v` 提取器件无关定点公式；
- 在 `video_out` 与 `hdmi_mixer` 之间接入 RGB/YUV 适配和视觉模块；
- 加入原图、灰度、颜色二值和轻量边缘显示；
- 加入红绿蓝像素统计、包围框、状态条与蜂鸣器；
- 蜂鸣器使用 C12、低有效；
- 新增 RTL 已加入 TD `.al` 工程。

## 明确未迁移

- Vivado Block Design、MicroBlaze、AXI Interconnect；
- Xilinx MIG DDR3、ILA、Clock Wizard、DNA/IP Integrator；
- 旧板多路 LVDS 接收和解串；
- 10G SFP GT、RGMII、TCP_10G。

## 第一版编译注意事项

- 保持参考工程的 MIPI、DDR、HDMI、PLL 和 FIFO IP；
- 目标器件为 PH1P35MDG324；
- 必须在匹配版本的 Tang Dynasty 中重新综合、布局布线并实机验证；
- 当时本机没有可用的 TD、Icarus、Yosys 或 Verilator，因此仅完成静态检查。
