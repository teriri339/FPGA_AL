# HX1P35A 算法迁移改动清单

## 已迁移并接入

* 来源：旧工程 `ttttssstttt/repo/rgb_to_yuv/src/rgb2yuv.v` 与 `ttttssstttt/repo/yuv_to_rgb/src/yuv2rgb.v`。
* 位置：`reference_edge_project/user_source/hdl_source/hx1p35_port/hx_pixel_stream_adapter.v`。
* 内容：保留 RGB→YUV 的 `77/150/29`、`43/85/128`、`128/107/21` 系数，以及 YUV→RGB 的 `255/359/88/183/454` 系数、阈值和饱和逻辑。只将两个模块重命名为 `_port`，并由 `hx_pixel_stream_adapter` 处理 RGB888 与同步标志。
* 接入点：`design_top_wrapper.v` 的 `video_out` 与 `hdmi_mixer` 之间；MIPI、ISP、DDR、HDMI TX 与其底层驱动均未修改。
* 新增 `hx_vision_pipeline.v`：原图/灰度/颜色掩膜/3×3 Sobel、红绿蓝高饱和目标检测、帧级面积统计、目标包围框与 HDMI 状态条 OSD。
* 新增 `hx_button_mode_ctrl.v`：两级同步、约 10 ms 消抖；按键 0 循环切换显示模式，按键 1 开关告警。
* 新增 `O_buzzer_n`：目标首次出现时低有效短鸣约 200 ms；使用板载蜂鸣器管脚 C12，约束已写入参考工程 `pin.adc`。

## 未迁移（明确废弃）

* Vivado Block Design、MicroBlaze、AXI Interconnect、AXI GPIO/UART/Timer/XADC。
* MIG 7-series DDR3（HX1P35A 改用参考工程的 `ph1p35_324_ddr_wrapper`）。
* 旧板 4 路 LVDS 1:7 接收/解串与对应 I2C。
* 10G SFP GT、RGMII、TCP_10G 与 Xilinx GT 时钟 IP。
* Xilinx ILA、Clock Wizard、DNA/IP Integrator 生成文件。

## 接口与编译注意事项

* 算法总延时为 4 个 `S_hdmi_pixel_clk`，适配层已同步延时 `vsync/hsync/de/user/last`。
* `video_out` 保持由原始 `S_hdmi_de` 请求像素，不能由延时后的 `hdmi_mixer` 请求驱动，否则每行前四个像素会错位。
* 工程文件已加入新增 RTL：`td_project/camera_to_dsi_display.al`，CompileOrder 为 52～54。
* 保持参考工程的 `pin.adc`、`timing.sdc` 和安路 PLL/MIPI/DDR/HDMI IP；必须使用与该参考工程匹配的 PH1P35MDG324、Tang Dynasty 版本重新综合。
* 本机未安装 Tang Dynasty，尚不能完成本次修改后的实机综合；需在装有 TD 的环境进行语法、时序和摄像头/HDMI 联调。
# 复查修正（像素同步）

- 已将 `hx_pixel_stream_adapter.v` 的 `vsync/hsync/de/user/last` 延迟由原先取四级移位寄存器的第 3 级，修正为五级移位寄存器的第 4 级。旧 RGB→YUV→RGB 算法的数据从输入采样到输出相隔四个时钟沿；修正后同步标志与 RGB 输出同拍。

## 视觉功能优化

- 将显示链路中的单像素水平差分替换为两行缓存的 3×3 Sobel，默认阈值为 160。
- 修正帧首有效像素未计入目标面积、首行第二个像素坐标重复的问题。
- 颜色掩膜改为红/绿/蓝分别着色，便于现场调阈值。
- 蜂鸣器由持续电平告警改为目标出现沿触发的约 200 ms 短鸣。
- 两颗板载按键最初用于视觉模式和蜂鸣开关；后续已将 KEY3 改为四档曝光键，蜂鸣器改由板载 SW5 控制；`ae_set` 的原四位按键输入固定为未按下，避免误触发旧调节逻辑。

