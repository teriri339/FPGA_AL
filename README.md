# FPGA_AL：PH1P35A 实时视觉与边缘检测工程

最新独立发布：[时序 / CDC 修复 A](bitstreams/timing_closure_20261021_a/README.md)，烧录 `bitstreams/timing_closure_20261021_a/camera_timing_closure_20261021_a.bit`。经用户同意采用隔离 D 的复位/CDC/DDR 修复，223 个设计文件指纹与验证版一致，40 项仿真、Python 17 项通过。Setup/Hold WNS +0.116/+0.020 ns，STA 覆盖 98.49%，Slice 82.69%、ERAM 92/108、DSP 27/40。新生成位流，尚待上板验证；未覆盖历史文件或原运行数据库，未提交/推送。下面为历史发布记录。

最新独立发布：[快速找回资源优化 A](docs/TEMPLATE_FAST_RESOURCE_OPT.md)，烧录 `bitstreams/local_template_fast_resource_opt_20261020_a/camera_template_fast_resource_opt_20261020_a.bit`。保持原快速找回的精度、范围、门限及处理时延，40位快照打包和地址优化使 ERAM99→95、DSP29→27；Slice18239→18300（86.26%），是少量逻辑换存储余量。35项仿真配置、Python17项和隔离综合/路由通过；Setup/Hold WNS +0.136/+0.020ns，STA覆盖95.86%。新位流待上板，不增加缩放适应；原数据库、历史位流及best_result未覆盖，未提交/推送。下条为上一独立发布。

上一独立发布：[快速粗搜找回 A](docs/TEMPLATE_FAST_REACQUIRE.md)，烧录 `bitstreams/local_template_fast_reacquire_20261020_a/camera_template_fast_reacquire_20261020_a.bit`。320×180 冻结亮度快照粗搜候选、原分辨率精匹配三帧确认，保留近邻与慢速全画面兜底；720p 静态仿真约 0.617 秒恢复，不保证任意实景秒级，也不支持旋转/缩放。33项仿真配置、Python17项及隔离构建通过；Slice85.97%、ERAM99/108、DSP29/40，Setup/Hold WNS +0.252/+0.020ns，STA覆盖95.77%。实板待验收，旧位流及best_result未覆盖，未提交/推送。下条为上一独立发布。

上一独立发布：[低资源分片全画面找回](docs/TEMPLATE_GLOBAL_REACQUIRE.md)，烧录 `bitstreams/local_template_global_reacquire_20261020_a/camera_template_global_reacquire_20261020_a.bit`。前32次失败搜索保留原邻域优先，之后局部/全画面交替；720p共3234个全局窗口，完整轮询理想约108秒另加确认，不是秒级全画面检测，不支持旋转/缩放。26项仿真配置、Python17项及隔离综合/路由通过；Slice83.97%、ERAM71，Setup/Hold WNS=+0.179/+0.020ns，STA覆盖95.82%。新位流实板待验收，历史版本和best_result未覆盖，未提交/推送。

上一独立发布：[近邻优先的扩大找回](docs/TEMPLATE_FAR_REACQUIRE.md)，烧录 `bitstreams/local_template_far_reacquire_20261020_a/camera_template_far_reacquire_20261020_a.bit`。最后位置/中央各自名义约±73个处理像素，保留快速近邻优先、3帧确认，不是全画面或旋转缩放。完整远邻轮询576个失败搜索帧，60fps理想条件约9.6秒另加确认，不保证立即恢复。22项仿真配置、Python17项及隔离综合/路由通过；Slice84.03%、ERAM71，Setup/Hold WNS=+0.316/+0.020ns，STA覆盖95.77%。新位流实板待验收，历史位流保留。

