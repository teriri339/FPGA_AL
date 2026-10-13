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
- 两颗板载按键已专用于视觉模式和蜂鸣开关；`ae_set` 的按键输入固定为未按下，避免切换模式时同时修改摄像头曝光。

## SC520 摄像头修正

- 摄像头型号由先前误认的 SC500 修正为 SC520；加入官方 `uics520_cfg` 配置模块与 1280×720@60 寄存器表。
- 工作格式为 RAW10、2 Lane、828 Mbps/Lane；MIPI D-PHY 接收均衡按官方 SC520 参考工程改为 3 dB。
- 增加 PWDNB/XSHUTDN 上电时序：低电平保持至少 1 ms，释放后等待至少 5 ms，再启动 100 kHz I2C 初始化。
- 增加 Sensor ID 与 I2C 错误状态保留信号，便于 Tang Dynasty 在线调试。
- DDR、ISP、HDMI 和现有视觉算法链路未改动；旧 `uics500_cfg` 文件仅保留作历史参考，不再加入 TD 编译工程。

## 板级引脚复核修正

- 根据 HX1P35A 新版开发板手册和原理图，将系统复位改到板载 KEY1/D5、算法切换改到 KEY2/A9、蜂鸣开关改到 KEY3/B9；三个输入均为低有效并启用上拉。
- 顶层 `I_button` 由只读但误声明的 `inout` 修正为 `input`。
- 删除无实际 HDMI 用途的 `O_screen_pwm` 顶层输出及 R11 约束，释放以太网 PHY 的 TXD0；同时释放原先被误作复位输入的以太网 TX_EN/R10。
- `S_rst_n` 与 `S_hdmi_rst_n` 现同时受 PLL 锁定和板载 KEY1 控制，复位键可真正复位视频与视觉流水线。
- 摄像头 K3/J3/L3/L2、蜂鸣器 C12、HDMI G16/F17/H14/C17、MIPI 硬核 Pad 与 DDR IP 内部约束经复核保持不变。

