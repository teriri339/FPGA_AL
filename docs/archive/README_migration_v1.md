# ATLE0200P → 安路 PH1P35A 第一版迁移存档

> 来源：提交 `455778f`。这是视觉功能优化前的状态快照。

第一版以安路官方 `reference_edge_project/` 为硬件基线，保留 MIPI D-PHY RX、SC500 摄像头配置、RAW10 解包、ISP、DDR、HDMI、PLL、FIFO、TD 工程与约束。

## 第一版已接入功能

- RGB888 → RGB/YUV 旧算法 → 显示侧视觉处理 → HDMI；
- 原图、灰度、三色目标二值图和轻量水平差分边缘图；
- 红、绿、蓝高饱和像素检测与帧级面积统计；
- 上一帧目标包围框和状态条 OSD；
- 目标存在时持续驱动低有效蜂鸣器 C12；
- 修正 RGB/YUV 流水数据与 `vsync/hsync/de/user/last` 的一拍错位。

## 第一版限制

- 显示链路中的边缘检测还是单行水平差分，不是真正的 3×3 Sobel；
- 两颗按键以组合电平直接选择模式，未做同步、消抖和单脉冲；
- 按键同时连接参考工程曝光控制，可能在切换模式时改变曝光；
- 蜂鸣器在目标存在期间持续鸣叫；
- 尚未在安装安路 TD 的环境重新综合。

## 第一版核心文件

- `reference_edge_project/user_source/hdl_source/hx1p35_port/hx_pixel_stream_adapter.v`
- `reference_edge_project/user_source/hdl_source/hx1p35_port/hx_vision_pipeline.v`
- `reference_edge_project/user_source/hdl_source/design_top_wrapper.v`
- `reference_edge_project/user_source/constraints_source/pin.adc`
- `reference_edge_project/td_project/camera_to_dsi_display.al`
