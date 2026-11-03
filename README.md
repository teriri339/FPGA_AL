# 嵌入式大赛项目报告：基于安路 PH1P35A 的 MIPI 摄像头实时视觉系统

## 一、项目概述

本项目基于**安路科技 PH1P35A**（PH1P35MDG324 封装）FPGA 平台，实现了一套从 MIPI 摄像头采集、ISP 处理、DDR 帧缓存到 HDMI 实时输出的完整视觉系统，并在显示链路上叠加了纯 RTL 实现的实时图像处理算法流水线，包括：

- **轻量 Canny 边缘检测**（Gaussian → Sobel → 四方向 NMS → 双阈值滞后连接 → 形态学加粗）
- **三原色目标检测**（红/绿/蓝通道饱和度分析 + 空间一致性过滤 + 包围框跟踪）
- **模板 SAD 跟踪**（64×64 模板、stride-2 粗搜 + stride-1 精搜、α-β 运动预测、多级重捕获）
- **闭环自动曝光**（全帧稀疏采样测光 + 高光保护 + 50Hz 防频闪）
- **白场校准与镜头阴影校正**（LSC）
- **HDMI OSD 信息叠加**（模式/曝光/目标坐标/状态条/安路 Logo）

**目标分辨率**：1280×720@60fps（720p60）
**摄像头**：思特威 SC520CS（RAW10, 2-Lane MIPI CSI-2, 828 Mbps/Lane）
**显示输出**：HDMI 1.4（TMDS, 74.25 MHz 像素时钟）
**开发工具**：Tang Dynasty 6.2（综合/布局布线）+ ModelSim 10.5b（仿真）

---

## 二、硬件平台

### 2.1 FPGA 芯片

| 项目 | 参数 |
|------|------|
| 芯片型号 | 安路 PH1P35MDG324 |
| 工艺/密度 | 28nm, 21226 逻辑单元 (SLICE) |
| BRAM | 39 组 ERAM |
| DSP | 23 个 |
| 封装 | 324-pin BGA |
| 外部存储 | DDR2 SDRAM（通过 PH1P DDR PHY 接口） |

### 2.2 外设连接

| 外设 | 接口 | FPGA 引脚 |
|------|------|-----------|
| SC520CS 摄像头 | MIPI CSI-2 D-PHY (2-Lane) | MIPI DPHY0 硬核 Pad (K3/J3/L3/L2) |
| HDMI 输出 | TMDS (4 对差分) | G16/F17/H14/C17 |
| 板载按键 | KEY1 复位, KEY2 模式切换, KEY3 曝光切换 | D5/A9/B9 |
| 蜂鸣器 | 无源蜂鸣器 (约 2kHz 方波驱动) | C12 |
| 板载开关 | SW5 控制蜂鸣器通断 | 硬件开关 |
| DDR2 | 16-bit 数据总线 | DDR PHY 硬核引脚 |
| 系统时钟 | 50 MHz 单端晶振 | 系统时钟管脚 |

### 2.3 时钟架构

由板载 50 MHz 晶振经 PH1P PHY PLL 生成全局时钟：

| 时钟域 | 频率 | 用途 |
|--------|------|------|
| `pll_clk_100m` | 100 MHz | MIPI D-PHY LP 时钟、DDR APB |
| `pll_clk_24m` | 23.81 MHz | 摄像头 MCLK、I2C 配置、AE 逻辑 |
| `HDMI_PIXEL_CLK` | 74.25 MHz | HDMI VTC、视频输出、视觉流水线 |
| `HDMI_SERIAL_CLK` | 1485 MHz | HDMI TMDS 串行器 |
| `MIPI_RX_BYTE_CLK` | ~207.5 MHz | CSI 解包、RAW10 解码、ISP |
| `usr_clk` (DDR) | 133.33 MHz | DDR 控制器用户接口 |

各时钟域之间使用 `hx_reset_release` 模块做异步复位同步释放，跨域数据传递使用两级同步器或握手协议。

---