上一独立发布：[功能保持的资源优化](docs/TEMPLATE_RESOURCE_OPT.md)，烧录 `bitstreams/local_template_resource_opt_20261020_a/camera_template_resource_opt_20261020_a.bit`。保留用户已验证扩展A全部功能/参数/时延，搜索块改用专用存储，Slice89.35%→84.36%（省1058）、LUT省1363、ERAM66→71。59011955周期对照、21项仿真配置、Python17项及隔离综合/路由通过；Setup/Hold WNS=+0.337/+0.020ns，STA覆盖95.79%。新位流实板待验收，历史位流和原运行数据库不覆盖，未提交/推送。

上一独立发布：[LOST分阶段邻域找回](docs/TEMPLATE_EXPANDED_REACQUIRE.md)，位流 `bitstreams/local_template_expanded_20261020_a/camera_template_expanded_reacquire_20261020_a.bit` 已由用户实板确认可识别并找回，保留对照。最后位置/中央八方向邻域名义约±25个720p像素、3帧确认，不是全画面找回。

上一独立发布：[模板匹配流水化](docs/TEMPLATE_SAD_PIPELINE.md)，位流 `bitstreams/local_template_sad_pipeline_20261020_a/camera_template_sad_pipeline_20261020_a.bit` 保留对照。RAM预取与连续累加使最长计算38602→13654时钟，不包含本次邻域扩展。

上一独立发布：[模板快速自动找回](docs/TEMPLATE_REACQUIRE.md)，位流 `bitstreams/local_template_reacquire_20261020_a/camera_template_reacquire_20261020_a.bit` 保留对照。LOST后保留原模板，交替搜索最后位置和中央附近，连续3帧确认；不是全画面搜索。

上一独立发布：[小幅移动模板跟踪优化版](docs/TEMPLATE_FINE_TRACKING.md)，位流 `bitstreams/local_template_fine_20261020_d/camera_template_fine_20261020_d.bit`。2像素粗搜和1像素细化、约±9像素；旧fine D在LOST后停止搜索，不含本次自动找回，保留用于历史对比。

上一独立发布：[中央选定与局部模板跟踪原型](docs/LOCAL_TEMPLATE_TRACKING.md)，位流 `bitstreams/local_template_20261020_b/camera_local_template_20261020_b.bit`，原8像素步进、±32像素版本保留用于历史对比。以下Git检查点与10月19日发布条目为历史记录，不代表本次资源基线。

> 当前有效分支：`WZY`
>
> 历史功能/资源检查点：`a7676fb`（`perf: move vision line buffers to ERAM`）
>
> 可回退标签：`checkpoint-20261016-eram-linebuffers`
> 工程状态：完整综合、布局布线和静态时序已经通过；最新位流仍应在实板上回归检查所有显示模式、自动曝光、按键和蜂鸣器。

这是基于安路 PH1P35A 的 SC520 MIPI 摄像头实时视觉工程。工程在参考的摄像头、ISP、DDR 帧缓存和 HDMI 输出链路上，加入了纯 RTL 的原图/灰度/颜色识别/Canny 边缘检测、自动曝光、OSD、按键控制和蜂鸣器告警。

边缘算法阅读入口：[核心代码分阶段整理](docs/EDGE_DETECTION_CORE.md)，按当前实际 RTL 说明灰度、高斯平滑、Sobel、NMS、双阈值、邻域连接和显示加粗。新增功能的设计草案见 [运动检测方案](reference_edge_project/MOTION_DETECTION_DESIGN.md)；其中资源估算、AE 补偿和验证目标已标注为待实现/待验证。

10月19日历史交付为 [RAW 直通恢复版](docs/RAW_RESTORE.md)：`bitstreams/camera_raw_restore_20261019.bit`，2026-10-19 19:55:06 生成，已同步原 `best_result/camera_to_dsi_display.bit`。默认关闭新增显示均值降噪和暗部曲线，恢复 RAW RGB / GRAY 逐像素输出；保留原曝光/增益、白场 V2、Logo/OSD、10 帧保持及 [Canny 轻度抑噪版](docs/CANNY_NOISE_TUNING.md) 门限，不是回退整个工程。完整功能回归及综合/布局布线通过，Setup/Hold WNS +0.186/+0.020 ns；Slice 76.94%、ERAM 56/108、DSP 24/40。实际清晰度恢复程度仍待同场景实板对比，Canny 内部细节本次未调整。

