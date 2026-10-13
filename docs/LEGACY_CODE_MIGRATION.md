# 旧工程完整代码迁移台账

旧工程位置：`ATLE0200P_1118/ATLE0200P_1118/ATLE0200P_1118`。

本台账以旧 Vivado 工程 `ATLE0200P.xpr` 的 `sources_1` 和 Block Design 依赖为准，而不是把缓存、仿真网表和生成目录当作业务源代码。`WZY` 分支不删除旧算法；可综合的器件无关 RTL 已复制到当前 TD 工程，旧板专用功能由目标板的 SC520/MIPI/DDR/HDMI 链路替代。

## 已完整带入 TD 工程的独立 RTL

位置：`reference_edge_project/user_source/hdl_source/legacy_port/`，已加入 `camera_to_dsi_display.al`。

| 原模块 | 当前文件 | 状态 |
| --- | --- | --- |
| `rgb_analyze`、`crc18/24/30/36_rgb` | `rgb_analyze.v` | 保留完整时序测量、纯色、CRC、高度和错误计数算法；不再带 AXI-Lite 包装。 |
| `video_data_sw` | `video_data_sw.v` | 保留四路总线选择逻辑；当前单摄像头链路未例化。 |
| `a2b`、`debounce`、`delay_rdy` | `rtl/` | 原样迁移。 |
| `flash_mux_3`、`freq_test_value` | `rtl/` | 原样迁移。 |
| `hs_gen`、`vs_gen`、`mux2`、`para`、`portadd` | `rtl/` | 原样迁移。 |
| `lvds_data` | `rtl/` | 原样保留为并行 LVDS 数据解析逻辑；HX1P35A 参考板没有对应 LVDS 输入，未接入顶层。 |
| `yuv_rgb` | `rtl/` | 原样迁移；显示链路另有已接入的 RGB/YUV 适配版本。 |

## 已在当前功能中替代的旧模块

| 旧工程能力 | HX1P35A 实现 |
| --- | --- |
| LVDS 摄像头采集与解串 | SC520 MIPI CSI-2 + 安路 MIPI D-PHY RX。 |
| Xilinx MIG DDR3 | 参考工程 `ph1p35_324_ddr_wrapper`。 |
| 旧 RGB/YUV IP | `hx_pixel_stream_adapter.v`。 |
| 视频分析/显示 OSD | `hx_vision_pipeline.v`。 |
| 原按键控制 | `hx_button_mode_ctrl.v`。 |
| Xilinx Clock Wizard | 安路 TD 的 PLL IP。 |

## 不能原样迁移的旧板专用代码

这些文件不是普通 Verilog 算法，依赖旧 Kintex-7 硬核、收发器、物理管脚或 Vivado Block Design，HX1P35A 参考板也没有相应外设。因此不能通过复制代码获得可运行功能。

| 原部分 | 原因 | 目标处理 |
| --- | --- | --- |
| `ATLE0200P.v`、`ATLE0200P_BD` | 顶层绑定旧板全部 I/O 和 Vivado BD。 | 改用 `design_top_wrapper.v`。 |
| 4 路 `lvds_1to7`、LVDS I2C | 板上没有 LVDS 接收器与对应接口。 | 已由单路 SC520 MIPI 替代。 |
| MIG 7-series DDR3 | Xilinx 专有 DDR PHY/校准逻辑。 | 使用安路参考 DDR 控制器。 |
| 10G SFP、TCP_10G、GTX/GTH、DP/eDP | HX1P35A 参考板无 10G/DP 高速收发器及相关接口。 | 无硬件等价物，需更换底板才能实现。 |
| MicroBlaze、AXI Interconnect、XADC、ILA/VIO | Xilinx 专有 IP 与软核系统。 | 改为纯 RTL 控制或安路调试 IP；没有直接二进制兼容路径。 |
| AXI-Lite 外壳 `rgb_analyze_axi` | 包含 Xilinx XPM CDC 和 AXI 控制面。 | 保留其内核 `rgb_analyze`；若需要寄存器配置，后续为安路重写轻量寄存器接口。 |

## 当前可运行链路

`SC520 → MIPI D-PHY → RAW10 解包 → ISP → DDR 帧缓存 → 视觉处理 → HDMI`

该链路已经具备原图、灰度、三色掩膜、3×3 Sobel、目标面积/包围框、OSD 和蜂鸣器告警。旧板的多路 LVDS、10G 网络和 DP 功能需要额外的同类硬件后才可继续恢复。
