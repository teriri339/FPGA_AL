# ATLE0200P → 安路 PH1P35A 迁移版

这是将原 Kintex-7/Vivado 工程按功能重新组织的安路 PH1P35A（Tang Dynasty）迁移目录。它不包含或复用任何 Xilinx `.xci`、Block Design、MicroBlaze、MIG、ILA、GT 或约束文件。

当前开发分支为 `WZY`。工程目录导航和分支使用规则见 `docs/PROJECT_STRUCTURE.md`；`main` 仅保留稳定基线，不直接覆盖。

旧 Vivado 工程的逐模块迁移状态、已带入的独立 RTL 与无法原样迁移的硬件/IP 依赖见 `docs/LEGACY_CODE_MIGRATION.md`。

目录内的 `reference_edge_project/` 是完整的安路官方边缘检测工程基线（PH1P35MDG324），包括 MIPI D-PHY RX、SC520 摄像头配置、RAW10 解包、ISP、DDR、HDMI、PLL、FIFO、安路工程文件与 pin/SDC 约束。当前摄像头工作模式为 1280×720@60、RAW10、2 Lane、828 Mbps/Lane。Tang Dynasty 工程入口为：`reference_edge_project/td_project/camera_to_dsi_display.al`。

## 已实现的迁移范围

`RGB888 视频流 → 原图 / 灰度 / Sobel 边缘 / 红绿蓝目标检测 → OSD 框与状态条 → RGB888 输出`。

* `src/video_processor.v`：单时钟像素流处理核心；使用行缓存完成 3×3 Sobel，输出可选灰度、边缘或原图。
* `src/color_target_detect.v`：红色像素阈值检测、每帧像素计数、检测结果输出。
* `src/osd_overlay.v`：在视频左上角显示模式/目标状态色条，并在检测到目标时绘制居中红框。
* `src/ph1p35_video_top.v`：面向安路平台的顶层，接口为标准 RGB888 + `vsync/hsync/de`。

## 硬件处理链路

本工程的完整硬件适配基线和视觉算法已经集成在 `reference_edge_project/`。当前有效链路为：

`SC520 → MIPI D-PHY RX → RAW10 解包 → ISP/demosaic → DDR 帧缓存 → 视觉处理 → HDMI`

直接使用 Tang Dynasty 打开 `reference_edge_project/td_project/camera_to_dsi_display.al`。无需重新创建工程，也不要把根目录 `src/` 直接加入当前工程；`src/` 是早期独立算法样例，实际接入版本位于 `reference_edge_project/user_source/hdl_source/hx1p35_port/`。

## 与原 Xilinx 工程的对应关系

| 原工程能力 | 安路版处理方式 |
| --- | --- |
| LVDS 1:7 接收、DDR3 帧缓存、DP/10G | 不直接迁移；均为器件/板卡专用 IP，需要按目标硬件另行适配 |
| YUV/RGB 转换 | 由参考工程 MIPI ISP 输出 RGB888；可在 ISP 前后增加转换模块 |
| `video_data_sw` | `I_mode` 支持原图/灰度/边缘显示切换 |
| RGB 分析 | `color_target_detect` 提供红色目标存在标志和计数 |
| 调试 ILA | 删除；可使用安路在线调试 IP 重新插入 |

## 重要限制

* `reference_edge_project/` 是当前完整且可打开的 `.al` 工程；`src/` 仅保留为早期独立样例，当前综合使用的是 `hx1p35_port/` 内的接入版本。
* Sobel 行缓存最大宽度由 `IMAGE_WIDTH` 参数决定，必须与摄像头实际有效像素宽度一致；默认 1280。
* 处理核心不使用 DDR，因此可先完成低延迟直通显示；若要保留原工程的帧缓存、多路切换或网络传输，需在该核心外接安路 DDR/以太网 IP。

## 本地检查记录（2026-10-08）

* 已复制的 `reference_edge_project` 含 93 个 Verilog 文件与完整 Tang Dynasty 项目文件；已有实现产物为 `td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit`。
* 2026-10-14 已使用本机安路 TD 6.2.168116 完成综合、布局布线和位流生成；Canny 暗部轮廓补全版本最终 setup WNS `0.311 ns`、hold WNS `0.020 ns`、0 个违规端点，使用 15453 slices（72.84%）、39 RAM、23 DSP。
* SC520、视觉处理源码、管脚与时序约束均已加入 `.al` 工程；最新标准位流位于 `td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit`，仍需烧录后进行摄像头实拍确认。
# 当前已接入的可运行功能

在 `reference_edge_project` 的 MIPI → ISP → DDR 帧缓存 → HDMI 参考链路上，已加入纯 RTL 显示侧视觉功能：

- 按键循环选择原图、灰度、彩色目标高亮、全屏轻量 Canny 轮廓图；Canny 先用 3×3 Gaussian 平滑抑制噪声，再执行 Sobel 梯度、0°/45°/90°/135° 四方向峰值细化，并根据整帧亮度自动选择弱门限 `56/80/112` 和强门限 `96/128/192`，最后受控延伸一个弱边缘像素以补齐短断点；
- 红／绿／蓝目标检测采用亮度、色差和同色邻域一致性三级筛选；绿色使用适合偏暗印刷包装的独立门限，暗光孤立噪点仍不会进入目标面积、包围框和蜂鸣器告警；COLOR 模式保留半亮原图作为背景；
- 全画面亮度抽样闭环自动曝光：过暗时先增加曝光时间、到上限后增加增益，过亮时反向调整，并设置亮度死区和 16 帧调节间隔以减少闪烁；
- 自动曝光加入高光保护：接近饱和的采样区域超过约 3% 时，即使全局平均亮度偏暗也会优先降低增益/曝光，减轻灯具和中间反光区域过曝；
- HDMI 画面目标框与状态条 OSD；目标框仅在 COLOR 模式显示，避免干扰 RAW、GRAY 和 SOBEL 观察；
- 目标首次出现时仿照板载初始音乐工程，在 `C12` 输出约 2 kHz 方波并告警约 1 秒，适配板载无源蜂鸣器；
- 保留并接入从旧工程剥离的 RGB↔YUV 定点转换公式。

新增 RTL 位于 `reference_edge_project/user_source/hdl_source/hx1p35_port/`。板载 KEY2（A9）已加入同步与约 10 ms 消抖，每按一次按 `原图 → 灰度 → 彩色目标高亮 → Sobel` 循环；板载 KEY3（B9）每按一次按 `AUTO → EXP:0 → EXP:1 → EXP:2 → EXP:3 → AUTO` 循环；板载 KEY1（D5）用作低有效系统复位。上电默认自动曝光，HDMI 左上角显示 `EXP:A`；手动档中 `EXP:3` 用于暗光。蜂鸣器使用 C12，是否发声由板载 SW5 控制。原参考约束占用的以太网 TX_EN/R10 和 TXD0/R11 已释放。这些功能均不依赖 Xilinx IP；必须在安路 TD 中打开 `td_project/camera_to_dsi_display.al` 后，以该工程的 IP 和约束完成综合、布局布线与下载验证。

## 历史文档

仓库初始规划和第一版迁移说明已整理到 `docs/archive/`，同时保留对应 Git 提交号，便于回看和对照。