## 三、系统架构

### 3.1 数据流总览

```
SC520CS 摄像头
    │  MIPI CSI-2 (2-Lane, 828 Mbps/Lane, RAW10)
    ▼
MIPI D-PHY RX (PH1P 硬核)
    │  HS 16-bit @ byte_clk
    ▼
CSI-2 解包 (csi_unpacket_2lane)
    │  帧/行/有效 + 32-bit payload
    ▼
RAW10 解包 (raw10_unpacket_2lane)
    │  40-bit RAW10 像素流
    ▼
AXI-Stream 打包 (uial2axis)
    │  AXI4-Stream tdata[39:0] / tvalid / tuser / tlast
    ▼
ISP 处理 (isp_top)
    │  BLC → Demosaic → AWB → 96→128 位宽转换
    │  输出: AXI4-Stream tdata[127:0] (RGB888 × 4 像素打包)
    ▼
Video In → DDR 帧缓存 (video_in + mc_to_user_interface + DDR2)
    │  写入 DDR2 帧缓冲区 (128-bit bus)
    ▼
Video Out ← DDR 读帧 (video_out)
    │  按 HDMI VTC 时序读出 RGB888 像素
    ▼
hx_pixel_stream_adapter (白场校准 / LSC / 直通)
    │  校正后 RGB888 + 同步信号
    ▼
hx_vision_pipeline (视觉算法核心)
    │  灰度转换 → Gaussian 平滑 → Sobel → NMS → 双阈值 Canny
    │  颜色目标检测 → 空间过滤 → 包围框
    │  模板 SAD 跟踪 → 运动预测 → 显示平滑
    │  RAW 锐化 / 灰度轮廓 / OSD 叠加
    │  帧级测光统计 (亮度/高光/暗部)
    ▼
hdmi_mixer (混合器 + 时序对齐)
    │
    ▼
hdmi_tx (HDMI 1.4 发射器)
    │  TMDS 串行
    ▼
HDMI 显示器
```

### 3.2 模块层次

```
design_top_wrapper (顶层)
├── PLL                    — 全局时钟生成
├── hx_reset_release ×5    — 各时钟域复位同步
├── ae_set                 — 自动曝光状态机 (24 MHz 域)
├── uicfgcs520             — SC520 I2C 寄存器配置 (24 MHz 域)
├── hx_sensor_applied_cdc  — 曝光/增益值跨域握手快照
├── mipi_dphy_rx           — MIPI D-PHY 接收硬核
├── csi_unpacket_2lane     — CSI-2 协议解包
├── raw10_unpacket_2lane   — RAW10 → 像素流
├── uial2axis              — 像素流 → AXI-Stream
├── isp_top                — ISP 处理链
│   ├── BLC                — 黑电平校正
│   ├── demosaic           — 拜耳插值 (双线性)
│   ├── AWB                — 自动白平衡
│   └── data96_128         — 位宽转换
├── video_in               — 帧写入 DDR
├── video_out              — 帧读出 DDR
├── mc_to_user_interface   — DDR 用户接口桥
├── ph1p35_324_ddr_wrapper — DDR2 控制器 + PHY
├── uivtc                  — 视频 timing 控制器 (1280×720@60)
├── hx_button_mode_ctrl    — 按键消抖 + 模式/曝光控制
├── hx_pixel_stream_adapter — 白场校准 / LSC
├── hx_vision_pipeline     — 视觉算法核心 ← 【本项目核心创新】
│   ├── 灰度转换 + Gaussian 平滑
│   ├── Sobel + 四方向 NMS + 双阈值滞后连接
│   ├── 形态学加粗 + 连续性去噪
│   ├── 三原色目标检测 + 空间一致性
│   ├── hx_template_tracker — 模板 SAD 跟踪
│   ├── RAW 锐化
│   ├── 测光统计 (亮度/高光/暗部)
│   └── OSD 叠加 (状态条/模式/坐标/Logo)
├── hdmi_mixer             — HDMI 输出混合器
└── hdmi_tx                — HDMI 1.4 物理层
```

