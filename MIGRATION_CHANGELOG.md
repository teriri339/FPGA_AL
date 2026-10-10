# HX1P35A 算法迁移改动清单

## 已迁移并接入

* 来源：旧工程 `ttttssstttt/repo/rgb_to_yuv/src/rgb2yuv.v` 与 `ttttssstttt/repo/yuv_to_rgb/src/yuv2rgb.v`。
* 位置：`reference_edge_project/user_source/hdl_source/hx1p35_port/hx_pixel_stream_adapter.v`。
* 内容：保留 RGB→YUV 的 `77/150/29`、`43/85/128`、`128/107/21` 系数，以及 YUV→RGB 的 `255/359/88/183/454` 系数、阈值和饱和逻辑。只将两个模块重命名为 `_port`，并由 `hx_pixel_stream_adapter` 处理 RGB888 与同步标志。
* 接入点：`design_top_wrapper.v` 的 `video_out` 与 `hdmi_mixer` 之间；MIPI、ISP、DDR、HDMI TX 与其底层驱动均未修改。
* 新增 `hx_vision_pipeline.v`：按键模式切换（原图/灰度/颜色二值/边缘）、红绿蓝高饱和目标检测、帧级面积统计、目标包围框与 HDMI 状态条 OSD。
* 新增 `O_buzzer_n`：目标检测为真时拉低；使用板载蜂鸣器管脚 C12，约束已写入参考工程 `pin.adc`。

## 未迁移（明确废弃）

* Vivado Block Design、MicroBlaze、AXI Interconnect、AXI GPIO/UART/Timer/XADC。
* MIG 7-series DDR3（HX1P35A 改用参考工程的 `ph1p35_324_ddr_wrapper`）。
* 旧板 4 路 LVDS 1:7 接收/解串与对应 I2C。
* 10G SFP GT、RGMII、TCP_10G 与 Xilinx GT 时钟 IP。
* Xilinx ILA、Clock Wizard、DNA/IP Integrator 生成文件。

## 接口与编译注意事项

* 算法总延时为 4 个 `S_hdmi_pixel_clk`，适配层已同步延时 `vsync/hsync/de/user/last`。
* `video_out` 保持由原始 `S_hdmi_de` 请求像素，不能由延时后的 `hdmi_mixer` 请求驱动，否则每行前四个像素会错位。
* 工程文件已加入新增 RTL：`td_project/camera_to_dsi_display.al`，CompileOrder 为 52。
* 保持参考工程的 `pin.adc`、`timing.sdc` 和安路 PLL/MIPI/DDR/HDMI IP；必须使用与该参考工程匹配的 PH1P35MDG324、Tang Dynasty 版本重新综合。
* 本机未安装 Tang Dynasty，尚不能完成本次修改后的实机综合；需在装有 TD 的环境进行语法、时序和摄像头/HDMI 联调。
# 复查修正（像素同步）

- 已将 `hx_pixel_stream_adapter.v` 的 `vsync/hsync/de/user/last` 延迟由原先取四级移位寄存器的第 3 级，修正为五级移位寄存器的第 4 级。旧 RGB→YUV→RGB 算法的数据从输入采样到输出相隔四个时钟沿；修正后同步标志与 RGB 输出同拍。