## SC520 摄像头修正

- 摄像头型号由先前误认的 SC500 修正为 SC520；加入官方 `uics520_cfg` 配置模块与 1280×720@60 寄存器表。
- 工作格式为 RAW10、2 Lane、828 Mbps/Lane；MIPI D-PHY 接收均衡按官方 SC520 参考工程改为 3 dB。
- 增加 PWDNB/XSHUTDN 上电时序：低电平保持至少 1 ms，释放后等待至少 5 ms，再启动 100 kHz I2C 初始化。
- 增加 Sensor ID 与 I2C 错误状态保留信号，便于 Tang Dynasty 在线调试。
- DDR、ISP、HDMI 和现有视觉算法链路未改动；旧 `uics500_cfg` 文件仅保留作历史参考，不再加入 TD 编译工程。

## 板级引脚复核修正

- 根据 HX1P35A 新版开发板手册和原理图，将系统复位改到板载 KEY1/D5、算法切换改到 KEY2/A9、曝光切换改到 KEY3/B9；三个输入均为低有效并启用上拉，蜂鸣器声音由板载 SW5 控制。
- 顶层 `I_button` 由只读但误声明的 `inout` 修正为 `input`。
- 删除无实际 HDMI 用途的 `O_screen_pwm` 顶层输出及 R11 约束，释放以太网 PHY 的 TXD0；同时释放原先被误作复位输入的以太网 TX_EN/R10。
- `S_rst_n` 与 `S_hdmi_rst_n` 现同时受 PLL 锁定和板载 KEY1 控制，复位键可真正复位视频与视觉流水线。
- 摄像头 K3/J3/L3/L2、蜂鸣器 C12、HDMI G16/F17/H14/C17、MIPI 硬核 Pad 与 DDR IP 内部约束经复核保持不变。

## SC520 欠曝光修复

- 修复 `ae_set` 的首次曝光/增益请求条件：此前内部已应用值与目标初值同为 `1990/80`，导致初始化完成后不会产生更新请求，SC520 实际停留在初始化表的最低增益。
- 新增首次应用标志；每次复位后等待摄像头寄存器初始化完成，再强制下发一次曝光 `1990` 和默认增益 `80`（约 4x）。
- MIPI、DDR、ISP、HDMI 与视觉算法逻辑保持不变。

## 按键曝光控制

- 板载只有 KEY1～KEY3，没有可直接分配的第四颗按键；KEY3 改为专用曝光键，每次按下循环一档；蜂鸣器是否发声由板载 SW5 硬件开关控制。
- 曝光共四档：`EXP:0`（600/约 1x）、`EXP:1`（1200/约 2x）、`EXP:2`（1990/约 4x，默认）、`EXP:3`（1990/约 16x，暗光）。
- KEY3 在 24 MHz SC520 配置域独立同步、消抖并生成单脉冲，避免跨时钟控制路径；HDMI 左上角 OSD 显示 `EXP:0～3`。

## 彩色通路与暗光识别修复

- 旁路 ISP 公共链路中的前置 `edge_detect_96`，DDR 改为保存 AWB 后的真实 RGB 彩色帧；RAW、GRAY、COLOR、SOBEL 四种模式不再共同接收黑白边缘图。
- 将 ISP 下游 `ready` 固定为有效，修复顶层原先未驱动的握手输入。
- COLOR 模式改为半亮原图背景叠加红/绿/蓝命中像素，并将亮度门限从 150 降至 80、通道差门限从 45 降至 24，改善暗光和彩色屏幕目标识别。

## 彩色误检抑制