---

## 四、核心算法实现

### 4.1 轻量 Canny 边缘检测

在不使用外部处理器的情况下，用纯 RTL 实现了适合 720p60 实时处理的轻量 Canny 流水线：

**处理链**：`Gaussian 3×3 → Sobel 3×3 → 四方向 NMS → 双阈值滞后连接 → 2×2 形态学加粗`

| 步骤 | 实现要点 |
|------|----------|
| Gaussian 平滑 | 1-2-1 / 2-4-2 / 1-2-1 加权核，移位加法 + 右移归一化，无除法器 |
| Sobel 梯度 | 标准 Gx/Gy 3×3 算子，输出 12-bit 幅值 |
| 四方向 NMS | 按 Gx/Gy 主方向量化为 0°/45°/90°/135°，沿梯度方向保留局部极大值 |
| 双阈值连接 | 强边缘直接保留；弱边缘仅在 8 邻域存在强边缘时保留，防止纹理链扩散 |
| 局部门限 | 按局部平滑亮度逐像素选择弱/强门限，同一画面可同时保留暗墙和亮窗边缘 |
| 形态学加粗 | 2×2 受控膨胀，线条加粗约 1 像素，增强短断点可见度 |

**资源使用**：Canny 全链路约占用 3000+ LUT6，使用 2 组 ERAM 行缓存（合并 Gaussian/Sobel/NMS/Hyst 状态为 46-bit），0 DSP。

### 4.2 三原色目标检测

| 特性 | 实现 |
|------|------|
| 颜色判据 | R/G/B 主通道饱和度 + 通道间差值门限，红蓝严格(亮度≥96, 差≥40)，绿色宽松(亮度≥64, 差≥16) |
| 空间一致性 | 当前像素须与左/上/左上三个邻居中至少两个颜色一致，过滤孤立色噪点 |
| 帧级统计 | 逐帧统计红/绿/蓝目标像素数，超过阈值时输出 `target_found` |
| 包围框 | 实时计算目标像素的最小外接矩形，HDMI 上叠加黄色框 |
| 保持机制 | 连续 10 帧无目标后释放锁定，防止目标短暂遮挡时丢失 |
| 告警 | 目标首次出现时蜂鸣器播放 1 秒 2kHz 方波，持续存在不重复触发 |

### 4.3 模板 SAD 跟踪

完全纯 RTL 实现的块匹配目标跟踪器，不依赖 DDR，全部使用片上 ERAM：

| 特性 | 实现 |
|------|------|
| 模板尺寸 | 64×64 像素 |
| 搜索策略 | stride-2 粗搜 (±8 像素) → stride-1 精搜 (±2 像素)，总搜索范围 ±10 |
| 匹配准则 | 零均值 SAD（先减模板均值再做绝对差累加），抑制全局亮度漂移 |
| 纹理门限 | 模板纹理量 < 384 时拒绝锁定，避免平坦区域误跟踪 |
| 唯一性 | 最佳/次佳 SAD 比值 < 64 时拒绝更新，避免多峰歧义 |
| 运动预测 | α-β 滤波器（位置 α=1, 速度 β=1/2 Q4 定点），同方向运动平滑，停止/反转立即响应 |
| 保持机制 | 连续 16 帧匹配失败进入 HOLD，使用最后的速度预测保持跟踪；第 17 帧仍失败进入 LOST |
| 多级重捕获 | LOST 后依次尝试：当前位置恢复 → 扩大范围 → 远距搜索 → 全局搜索 → 快速重捕获 |
| 显示平滑 | 搜索中心每帧直接跳到 SAD 峰值；显示坐标一阶低通 + 2 像素死区，消除跟踪框抖动 |

**资源使用**：约 800 LUT6，3 组 ERAM（模板缓存 + 搜索行缓存 + 参考行缓存），0 DSP。

### 4.4 闭环自动曝光

