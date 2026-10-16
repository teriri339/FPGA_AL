# FPGA_AL：PH1P35A 实时视觉与边缘检测工程

> 当前有效分支：`WZY`
>
> 当前功能/资源基线：`a7676fb`（`perf: move vision line buffers to ERAM`）
>
> 可回退标签：`checkpoint-20261016-eram-linebuffers`
> 工程状态：完整综合、布局布线和静态时序已经通过；最新位流仍应在实板上回归检查所有显示模式、自动曝光、按键和蜂鸣器。

这是基于安路 PH1P35A 的 SC520 MIPI 摄像头实时视觉工程。工程在参考的摄像头、ISP、DDR 帧缓存和 HDMI 输出链路上，加入了纯 RTL 的原图/灰度/颜色识别/Canny 边缘检测、自动曝光、OSD、按键控制和蜂鸣器告警。

`RAW` 显示模式的含义是“绕过本工程视觉算法的 RGB 原图”。它**不是**传感器 Bayer RAW10：画面已依次经过 SC520、MIPI、RAW10 解包、demosaic/ISP 和 DDR 帧缓存。因此 RAW 模式中观察到的颜色偏差可用于区分摄像头/ISP 问题与后级算法问题。

## 当前版本摘要

最新版本保留全部功能模式，没有通过隐藏模式或删除旧源码来节省逻辑资源。资源优化来自两项等价实现替换：

1. 将显示侧无必要的 RGB → YUV → RGB 往返替换为 RGB888 直通；
2. 将视觉流水线的长行缓存由分布式 LUT RAM 迁移到片上 ERAM，并增加必要的流水线对齐。

| 项目 | 原始基线 | RGB 直通版 | 当前 ERAM 行缓存版 |
| --- | ---: | ---: | ---: |
| Slice | 15905 / 21216（74.97%） | 15787（74.41%） | **13810（65.09%）** |
| LUT6 | 13725 / 21216（64.69%） | 13546（63.85%） | **11437（53.91%）** |
| 寄存器 | 14341（33.80%） | 14274（33.64%） | **14246（33.57%）** |
| 分布式 RAM LUT | — | 1936 | **296** |
| ERAM | 39 / 108（36.11%） | 39（36.11%） | **47（43.52%）** |
| DSP | 23 / 40（57.50%） | 11（27.50%） | **11（27.50%）** |
| Setup WNS | +0.309 ns | +0.228 ns | **+0.256 ns** |
| Hold WNS | +0.021 ns | +0.020 ns | **+0.020 ns** |

当前 ERAM 构建的其他资源占用：IO `58 / 160`（36.25%）、DDR Byte `6 / 12`（50%）、MIPI RX `1 / 2`（50%）、PLL `3 / 6`（50%）、GCLK `9 / 32`（28.12%）。

当前版本的资源结论：相对原始基线，Slice 降至 65.09%，LUT6 降至 53.91%，DSP 从 23 个降至 11 个；ERAM 增加 8 个，但仍剩余 61 个。完整对比和实现结论见 [RESOURCE_OPT_NOTES.md](RESOURCE_OPT_NOTES.md)。

## 工程与目标器件配置

| 项目 | 当前配置 |
| --- | --- |
| FPGA | Anlogic PH1P35MDG324，速度等级 `-3` |
| 开发工具 | Tang Dynasty `6.2.168116` |
| TD 工程 | `reference_edge_project/td_project/camera_to_dsi_display.al` |
| 顶层模块 | `design_top_wrapper` |
| 摄像头 | SC520 / SC520CS |
| 摄像头输入 | MIPI CSI-2、2 Lane、RAW10、1280×720 @ 60 fps、828 Mbps/Lane |
| 显示输出 | HDMI RGB888；VTC 配置为 1280×720、总计数 1650×750，目标为 720p60。 |
| 主输入时钟约束 | `I_sys_clk`：50 MHz（见 `camera_to_dsi_display.sdc`） |
| HDMI 像素时钟 | VTC / 蜂鸣器分频按 720p60 的名义 `74.25 MHz` 编写；当前 ERAM 版本机构建的已布线报告为 `75.002 MHz`，需以显示器与示波器继续确认实际帧率和 PLL 配置。 |
| MIPI 接收时钟约束 | `IO_rx_clk_pad_p`：4.167 ns（见 SDC） |
| 启动配置 | `mspix4`，位流压缩已开启 |