- 红色与蓝色候选使用亮度 96、主通道领先 40 的严格门限；绿色在实拍感冒灵印刷袋无法识别后单独调整为亮度 64、主通道领先 16，并继续依靠空间一致性抑制暗光噪点。
- 新增一行两位颜色缓存；当前候选必须与左、上、左上三个已到达邻居中的至少两个颜色一致，才会成为有效红／绿／蓝目标像素。
- COLOR 高亮、像素计数、目标包围框和蜂鸣器全部改用空间过滤后的结果，孤立或稀疏色噪点不再触发告警。
- 安路 TD 6.2.168116 绿色包装识别优化版本完整实现通过：setup WNS `0.134 ns`、hold WNS `0.020 ns`、0 个违规端点，使用 14198 slices（66.92%）、39 RAM、23 DSP。

## 蜂鸣器方波驱动修复

- 对照开发板初始音乐工程确认 C12 需要音频翻转方波；原先固定拉低 200 ms 只能导通三极管，不能可靠驱动无源蜂鸣器发声。
- 告警改为目标首次出现时输出约 2 kHz、50% 占空比方波 1 秒；空闲保持高电平，SW5 保持在能够播放初始音乐的接通位置。
- 安路 TD 6.2.168116 完整实现通过：setup WNS `0.348 ns`、hold WNS `0.020 ns`、0 个违规端点，使用 14377 slices（67.76%）、39 RAM、23 DSP。

## Sobel 轮廓细化

- 针对实验室实拍中轮廓偏粗、重复边缘较多且弱轮廓断裂的问题，在 Sobel 幅值后增加一组 3x3 滑动窗口。
- 按 `Gx/Gy` 主梯度方向执行局部极大值抑制，仅保留梯度峰值，将宽边缘压细后再进行连续性去噪。
- 细化后自适应门限从 `64/96/128` 调整为 `56/80/112`，补回座椅、设备和文字等低对比度轮廓。
- 安路 TD 6.2.168116 完整实现通过：setup WNS `0.319 ns`、hold WNS `0.020 ns`、0 个违规端点，使用 14814 slices（69.82%）、39 RAM、23 DSP。

## Sobel 双阈值滞后筛选

- 针对轮廓细化后天花板、桌面及设备纹理仍形成大片连续雪花的问题，增加随全局亮度切换的强门限 `96/144/192`。
- 强边缘直接保留；弱边缘 `56/80/112` 仅在水平、垂直或斜向邻接强边缘时保留，避免普通连续性滤波让弱纹理链自行扩散。
- 保留原局部极大值细化，处理顺序为 Sobel 幅值 → 峰值细化 → 双阈值连接，主体边缘仍保持单像素级显示。
- 安路 TD 6.2.168116 完整实现通过：setup WNS `0.526 ns`、hold WNS `0.020 ns`、0 个违规端点，使用 14920 slices（70.32%）、39 RAM、23 DSP。

## 全屏轻量 Canny

- 保持全屏黑底白边输出，不引入左右分屏；OSD 模式名称由 `SOBEL` 更新为 `CANNY`。
- 在 Sobel 前增加 3×3、权重为 `1-2-1 / 2-4-2 / 1-2-1` 的 Gaussian 平滑，以移位加法和右移归一化实现，不使用除法器。
- 局部极大值抑制由水平/垂直两方向升级为 `0°/45°/90°/135°` 四方向，改善椅背、线缆等斜向轮廓的连续性。
- 保留自适应强弱双阈值连接，形成 Gaussian → Sobel → 四方向细化 → 双阈值连接的轻量 Canny 流水线。
- Gaussian 输出增加一级寄存流水，最终实现 setup WNS `0.109 ns`、hold WNS `0.020 ns`、0 个违规端点；使用 15434 slices（72.75%）、39 RAM、23 DSP。

## Canny 暗部轮廓补全

- 根据实拍结果将普通室内场景强门限由 `144` 调整为 `128`，弱门限保持 `80`，增强暗部桌椅和设备边缘而不重新放开低幅噪声。
- 在强边缘邻接筛选后增加一级只读种子连接，允许弱边缘额外延伸一个像素；最终边缘不回写种子缓存，避免纹理链无限传播。
- 安路 TD 6.2.168116 完整实现通过：setup WNS `0.311 ns`、hold WNS `0.020 ns`、0 个违规端点，使用 15453 slices（72.84%）、39 RAM、23 DSP。