| 特性 | 实现 |
|------|------|
| 测光 | HDMI 像素域每 16 行 × 16 列抽样，3600 个样点全帧平均亮度 |
| 跨域传递 | 稳定总线 + 逐帧翻转标志，从 74.25 MHz 域到 24 MHz 域 |
| 亮度目标 | 96~160 死区，超出时每 16 帧调节一次 |
| 高光保护 | 逐通道过曝检测：max(R,G,B) ≥ 250 且灰度 ≥ 180 时计数为高光；高光超过 25% 且全局亮度 ≥ 128 时优先降曝光 |
| 暗部保护 | 深暗样点(灰度 ≤ 48)统计，暗部面积大时优先增亮，不受高光保护限制 |
| 防频闪 | 50Hz 市电下曝光上限锁到 10ms (1200 半行)，避免卷帘快门横向条带 |
| 调节策略 | 暗时先增曝光后增增益；亮时先降增益后缩曝光 |
| 手动档位 | KEY3 循环：AUTO → EXP0(600) → EXP1(1200) → EXP2(1990) → EXP3(1990+16x) → AUTO |
| 上电默认 | AUTO 模式，自动根据画面亮度闭环调节 |

### 4.5 白场校准与镜头阴影校正 (LSC)

| 特性 | 实现 |
|------|------|
| 软预设 | 预存的 `white_field_soft_preset.mem` LUT，上电即加载，无需标定过程 |
| 在线标定 | 可选的 `hx_white_field_calibrator`，按键触发后采集一帧白场，计算逐网格增益 |
| 增益应用 | `hx_white_field_lsc` 按 16×16 网格地址读取增益，双线性插值校正 RGB888 |
| 黑电平 | 可选的 `LSC_BLACK_LEVEL` 参数，校准时先减黑电平再除增益 |

### 4.6 显示模式与 OSD

KEY2 短按循环切换 5 种显示模式：

| 模式编号 | 名称 | 显示内容 |
|----------|------|----------|
| 0 | RAW | 原始 RGB 彩色（可选锐化增强） |
| 1 | GRAY | BT.601 灰度 + 灰度等高线轮廓 |
| 2 | COLOR | 半亮原图 + 红/绿/蓝命中像素着色 + 目标包围框 |
| 3 | CANNY | 黑底白边 Canny 边缘检测图 |
| 4 | GRAD | Sobel 梯度幅值灰阶（连续灰阶，非二值化） |

OSD 叠加（不进入视觉统计）：
- 左上角：模式名称、曝光档位(AUTO/EXP0~3)、目标坐标与面积
- 右上角：安路 Logo（ROM 点阵）
- 目标包围框：黄色矩形，仅在 COLOR 模式绘制
- 模板跟踪框：青色矩形，跟踪激活时显示（RAW/GRAY/COLOR 模式下可见）

---

## 五、工程文件结构

### 5.1 目录总览

```
FPGA_AL/
├── reference_edge_project/     ← Tang Dynasty 工程（核心）
│   ├── td_project/             ← TD 工程文件 (.al / .sdc)
│   └── user_source/
│       ├── constraints_source/ ← 引脚约束 (pin.adc) + 时序约束 (timing.sdc)
│       └── hdl_source/         ← 全部 RTL 源码
│           ├── design_top_wrapper.v        ← 顶层
│           ├── hx1p35_port/               ← 【自研视觉算法模块】
│           │   ├── hx_vision_pipeline.v      (1352 行) 视觉流水线核心
│           │   ├── hx_template_tracker.v     (765 行)  模板 SAD 跟踪
│           │   ├── hx_pixel_stream_adapter.v (558 行)  白场/LSC 适配
│           │   ├── hx_button_mode_ctrl.v     (115 行)  按键控制
│           │   ├── hx_anlogic_logo_rom.v     (299 行)  安路 Logo ROM
│           │   ├── anlogic_logo_rom.v        (6400 行) Logo 点阵数据
│           │   └── white_field_soft_preset.* ← LSC 预设 LUT
│           ├── isp/             ← ISP 处理链 (BLC/Demosaic/AWB)
│           ├── uiisp_beta/     ← 自动曝光 (ae_set.v)
│           ├── uics520_cfg/    ← SC520 摄像头 I2C 配置
│           ├── mipi_dphy_rx/   ← MIPI D-PHY 接收
│           ├── ph1p35_ddr/     ← DDR2 控制器 + PHY
│           ├── legacy_port/    ← 旧板 RGB/YUV/时序模块
│           ├── hdmi_tx.v       ← HDMI 发射器
│           ├── hdmi_mixer.v    ← HDMI 混合器
│           └── ...
├── tests/                      ← ModelSim 仿真 (25 个 testbench)
├── docs/                       ← 设计文档
├── constraints/                ← 约束模板
├── src/                        ← 早期平台无关 stub (已被取代)
├── tools/                      ← 测试脚本
├── references/                 ← 外部参考仓库 (9 个 submodule)
├── MIGRATION_CHANGELOG.md      ← 迁移改动详细记录
└── README.md
```