TD 工程中的完整源码、IP、管脚及约束已经列入 `.al` 文件；不要仅综合根目录 `src/` 下的早期样例。

`camera_to_dsi_display.sdc` 对 `I_sys_clk` 施加 50 MHz 约束、对 MIPI 接收 pad 施加 4.167 ns 约束，并由工具派生 24 MHz、MIPI byte、HDMI pixel/serial 等时钟；HDMI 像素域到 24 MHz 摄像头配置域已显式声明为跨域例外。修改 PLL、MIPI 或曝光跨域逻辑时，应同步复查该 SDC，而不是只修改 RTL。

## 实际硬件处理链路

```text
SC520
  → MIPI D-PHY RX（2 Lane）
  → RAW10 解包
  → ISP / demosaic / 图像校正
  → 128-bit 视频打包
  → DDR 帧缓存
  → RGB888 直通适配
  → hx_vision_pipeline
  → HDMI mixer / HDMI TX
```

`hx_vision_pipeline` 位于 DDR 读出和 HDMI mixer 之间；它不会修改 MIPI、DDR 或 HDMI IP 的底层接口。

## 当前功能

### 显示模式

按 KEY2 循环切换，共四种模式：

| 模式 | OSD 名称 | 效果 |
| --- | --- | --- |
| `0` | `RAW` | ISP 和 DDR 输出后的 RGB 原图；不执行视觉模式着色。 |
| `1` | `GRAY` | 8-bit 灰度显示。 |
| `2` | `COLOR` | 红、绿、蓝目标以纯色高亮，未命中区域保留半亮原图；目标框只在该模式显示。 |
| `3` | `CANNY` | 带 Gaussian、Sobel、NMS 和双阈值连接的流式 Canny 风格边缘输出。 |

### 颜色目标检测和 OSD

- 检测红、绿、蓝三种颜色，使用亮度、通道差和同色邻域一致性三级筛选；绿色门限针对偏暗或偏黄绿印刷物额外放宽。
- 只有连续成片的颜色候选才进入面积、包围框和告警统计；默认最小目标面积为 `800` 像素。
- 左上角状态文字 OSD（模式、曝光、目标主颜色、中心坐标和像素面积）默认关闭，避免遮挡画面；`hx_vision_pipeline` 的 `ENABLE_STATUS_OSD` 参数设为 `1` 才会恢复显示。COLOR 模式的黄色目标框不受此开关影响。
- 当前代码**尚未实现 FPS OSD**；后续加入前不要把屏幕上的信息误认为帧率。

### Canny 风格边缘检测

边缘模式执行下列流式处理：

```text
RGB 灰度化
  → 3×3 Gaussian（1-2-1）平滑
  → Sobel 梯度与 0°/45°/90°/135°方向量化
  → 非极大值抑制（NMS）
  → 暗区/普通/亮区局部双阈值
  → 对称 8 邻域滞后连接
  → 孤立点抑制 + 单像素断点连接
  → 2×2 受控加粗显示
```

- 局部门限：弱门限 `40 / 60 / 64`，强门限 `72 / 96 / 112`（对应暗区 / 普通区 / 亮区）。
- 弱边必须邻接强边锚点，且邻域至少有两个弱候选；这可保留连续的衣纹、桌边和灯具轮廓，同时删除孤立白点。
- 仅在边缘两端至少一侧是强边时补一个像素间隙，避免把随机噪点扩大为轮廓。
- Gaussian、Sobel/NMS、滞后连接和加粗行缓存已打包为 PH1P35 的 8 个 ERAM，深度 2048，覆盖 1280 像素有效行。

### 自动/手动曝光

上电默认 `AUTO`。视觉流水线每隔 16 像素、16 行抽样一次（每帧 3600 个样点），统计平均亮度、近饱和高光和深暗区域；统计结果跨时钟域送回 24 MHz 摄像头配置域。

| 项目 | 当前值 |
| --- | ---: |
| 平均亮度稳定区间 | 96 ～ 160 |
| 高光统计阈值 | 灰度 ≥ 245 |
| 暗部统计阈值 | 灰度 ≤ 48 |
| 高光保持 / 温和降曝光 / 强降曝光 | 120 / 300 / 720 个抽样点 |
| 暗部保护阈值 | 1800 个抽样点 |
| 普通调整周期 | 每 16 帧一次 |
| 严重高光调整周期 | 每 8 帧一次 |
| 自动曝光范围 | 曝光 300 ～ 1990；增益 16 ～ 176 |