## Canny 强细节与轮廓加粗

- 针对实拍效果比参考画面细、暗、细节少的问题，在原四方向 NMS 主轮廓之外增加自适应高门限强细节通路，门限为暗光 `128`、普通照明 `176`、明亮场景 `256`。
- 强细节通路只恢复高置信度梯度邻边，不直接放开低幅弱纹理；与原 Canny 轮廓融合后执行 2×2 受控形态学膨胀，使线条加粗约一像素并增强短断点可见度。
- 新增融合结果流水寄存器，切断梯度比较到 HDMI 输出的长组合路径；安路 TD 6.2.168116 最终实现通过：setup WNS `0.120 ns`、hold WNS `0.020 ns`、0 个违规端点，使用 15717 slices（74.08%）、39 RAM、23 DSP。

## 闭环自动曝光

- HDMI 像素域每 16 行、每 16 像素抽样一次 BT.601 灰度，覆盖全画面并输出逐帧平均亮度，避免仅由局部台灯等高亮区域决定曝光。
- 亮度数据通过稳定总线加翻转标志跨入 24 MHz 摄像头配置域；同步器路径已加入异步约束。
- 自动曝光设置 72～145 的亮度死区，每 16 帧最多调整一次；暗时先增加曝光时间、到顶后增加增益，亮时先降低增益再缩短曝光。
- 上电默认为 `EXP:A`；KEY3 循环 `AUTO → EXP0 → EXP1 → EXP2 → EXP3 → AUTO`，保留四档手动备用。
- 安路 TD 6.2.168116 最终实现结果：setup WNS `0.323 ns`、hold WNS `0.020 ns`、0 个违规端点。

## Sobel 弱边缘增强

- 将原固定阈值 `160` 改为基于上一帧全局亮度的自适应门限：暗光 `40`、普通照明 `64`、高亮 `96`。
- 暗光和普通室内场景能够保留床沿、木板接缝等低对比边缘；高亮场景自动提高阈值，避免木纹和传感器噪声过多。
- 安路 TD 6.2.168116 最终实现结果：setup WNS `0.110 ns`、hold WNS `0.020 ns`、0 个违规端点。

## 自动曝光高光保护

- 在全局平均亮度之外增加接近饱和样点统计；3600 个抽样点中高光超过 108 个（约 3%）时优先执行降曝光。
- 高光过曝时调节间隔由 16 帧缩短为 8 帧，并优先降低增益，再缩短曝光时间；防止暗背景促使灯具或中央反光区域持续过曝。
- 安路 TD 6.2.168116 最终实现结果：setup WNS `0.117 ns`、hold WNS `0.020 ns`、0 个违规端点。

## Sobel 去噪与显示净化

- 根据实拍雪花噪声将自适应门限由 `40/64/96` 调整为 `64/96/128`，降低暗光高增益噪声被误判为边缘的概率。
- 增加上一行、左邻和左上邻边缘一致性判断，仅保留连续边缘，过滤孤立白点，同时保留水平、垂直和斜向结构。
- 黄色颜色目标包围框仅在 COLOR 模式绘制，不再覆盖 RAW、GRAY 或 SOBEL 画面。
- 安路 TD 6.2.168116 最终实现结果：setup WNS `0.243 ns`、hold WNS `0.020 ns`、0 个违规端点。

## Canny 细节连接与暗场曝光优化