用户最新澄清为“相机在动、目标物体静止”。**当前 X/Y/P 仍为颜色检测统计，不是通用目标跟踪**。需先指定/初始化目标，再评估移动相机下的跟踪；不能用颜色阈值或裸帧差代替。需求分析见 [移动相机目标需求](docs/MOVING_CAMERA_REQUIREMENTS.md)。

颜色跟踪支持 [有限漏检保持](docs/TARGET_TRACKING_STABILITY.md)：源码默认 10 帧，HOLD=0/1/4/10 的 RTL 仿真已通过；保持期间 OSD 明确显示 HOLD 并保留旧 C/X/Y，P 继续显示本帧实际计数。最新画质位流已包含 10 帧设置；历史存档 `camera_target_tracking_20261017.bit`（20:20:10）仍对应此前 4 帧默认值。

保留 [直接使用安路 Logo 例程代码](docs/EXAMPLE_LOGO.md)：右上调用 `lab_ex3_osd` 原版 `anlogic_logo_rom.v`，保留完整 RGB 和透明规则，不裁剪或量化；左上模式、曝光和颜色目标文字保留。原 Logo 验证位流 `camera_example_logo_20261017.bit`（19:34:55）仍存档，原 `best_result` 现为上述画质优化版。此前 [16 色转换版](docs/LOGO_AND_STATUS_OSD.md) 仅保留为历史。

仍保留 [去孤立小点簇与定向短断口连接](docs/EDGE_REFINEMENT.md)：在显示加粗前清理无支撑小点簇，并补四个方向上最多 2 像素的断口；颜色识别和白场补偿不变。

当前默认使用 [白纸残差固定补偿 V2](docs/WHITE_FIELD_PAPER_V2.md)：根据用户烧录旧免操作版后拍摄的两张白纸图，重新拟合残余色偏并与旧表组合，上电直接应用，不需要长按或按键标定。保留动态 AWB、自动曝光和原按键行为。V2 原验证位流生成时间为 2026-10-17 15:55:01；当前带 Logo/文字的 `best_result` 仍保留 V2 补偿。下述资源/时序表仍属于原 ERAM 基线。之前的 [经验补偿 V1](docs/WHITE_FIELD_SOFT_PRESET.md)、[板上自标定](docs/WHITE_FIELD_SELF_CALIBRATION.md) 保留为历史/可选方案。

`RAW` **不是**传感器 Bayer RAW10：画面仍经过 SC520、MIPI、RAW10 解包、demosaic/ISP、DDR 和白场补偿。当前视觉显示模块已恢复叠加前的逐像素直通；历史[画质增强](docs/PICTURE_QUALITY.md)的 2×2 平均与暗部曲线默认关闭，可选源码保留。自动曝光、手动四档和原 Logo/文字覆盖仍在。

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
- 只有连续成片的颜色候选才进入面积、包围框和告警统计；默认 `800` 像素获取，锁定后 `400` 像素即可更新，漏检最多保持 `10` 帧。HOLD 显示橙色并保留旧 C/X/Y；P 仍显示实际计数，确认 LOST 后清空 C/X/Y。详见 [跟踪状态语义及验证](docs/TARGET_TRACKING_STABILITY.md)。
- 左上角状态文字 OSD（模式、曝光、目标主颜色、中心坐标和像素面积）已恢复默认显示，右上角直接使用安路资料包 `lab_ex3_osd` 的原始 Logo ROM 与透明规则。可用 `ENABLE_STATUS_OSD=0`、`ENABLE_ANLOGIC_LOGO=0` 分别关闭；COLOR 模式的黄色目标框不受影响。原例程位置、接入适配与验证见 [原版 Logo 例程接入](docs/EXAMPLE_LOGO.md)。
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
