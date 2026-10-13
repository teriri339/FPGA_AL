# WZY 分支工程结构

本分支按“可直接编译工程、当前有效 RTL、独立算法样例、历史资料”分层。为保持 Tang Dynasty 工程内的相对路径有效，不随意移动 `reference_edge_project/` 中的文件。

## 实际编译入口

- TD 工程：`reference_edge_project/td_project/camera_to_dsi_display.al`
- 顶层 RTL：`reference_edge_project/user_source/hdl_source/design_top_wrapper.v`
- 管脚约束：`reference_edge_project/user_source/constraints_source/pin.adc`
- 时序约束：`reference_edge_project/user_source/constraints_source/timing.sdc`

## 当前有效功能代码

- `reference_edge_project/user_source/hdl_source/hx1p35_port/`
  - `hx_pixel_stream_adapter.v`：RGB/YUV 定点变换与像素流适配。
  - `hx_vision_pipeline.v`：原图、灰度、三色掩膜、3×3 Sobel、目标统计、包围框和 OSD。
  - `hx_button_mode_ctrl.v`：按键同步、消抖与显示模式控制。
- `reference_edge_project/user_source/hdl_source/uics520_cfg/`
  - SC520 初始化、1280×720@60 寄存器表、曝光和增益配置。

上述文件已经加入 `.al` 工程。摄像头至显示的有效链路为：

`SC520 → MIPI D-PHY → RAW10 解包 → ISP → DDR 帧缓存 → hx_vision_pipeline → HDMI`

## 其他目录

- `src/`：早期独立 RGB888 算法样例，不是当前 TD 工程的编译输入，保留用于模块级阅读和复用。
- `constraints/board_template.adc`：早期约束模板；实际编译以参考工程内的 `pin.adc` 为准。
- `docs/archive/`：早期迁移方案与历史说明，不代表当前实现状态。
- `references/`：外部算法参考仓库，以 Git submodule 固定版本，不进入目标工程综合。

## 分支规则

- 日常开发只提交到 `WZY`。
- `main` 保留为稳定基线，不直接覆盖、不强制推送。
- 每项功能单独提交；验证后再由用户决定是否通过 Pull Request 合并到 `main`。
- 修改 TD 工程时保持相对路径，避免整目录替换造成 IP、约束或工程配置丢失。

## 克隆方式

只获取主工程：

```bash
git clone --branch WZY https://github.com/teriri339/FPGA_AL.git
```

同时获取外部参考仓库：

```bash
git clone --branch WZY --recurse-submodules https://github.com/teriri339/FPGA_AL.git
```

已克隆但参考目录为空时：

```bash
git submodule update --init --recursive
```