### 5.2 自研核心模块代码量

| 模块 | 行数 | 功能 |
|------|------|------|
| `hx_vision_pipeline.v` | 1352 | 视觉算法流水线总成 |
| `hx_template_tracker.v` | 765 | 模板 SAD 跟踪器 |
| `hx_pixel_stream_adapter.v` | 558 | 白场/LSC 适配层 |
| `anlogic_logo_rom.v` | 6400 | Logo 点阵 ROM |
| `hx_anlogic_logo_rom.v` | 299 | Logo ROM 控制器 |
| `hx_button_mode_ctrl.v` | 115 | 按键消抖/模式控制 |
| `design_top_wrapper.v` | 979 | 系统顶层 |
| `ae_set.v` | 181 | 自动曝光状态机 |
| **合计** | **10649** | |

### 5.3 仿真测试

共 25 个 SystemVerilog testbench，覆盖：

| 类别 | 用例数 | 代表用例 |
|------|--------|----------|
| 模板跟踪 | 10 | reacquire (多级重捕获)、overlay (端到端像素比对)、display_smooth (抖动抑制) |
| 颜色目标 | 3 | target_tracking、gray_contours_tracking、adaptive_tracking |
| 边缘检测 | 3 | canny_noise、vision_edge_modes、picture_quality |
| 自动曝光 | 3 | ae_anti_flicker (防频闪)、picture_ae、ae_cdc_coherency |
| 显示/OSD | 3 | logo_osd、display_mode_cycle、alpha_guard |
| 其他 | 3 | raw_sharpen、motion_prediction、motion_stress |

仿真环境：ModelSim 10.5b + 自研 `ph1p_logic_eram_stub.v`（安路 ERAM 行为模型），无需安装 Tang Dynasty 即可运行流水线级仿真。

---

## 六、技术亮点

### 6.1 纯 RTL 视觉流水线

所有图像处理算法完全用 Verilog 实现，不使用 MicroBlaze 软核、不使用 AXI DMA、不依赖外部处理器。从 Gaussian 平滑到模板跟踪，全部在 74.25 MHz 像素时钟域内逐像素流水完成，每帧处理延迟仅 4 个时钟周期。

### 6.2 ERAM 行缓存合并技术

使用安路 `PH1P_LOGIC_ERAM` 原语（双端口、REGMODE="NOREG" 异步读 + clka 反相时钟）实现行缓存。将 Gaussian、Sobel/NMS、双阈值滞后三个阶段的状态合并为一组 46-bit 行缓存，相比三个独立行缓存节省约 30% ERAM 资源。

### 6.3 局部自适应门限

Canny 边缘检测不使用整帧统一门限，而是按逐像素的局部平滑亮度选择弱/强门限。同一画面中暗墙板缝(门限 44/80)和亮窗边缘(门限 96/176)可同时保留，解决高反差场景细节丢失问题。

### 6.4 α-β 运动预测跟踪