- 保持现有 2×2 轮廓加粗不变，将弱门限调整为暗光/普通/明亮 `48/72/96`，强门限调整为 `88/112/176`，让文字、线缆、衣物纹理和屋顶接缝等低对比细节获得更多强边缘锚点。
- 双阈值滞后连接由左、左上、上三个已到达邻域扩展为左、左上、上、右上四邻域；补齐另一方向的斜线和短断点，同时仍只允许弱边缘受控延伸一次，不让弱纹理无限传播。
- 自动曝光高光保护由约 3% 高光即触发改为：全局平均亮度至少达到 88 且高光抽样超过约 10% 才触发；平均亮度低于 72 时无条件优先增亮，允许小面积灯具局部饱和，以保留屋顶、墙面等暗部结构。
- 安路 TD 6.2.168116 完整实现通过：setup WNS `0.212 ns`、hold WNS `0.020 ns`、0 个违规端点，使用 15853 slices（74.72%）、39 RAM、23 DSP。

## 高反差场景局部门限优化

- 针对画面中央灯具或窗口很亮、周围墙面较暗时只剩高光外框的问题，Canny 不再由上一帧全局平均亮度统一选阈值，改用与非极大值中心对齐的局部平滑亮度 `top_d2` 逐像素选择门限。
- 局部亮度低于 `96` 时采用弱/强门限 `44/80`，局部亮度达到 `176` 时采用 `96/176`，其余区域采用 `72/112`；同一画面可同时保留暗墙板缝、空调格栅和亮窗口边缘。
- 自动曝光目标区间由 `72～145` 提高到 `96～160`；高光保护改为全局平均亮度至少 `128` 且高光抽样超过约 `25%` 才触发，允许小面积灯具或窗口局部饱和，以换取暗部结构可见度。
- 轮廓末级仍采用原 2×2 受控加粗，不额外扩大线宽；安路 TD 6.2.168116 完整实现通过：setup WNS `0.138 ns`、hold WNS `0.020 ns`、0 个违规端点，使用 15820 slices（74.57%）、39 RAM、23 DSP。

## 连续弱边与亮区细节增强候选版

- 针对人物只有外框、眼镜等强边而面部明暗、头发和衣纹缺失的问题，新增一行弱边缓存及四方向因果邻域连续性判断；连续至少两个像素的 NMS 弱边可以独立进入输出，孤立噪点仍被拒绝。
- 局部暗/普通/明亮区域的弱门限调整为 `40/60/64`，强门限调整为 `72/96/112`，强细节补偿门限调整为 `112/144/176`；尤其降低亮区门限，以恢复灯管与浅色天花板之间的低对比边界。
- Gaussian、四方向 NMS、原双阈值滞后连接和 2×2 受控加粗均保留，目标是增加内部细节密度而不继续扩大轮廓宽度。
- 安路 TD 6.2.168116 完整实现通过：setup WNS `0.185 ns`、hold WNS `0.020 ns`、0 个违规端点，使用 15937 slices（75.12%）、39 RAM、23 DSP；等待人物与灯管同场景实拍后决定是否升级为里程碑标签。


## GRAD 梯度幅值灰阶模式（未综合验证）

- 显示模式由 4 档扩展为 5 档，KEY2 短按循环 `RAW → GRAY → COLOR → CANNY → GRAD → RAW`；原有四档功能与阈值不变。
- 新增 GRAD 模式：直接显示 Gaussian + Sobel 的梯度幅值，仅做右移缩放与饱和，不经过局部极大值抑制、双阈值滞后连接和 2×2 加粗，因此输出连续灰阶（平坦区黑、弱边灰、强边白）而不是二值细线。
- 幅值缩放由 `GRAD_SHIFT` 参数控制（默认 2，0 最亮、3 最暗），`mag_mid_d1[11:8]` 非零时饱和到 255。
- `I_mode` 由 2 bit 扩为 3 bit，涉及 `hx_button_mode_ctrl`（五档循环）、`design_top_wrapper`（`S_vision_mode`）和 `hx_vision_pipeline`（模式译码、OSD、payload 打包）。
- `hx_centered_display` 的 payload 由 55 bit 扩为 56 bit，`u_video_slots` 行缓存同步改为 56 bit；字段位置从高位插入，`ctrl/x/y/rgb` 索引不变，`stage_sharp` 移至 `[54]`、`stage_mode` 移至 `[53:51]`。
- 显示去噪路径的 `{I_mode,display_source}` 由 26 bit 扩为 27 bit（该路径默认关闭）。
- 模板框显示条件由 `!final_mode[1]` 改为 `final_mode <= 3'd1`，避免在 GRAD 模式下误画。
- OSD 新增 `GRAD` 标识，复用既有字模，无需新增字符。
- `tb_vision_edge_modes.sv` 同步扩到 5 档：新增 GRAD 输出必须为灰阶（R=G=B）且存在非零梯度像素的断言。
- **尚未综合、布局布线和上板**；新增逻辑约 40 LUT6、0 ERAM、0 DSP，需按 TD 流程重新验证时序与资源。