自动模式优先保护主体暗部，不会因少量灯管、窗口或反光区域立即压低整幅曝光；这不是 HDR，强逆光场景仍需要在高光与暗部之间折中。

手动档位参数如下：

| 档位 | 曝光寄存器值 | 增益寄存器值 | 用途 |
| --- | ---: | ---: | --- |
| `EXP:0` | 600 | 16 | 较亮环境 |
| `EXP:1` | 1200 | 48 | 中等亮度 |
| `EXP:2` | 1990 | 80 | 默认高曝光 |
| `EXP:3` | 1990 | 144 | 暗光环境 |

### 按键、蜂鸣器与管脚

| 硬件 | 管脚 | 当前作用 |
| --- | --- | --- |
| KEY1 | `D5` | 低有效系统复位。 |
| KEY2 | `A9` | 低有效；切换 `RAW → GRAY → COLOR → CANNY → RAW`。 |
| KEY3 | `B9` | 低有效；切换 `AUTO → EXP:0 → EXP:1 → EXP:2 → EXP:3 → AUTO`。 |
| 蜂鸣器 | `C12` | 目标由“未检测到”变为“检测到”时，输出约 2 kHz 方波约 1 秒；目标持续存在不会重复触发。 |
| 摄像头 I²C | `K3` / `J3` | `O_cam_scl` / `IO_cam_sda`。 |
| 摄像头 24 MHz / 复位 | `L3` / `L2` | `O_cam_24m` / `O_cam_rst`。 |
| HDMI TMDS + | `G16` / `F17` / `H14` / `C17` | CH0 / CH1 / CH2 / CLK。 |

按键经两级同步和约 10 ms 消抖；默认目标告警使能为开。

> 注意：历史说明中写过“SW5 控制蜂鸣器”，但当前顶层端口、`pin.adc` 和 RTL **没有 SW5 输入映射**。`O_alarm_enable` 上电后固定为使能。因此，当前提交中 SW5 不能实际静音蜂鸣器；若需要该功能，必须新增 SW5 顶层输入、ADC 管脚约束并接入 `S_alarm_enable`，而不是只修改说明文字。

完整 MIPI、DDR 和其余板级管脚请以 `reference_edge_project/user_source/constraints_source/pin.adc` 为唯一准则。

## 关键文件导航

| 文件或目录 | 用途 |
| --- | --- |
| `reference_edge_project/td_project/camera_to_dsi_display.al` | Tang Dynasty 工程入口、文件列表、顶层、目标器件、IP 和运行配置。 |
| `reference_edge_project/td_project/camera_to_dsi_display.sdc` | 主时钟、MIPI 时钟、派生时钟、异步时钟组和跨时钟域例外。 |
| `reference_edge_project/user_source/constraints_source/pin.adc` | 当前有效管脚约束。 |
| `reference_edge_project/user_source/hdl_source/design_top_wrapper.v` | 顶层；摄像头、MIPI、ISP、DDR、HDMI、按键、曝光和蜂鸣器集成。 |
| `reference_edge_project/user_source/hdl_source/hx1p35_port/hx_pixel_stream_adapter.v` | RGB888 直通适配；旧 RGB/YUV 公式仅保留作参考，不被实例化。 |
| `reference_edge_project/user_source/hdl_source/hx1p35_port/hx_vision_pipeline.v` | 四种显示模式、颜色检测、Canny、OSD、统计和 ERAM 行缓存。 |
| `reference_edge_project/user_source/hdl_source/hx1p35_port/hx_button_mode_ctrl.v` | KEY2/KEY3 同步、消抖、模式与曝光状态机。 |
| `reference_edge_project/user_source/hdl_source/uiisp_beta/ae_set.v` | 自动曝光、手动曝光、跨时钟域同步和 SC520 曝光/增益写入。 |
| `reference_edge_project/user_source/hdl_source/uics520_cfg/` | SC520 初始化、720p60 寄存器表、曝光和增益寄存器写入。 |
| `reference_edge_project/user_source/hdl_source/isp/` | RAW10 解包、demosaic、ISP 等参考链路模块。 |
| `reference_edge_project/user_source/hdl_source/ph1p35_ddr/` | DDR2 控制器及相关 IP。 |
| `src/` | 早期独立算法样例，不是当前 TD 工程的编译输入。 |
| `docs/` | 工程结构、迁移记录、版本检查点和历史文档。 |