模板跟踪器实现了 Q4 定点的 α-β 滤波器：位置更新 α=1（直接采用 SAD 峰值），速度更新 β=1/2。同方向运动做平滑以减少帧间噪声，停止或反转时立即响应。LOST 状态下使用最后的速度预测保持跟踪，实现短暂遮挡后的无缝恢复。

### 6.5 防频闪自动曝光

针对 SC520 卷帘快门在 50Hz LED 照明下的横向条带问题，将曝光上限锁定为 10ms 纹波周期的整数倍（1200 半行）。代价仅 0.73 EV 进光量，由模拟增益补偿。

### 6.6 逐通道过曝检测

传统 BT.601 灰度判据 `gray ≥ 245` 会漏判单通道削顶（如暖光 R=255,G=200,B=180 灰度仅 214）。本系统改为检测 max(R,G,B) ≥ 250 且 gray ≥ 180 的双条件，同时用灰度门限排除大面积饱和色物体（如纯红花 gray=90）的误判。

---

## 七、综合与实现结果

使用 Tang Dynasty 6.2.168116 综合实现，最近一次完整版本结果：

| 指标 | 结果 |
|------|------|
| Setup WNS | 0.323 ns |
| Hold WNS | 0.020 ns |
| 违规端点 | 0 |
| SLICE 使用 | 15853 / 21226 (74.72%) |
| ERAM 使用 | 39 / 39 (100%) |
| DSP 使用 | 23 / 23 (100%) |

> 注：最近新增的防频闪 AE、逐通道过曝检测、跟踪框平滑等改动已通过仿真验证，但尚未完成实机综合和上板测试。

---

## 八、按键操作说明

| 按键 | 短按 | 长按 (>1s) |
|------|------|------------|
| KEY1 (D5) | 系统复位（低有效） | — |
| KEY2 (A9) | 切换显示模式 (RAW→GRAY→COLOR→CANNY→GRAD→RAW) | 切换 RAW 锐化开关 |
| KEY3 (B9) | 循环曝光档位 (AUTO→EXP0→EXP1→EXP2→EXP3→AUTO) | 模板跟踪锁定/取消（跟踪使能时） |
| SW5 | 蜂鸣器通断（硬件开关） | — |

---

## 九、迁移历程

本项目从米尔康 (MiLianKe) 基于 Xilinx Zynq 的 SC500 参考工程迁移至安路 PH1P35A 平台，主要工作包括：

1. **平台替换**：Xilinx Zynq PS/MicroBlaze → 安路 PH1P35A 纯 FPGA
2. **摄像头升级**：SC500 → SC520CS（MIPI CSI-2 替代并行 DVP）
3. **DDR 替换**：Xilinx MIG 7-series → 安路 PH1P DDR2 PHY
4. **显示接口**：保留 HDMI TMDS，替换安路 HDMI TX IP
5. **算法移植**：RGB→YUV→RGB 往返 → 直通 RGB888 + 自研视觉流水线
6. **引脚重映射**：按 HX1P35A 开发板手册全面复核引脚
7. **自研功能**：Canny 边缘、颜色检测、模板跟踪、闭环 AE、防频闪、LSC

详细记录见 `MIGRATION_CHANGELOG.md`。

---

## 十、参考来源

- 安路科技 PH1P35A 数据手册与 Tang Dynasty 工具链
- 米尔康 SC500/SC520 MIPI 摄像头参考工程 (`references/05_isp/zynqmp_cam_isp_demo`)
- 开源 FPGA 视觉项目（`references/` 下 9 个 submodule，涵盖 JPEG/QOI/Sobel/Camera Pipeline 等）
- 模板 SAD 匹配的连续调度策略参考 Yiğit Bektaş Gürsoy 的 MIT 许可 Motion_Estimation_Hardware_Verilog，但搜索/同步逻辑为独立实现

---

*文档生成日期：2026-11-03*
*工程版本：最新 HEAD（含防频闪 AE + 逐通道过曝检测 + 跟踪框平滑，仿真已验证，待上板）*