## 模板跟踪框显示平滑（抖动抑制）

- `hx_template_tracker.v` 新增两个参数：`DISP_SMOOTH_SHIFT`（默认 2）、`DISP_DEADBAND`（默认 2）。
- 新增 `disp_x/disp_y` 与 `disp_approach()` 一阶逼近函数；`center_x/center_y` 改为输出 `disp_x/disp_y`（`VERIFY` 阶段仍显示候选位置 `pending_x/pending_y`，语义不变）。
- **搜索中心 `cx/cy` 完全不变**：仍每帧直接跳到 SAD 峰值。跟踪能力、丢失判定、重捕获行为与改动前逐位一致。
- 更新严格每帧一次，只在 `FINISH` 成功路径：连续跟踪走 `disp_approach(disp_x,best_x)`，重捕获确认直接 `disp_x<=best_x` 对齐。`HOLD`/`LOST`/`VERIFY` 期间不更新，框停在最后可靠位置。
- 复位与 `command` 均把 `disp_x/disp_y` 复位到画面中心。
- `hx_vision_pipeline.v` 新增透传参数 `TEMPLATE_DISP_SMOOTH_SHIFT` / `TEMPLATE_DISP_DEADBAND`。
- 新增 `tests/tb_template_display_smooth.sv`：逐拍验证死区性质、滞后、收敛不超调、LOST 保持、重捕获对齐、command/reset 复位；已注册进 `tools/test_raw_display_features.ps1`。
- 既有精确坐标回归用例（`tb_template_reacquire`、`tb_template_expanded_reacquire`、`tb_template_far_reacquire`、`tb_template_global_reacquire`、`tb_template_fast_reacquire`、`tb_template_overlay`）通过参数/`defparam` 把平滑关成 0，语义与改动前一致。
- 三个等价性用例（`tb_template_pipeline_equivalence`、`tb_template_resource_equivalence`、`tb_template_fast_resource_equivalence`）改为比较内部跟踪中心 `cx/cy`，因为 `center_x/center_y` 已是纯显示信号。
- 说明文档：`docs/TEMPLATE_DISPLAY_SMOOTH.md`。
- **尚未综合、布局布线和上板**；新增逻辑约 45 LUT6、0 ERAM、0 DSP。

## 仿真基础设施修复：ERAM 行为模型 + I_mode 位宽

### 新增 `tests/stubs/ph1p_logic_eram_stub.v`

本机未安装 Tang Dynasty，`ph1p/sim_release` 下的厂商仿真库不可用，而 `hx_vision_pipeline.v` 直接例化 `PH1P_LOGIC_ERAM`，导致**所有流水线级 testbench 都无法运行**。新增一个仅用于仿真的行为模型，两个关键点：

1. **A/B 两端口必须共用同一个存储阵列**。第一版桩给两个端口各建一个 `mem_a`/`mem_b`，写端口写进去的数据读端口永远读不到，行缓存恒为 0，流水线一个像素都不输出（表现为 `O_de` 全程为低、控制延迟断言在 20.6 µs 首次失败）。
2. **必须尊重 `REGMODE_A/B`**。本工程两处例化都是 `REGMODE="NOREG"`（异步读），配合 `clka(~clk)` 做"同一像素行内先读后写"的行缓存技巧。无条件打一拍会让整条流水线多出若干拍延迟。