## 构建与烧录

1. 使用 Tang Dynasty `6.2.168116` 打开 `reference_edge_project/td_project/camera_to_dsi_display.al`。
2. 确认目标器件为 `PH1P35MDG324-3`，顶层为 `design_top_wrapper`，约束集为 `constraint_1`。
3. 依次运行 `syn_1`（综合）和 `phy_1`（布局布线 / bitgen）。项目已开启 bit 压缩。
4. 生成后的标准位流通常位于：
   `reference_edge_project/td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit`。
5. 使用 Tang Dynasty 下载工具烧录后，依次验证 RAW、GRAY、COLOR、CANNY，随后验证 KEY3 曝光切换、颜色目标首次出现的蜂鸣器和 HDMI 稳定性。

`.al` 文件的 `Project Path` 是创建工程时写入的绝对本地路径。若克隆到其他目录后 Tang Dynasty 提示路径不存在，请在 TD 中重新选择当前 `td_project` 目录；源码、约束和 IP 条目本身均使用相对路径。

已核验的 ERAM 基线本机构建产物位于该构建副本的 `camera_to_dsi_display_Runs/best_result/`。它们未被 Git 跟踪，不会随克隆下载；下表仅用于确认获得的烧录文件是否正确。

| 文件 | SHA256 |
| --- | --- |
| `camera_to_dsi_display.bit` | `063248A6E5069E96B9ED1981A6DBFF525F58C1A99AA8F017906B5BD944AB9A46` |
| `camera_to_dsi_display_compress.bit` | `C9AE031A9E58D3A09474999EE76325E4BEFE07774F1F481EF1839D42D52108EF` |

请从相同提交重新构建，或使用项目维护者提供并经 SHA256 校验的烧录文件；不要把本地生成的 `.bit`、`*.area`、`*.timing` 当作仓库已提交内容。

## 验证状态与已知问题

| 项目 | 状态 |
| --- | --- |
| 综合、布局布线、bitgen | 本地 ERAM 基线构建已通过；Setup WNS `+0.256 ns`、Hold WNS `+0.020 ns`，0 个时序违规端点。 |
| RAW / GRAY / COLOR / CANNY 显示 | 已有实板画面；仍建议每次大改后完整回归。 |
| 自动曝光 | 已接入平均亮度、高光和暗部保护；强逆光仍不是 HDR。 |
| Canny 细节 | 已具备双阈值、8 邻域连接、去孤点和单像素补线；需按同场景继续调参。 |
| 摄像头中心偏绿、边缘偏紫红 | 当前 RAW 模式也可见，表现为平滑的空间色偏；优先怀疑摄像头镜头/ISP 的白平衡或 Lens Shading 校正，而非 Canny 或 ERAM。应使用均匀白墙、旋转摄像头和回退位流交叉确认。 |
| SW5 蜂鸣器开关 | 当前未接入 RTL / ADC，详见上方注意事项。 |
| FPS OSD | 当前未实现。 |
| HDMI 实际像素时钟 | 当前已布线报告是 `75.002 MHz`，与 720p60 名义 `74.25 MHz` 不一致；烧录后须用显示器状态、示波器或帧率测量确认。 |

## 版本管理与回退

- 日常开发分支：`WZY`。
- 当前性能检查点：`checkpoint-20261016-eram-linebuffers`。
- 当前性能提交：`a7676fb`。
- `main` 用于稳定基线，不直接覆盖。
- 需要验证历史版本时，优先新建临时分支，不要强制覆盖当前工作：

```bash
git switch -c verify-eram checkpoint-20261016-eram-linebuffers
```

完整版本检查点、较早 Canny/自动曝光候选版及各版位流校验值见 [docs/VERSION_CHECKPOINTS.md](docs/VERSION_CHECKPOINTS.md)。工程目录规则见 [docs/PROJECT_STRUCTURE.md](docs/PROJECT_STRUCTURE.md)。

## 克隆

```bash
git clone --branch WZY https://github.com/teriri339/FPGA_AL.git
```

如需同时获取外部参考仓库：

```bash
git clone --branch WZY --recurse-submodules https://github.com/teriri339/FPGA_AL.git
```

已克隆但参考目录为空时：

```bash
git submodule update --init --recursive
```
