# ATLE0200P → 安路 PH1P35A 迁移版

这是将原 Kintex-7/Vivado 工程按功能重新组织的安路 PH1P35A（Tang Dynasty）迁移目录。它不包含或复用任何 Xilinx `.xci`、Block Design、MicroBlaze、MIG、ILA、GT 或约束文件。

目录内的 `reference_edge_project/` 是完整的安路官方边缘检测工程基线（PH1P35MDG324，约 88 MiB / 93 个 Verilog 文件），包括 MIPI D-PHY RX、SC500 摄像头配置、RAW10 解包、ISP、DDR、HDMI、PLL、FIFO、安路工程文件与 pin/SDC 约束。它是实际可由 Tang Dynasty 打开的工程：`reference_edge_project/td_project/camera_to_dsi_display.al`。

## 已实现的迁移范围

`RGB888 视频流 → 灰度 / Sobel 边缘 / 红色目标检测 → OSD 框与状态条 → RGB888 输出`。

* `src/video_processor.v`：单时钟像素流处理核心；使用行缓存完成 3×3 Sobel，输出可选灰度、边缘或原图。
* `src/color_target_detect.v`：红色像素阈值检测、每帧像素计数、检测结果输出。
* `src/osd_overlay.v`：在视频左上角显示模式/目标状态色条，并在检测到目标时绘制居中红框。
* `src/ph1p35_video_top.v`：面向安路平台的顶层，接口为标准 RGB888 + `vsync/hsync/de`。

## 必须接入开发板参考工程的部分

本工程的完整硬件适配基线已经复制到 `reference_edge_project/`；同时也可参考现有资料中的
`HX1P35A_Contest_202606/lab_ex4_red_detect_SC520`（SC520 传感器版本）：

1. 使用其中的 MIPI D-PHY RX、`csi_unpacket_2lane.v`、RAW10 解包、ISP/demosaic，把摄像头转为 RGB888 流。
2. 将 ISP 的 `pixel_clk/rst_n/vsync/hsync/de/rgb888` 接到 `ph1p35_video_top` 的 `I_pix_*`。
3. 将 `O_pix_*` 接到该示例已有的 HDMI/DSI 输出链路。显示接口采用何种芯片、引脚和时钟取决于开发板原理图。
4. 在 Tang Dynasty 新建 PH1P35A 项目，加入 `src/` 文件，并按 `constraints/board_template.adc` 填写真实管脚与时钟。随后生成/加入参考工程所需的 PLL、MIPI、DDR IP。

## 与原 Xilinx 工程的对应关系

| 原工程能力 | 安路版处理方式 |
| --- | --- |
| LVDS 1:7 接收、DDR3 帧缓存、DP/10G | 不直接迁移；均为器件/板卡专用 IP，需要按目标硬件另行适配 |
| YUV/RGB 转换 | 由参考工程 MIPI ISP 输出 RGB888；可在 ISP 前后增加转换模块 |
| `video_data_sw` | `I_mode` 支持原图/灰度/边缘显示切换 |
| RGB 分析 | `color_target_detect` 提供红色目标存在标志和计数 |
| 调试 ILA | 删除；可使用安路在线调试 IP 重新插入 |

## 重要限制

* `reference_edge_project/` 是完整且可打开的 `.al` 工程；`src/` 是本次新增的可复用处理核心。二者尚未自动合并，因为当前参考工程已自带 `edge_detect_96.v`，而新增核心采用 RGB888 视频流接口；合并前需在 `design_top_wrapper.v` 中按实际视频时钟域选择一个处理链。
* Sobel 行缓存最大宽度由 `IMAGE_WIDTH` 参数决定，必须与摄像头实际有效像素宽度一致；默认 1280。
* 处理核心不使用 DDR，因此可先完成低延迟直通显示；若要保留原工程的帧缓存、多路切换或网络传输，需在该核心外接安路 DDR/以太网 IP。

## 本地检查记录（2026-10-08）

* 已复制的 `reference_edge_project` 含 93 个 Verilog 文件与完整 Tang Dynasty 项目文件；已有实现产物为 `td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit`。
* 保存的 `final_timing.rpt` 显示参考工程实现通过：setup WNS `1.163 ns`、hold WNS `0.020 ns`、0 个违规端点。
* 本机未安装构建脚本要求的 `E:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe`，已实际尝试启动并得到“命令未找到”，因此无法在本机对本次新增的 `src/` 文件重跑综合。
* `src/` 文件是独立 RGB888 流模块，尚未加入参考工程的 `.al` 源文件集；直接把它们加入工程不会替代现有 `edge_detect_96.v`，必须先在 `design_top_wrapper.v` 的 ISP/显示路径完成一次明确的接口选择和时钟域接入。
# 当前已接入的可运行功能

在 `reference_edge_project` 的 MIPI → ISP → DDR 帧缓存 → HDMI 参考链路上，已加入纯 RTL 显示侧视觉功能：

- 按键循环选择原图、灰度、三色目标掩膜、真正的 3×3 Sobel 边缘图；
- 红／绿／蓝高饱和目标的像素面积统计和上一帧包围框；
- HDMI 画面目标框与状态条 OSD；
- 目标首次出现时驱动板载低有效蜂鸣器 `C12` 短鸣约 200 ms；
- 保留并接入从旧工程剥离的 RGB↔YUV 定点转换公式。

新增 RTL 位于 `reference_edge_project/user_source/hdl_source/hx1p35_port/`。按键 0 已加入同步与约 10 ms 消抖，每按一次按 `原图 → 灰度 → 三色掩膜 → Sobel` 循环；按键 1 每按一次开关蜂鸣告警。为避免一键两用导致画面曝光同时变化，参考工程 `ae_set` 的手动曝光按键输入已固定为未按下，保留默认曝光参数。这些功能均不依赖 Xilinx IP；必须在安路 TD 中打开 `td_project/camera_to_dsi_display.al` 后，以该工程的 IP 和约束完成综合、布局布线与下载验证。