该文件不进入综合，也不会与 TD 的厂商模型同时编译。

### 修复：`I_mode` 从 2 bit 扩到 3 bit 后，多个 testbench 仍用 2 bit 驱动

`GRAD` 模式引入时 `I_mode` 由 `[1:0]` 扩为 `[2:0]`，但下列用例仍用 2 bit 信号/字面量连接：

- `tb_template_overlay.sv`、`tb_target_tracking.sv`、`tb_canny_noise.sv`、`tb_history_raw_compare.sv`、`tb_logo_osd.sv`、`tb_picture_quality.sv`、`tb_raw_sharpen.sv`

**ModelSim 对位宽不匹配的端口不会补零，而是把多余的高位当成未连接（`z`）**（只给一条 `vsim-3015` 警告）。后果：

- `final_mode` 的最高位变成 `z`，`(final_mode <= 3'd1)` 求值为 `X` → **跟踪框永远画不出来**（表现为 `tb_template_overlay` 报 "Tracking box mismatch"）。
- `case(I_mode)` 匹配不上任何分支 → 落到 `default`，颜色检测整体失效（表现为 `tb_target_tracking` 报 "colour-neighbour count differs from oracle"）。

修复：把上述用例的 `mode` 声明统一为 `[2:0]`（`tb_raw_sharpen` 的 `mode_q` 历史队列一并加宽），两处 `2'd2`/`2'd0` 字面量改为 `3'd2`/`3'd0`。

### 本次仿真实测结果（ModelSim 10.5b + ERAM 桩）

通过：`tb_template_display_smooth`、`tb_template_tracker`、`tb_template_reacquire`、`tb_template_expanded_reacquire`、`tb_template_far_reacquire`、`tb_template_global_reacquire`、`tb_template_fast_reacquire`、`tb_template_pipeline_equivalence`、`tb_template_resource_equivalence`、`tb_template_fast_resource_equivalence`、`tb_template_overlay`、`tb_target_tracking`、`tb_vision_edge_modes`、`tb_picture_quality`、`tb_canny_noise`。

**既有失败（非本次改动引入）**：`tb_raw_sharpen` 报 `Centered RAW/GRAY mismatch at output 2636 mode 0 sharp 1: got 202020 expected 181818`。已用 `git show HEAD:` 的版本做基线对照，**在 HEAD 上同一输出点同样失败**，说明与跟踪框平滑和 `I_mode` 位宽都无关。误差恰好等于 `RAW_SHARPEN_MAX_DELTA=8`，指向 `hx_correction_slots` 的读清/补丁时序（异步读语义下的同拍竞争）。需要 TD 真实原语模型才能判定是桩的语义差异还是设计缺陷，暂不修改。

## 自动曝光修复：防频闪曝光上限 + 逐通道过曝检测

### 问题一：弱光下的横向明暗条带

SC520 是卷帘快门，逐行曝光。50 Hz 市电下光强纹波周期为 10.0 ms，曝光时间不是纹波周期整数倍时各行积分到不同相位，产生横向条带。

本工程 `uics520reg_720p60.v` 配 VTS=1000 行，720p60 下行周期 16.667 µs，曝光寄存器单位为半行 8.333 µs：

- 原上限 1990 半行 = 16.583 ms = 1.66 个纹波周期 → 条带
- 新上限 1200 半行 = 10.000 ms = 1 个纹波周期 → 无条带

`ae_set.v` 新增参数 `ANTI_FLICKER`（默认 1）、`AE_EXPOSURE_MAX_FLICKER`（默认 1200）、`AE_EXPOSURE_MAX_NORMAL`（1990），内部统一为 `C_AE_MAX`，覆盖自动闭环、手动四档、上电初值、复位值。配套处理：

- `C_AE_EXP1 = min(C_AE_MAX, 1200)`：EXP1 原本写死 1200，60 Hz 地区上限 1000 时会越过防频闪上限。
- 进入 AUTO 当拍把 `r_ae_set` 压回 `C_AE_MAX`：原实现要等 16 帧才调节，从 EXP2/EXP3 切回 AUTO 会先闪约 0.27 秒条带。

代价：进光量减少 `1990/1200 = 1.66x = 0.73 EV`，由模拟增益（16~176，最大约 32x）补偿，暗光噪声略增。`ANTI_FLICKER=0` 时所有路径与原参数逐位一致。

### 问题二：暖光过曝盲区

原高光判据 `gray >= 245`（BT.601 加权灰度）会漏判单通道削顶：暖光 `R=255,G=200,B=180` 的灰度只有 214，AE 认为曝光合适，继续提亮直到整片死白。

`hx_vision_pipeline.v` 改为：

```verilog
wire [7:0] max_channel = max(R, G, B);
wire channel_clipped = (max_channel >= HIGHLIGHT_CHANNEL_LEVEL) && (gray >= HIGHLIGHT_LUMA_GATE);
wire highlight_pixel = channel_clipped || (gray >= HIGHLIGHT_LUMA_LEVEL);
```

新增参数 `HIGHLIGHT_CHANNEL_LEVEL=250`、`HIGHLIGHT_LUMA_GATE=180`、`HIGHLIGHT_LUMA_LEVEL=245`。

`gray >= 180` 门限用于排除大面积低亮度饱和色物体：纯红 `255/20/20` 灰度仅 90，属于颜色饱和而非过曝，若不带门限会让 AE 压暗整幅画面去「修复」一朵花。

`frame_highlight_count` 的帧首重装载同步改用 `highlight_pixel`。`C_HIGHLIGHT_HOLD/REDUCE/SEVERE` 三档门限与 3600 采样点不变，百分比含义不变。

资源：约 4 个 LUT6，0 ERAM，0 DSP，不新增流水级。

### 顶层参数

`design_top_wrapper.v` 新增 `ANTI_FLICKER`、`AE_EXPOSURE_MAX_FLICKER`，透传给 `ae_set`。

### 测试

- 新增 `tests/tb_ae_anti_flicker.sv`：同时例化 50 Hz（上限 1200）/60 Hz（上限 1000）两种配置，检查复位值、手动四档（含 EXP1 在 60 Hz 下收到 1000）、全暗停在上限且增益补到 176、强光退到 300/16、回到全暗重新收敛，并用逐时钟沿断言保证全程 `ae <= 上限`。已注册进 `tools/test_raw_display_features.ps1`。
- `tests/tb_picture_ae.sv` 显式加 `.ANTI_FLICKER(0)`，继续逐条锁定改动前的 1990 语义，作为「关闭防频闪后行为不变」的回归保证。
- ModelSim 10.5b 实测通过：`tb_ae_anti_flicker`、`tb_ae_cdc_coherency`、`tb_picture_ae`、`tb_target_tracking`、`tb_template_overlay`（端到端逐像素比对，高光统计字段 dut 与 reference 一致）。
- **尚未综合、布局布线、上板**。条带是否真正消失必须在 50 Hz 实际光源下目视确认。

### 说明文档

`docs/AE_FLICKER_AND_HIGHLIGHT.md`。

### 仓库清理

`.lock.f`（TD 工程锁文件）与 `minidump-*.dmp`（TD 崩溃转储，273 KB）在 `df745ce` 被误提交。已在 `.gitignore` 加入 `*.lock.f` / `minidump-*.dmp`，并 `git rm --cached` 取消跟踪（本地文件保留）。这两个文件仍留在 `df745ce` 的历史里，该提交尚未推送到远端。
