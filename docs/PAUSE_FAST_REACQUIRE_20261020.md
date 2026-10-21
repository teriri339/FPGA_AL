# 快速全面找回：暂停及续写节点

> 后续资源优化已完成并独立发布，最新交付见 `TEMPLATE_FAST_RESOURCE_OPT.md`。原暂停记录和快速找回 A 均保留为历史；新优化 A 实板待验收。

> 已由用户明确要求恢复，并于 2026-10-20 完成全部验证和独立发布。本文件以下内容保留为暂停时的历史记录，不代表当前仍有未完成验证。最新状态、位流、资源和上板操作见 `TEMPLATE_FAST_REACQUIRE.md`；新位流为 `bitstreams/local_template_fast_reacquire_20261020_a/camera_template_fast_reacquire_20261020_a.bit`，实际效果仍待上板验收。

用户于 2026-10-20 要求暂停；后台测试与隔离 TD 构建已在约 19:46 主动停止。不要自动恢复工作。本文件是工作区续写记录，不是 Git 提交或经过完整验证的发布节点。

## 当前状态

快速粗搜已接入，完整回归、隔离综合、布局布线与时序验证尚未完成。没有生成或交付快速粗搜新版位流；不能把旧位流当作新版。

工程：`D:\Downloads\qiansai\FPGA_AL_WZY_ERAM_OPT_GIT`。
工作区有大量既有修改及未跟踪文件，必须保留；先重新检查当前状态及 diff，不要假设本记录之后源码没有变化。

## 已接入实现

- 生产改动集中于 `reference_edge_project/user_source/hdl_source/hx1p35_port/hx_template_tracker.v`，相对上个合格全画面找回版本增加 `FAST_REACQUIRE=1`，同文件内有 `hx_template_coarse_proposer`。
- 独立 4×4 盒式均值降采样，720p 得到 320×180 冻结灰度快照；原显示分辨率不变，不访问 DDR 新接口。
- 64 点零均值 SAD 粗搜，步长为一个缩小图像素，即原图 4 像素；保留两个空间分离候选。早期原图 8 像素步长漏掉 3 像素偏移，已经修正，不应恢复旧实现。
- 粗搜候选与原失败搜索交替调度，保留最后位置、中央、慢速全画面扫描兜底。候选仍经过原分辨率精匹配及三帧确认，不能直接进入 TRACK。
- 正常 TRACK/HOLD 和冻结原模板不变。无足够纹理时允许继续走慢速兜底。
- 新测试包括 `tests/tb_template_fast_reacquire.sv`、`tests/tb_coarse_720p.sv`，原全画面参考为 `tests/hx_template_tracker_global_ref.v`；脚本 `tools/test_raw_display_features.ps1` 默认共 33 个独立配置。

## 暂停时通过的证据（局部通过，不等于全套通过）

日志根目录：`D:\Downloads\qiansai\tmp`。

- `template_fast_unit_c.log`：四配置全部通过。盒式均值 1517 个精确比较；快速恢复 253 完整帧、61 检查；关闭 FAST 对旧全画面参考的等价比较 78476 周期；720p 粗搜 helper 测试 18 帧。
- `template_fast_phases_b.log`：16 种 x/y 子采样相位，496 完整帧，通过精匹配三帧确认。
- `template_fast_python_b.log`：17 项 Python 测试通过。
- `template_fast_equiv_b.log`：首项完整 720p 快速恢复测试通过；目标回来时旧背景扫描在途，35 帧候选加 2 帧确认（静态仿真约 0.617 秒，不是上板保证）。之后的组内测试被暂停中断，整个组未完成。
- helper 720p 扫描为 50325 候选、19375126 周期，74.25 MHz 下约 260.94 ms；这只是 helper 扫描时间，不是整个恢复延时。

## 必须补完的测试

以下组均被用户暂停主动中断，缺少整体成功结束标志，不可记为通过或工具失败。恢复时用新的日志名及新的测试输出目录重跑。

1. `template_fast_integrated_b.log`：8 配置，首个 fast overlay 停在帧 44，尚未到帧 55 的候选验证。配置：`tb_template_fast_overlay,tb_template_global_overlay,tb_template_overlay,tb_template_buttons,tb_template_debug_osd,tb_template_tracker,tb_template_reacquire,tb_template_expanded_reacquire`。
2. `template_fast_equiv_b.log`：7 配置；首项已通过，其余尚未完成。配置：`tb_template_fast_720p,tb_template_global_reacquire,tb_template_far_equivalence,tb_template_resource_equivalence,tb_template_pipeline_equivalence,tb_template_diagnostics,tb_template_global_720p_schedule`。
3. `template_fast_regression_b.log`：13 配置；前七项通过，picture quality 过程中暂停。配置：`tb_button_sharpen,tb_sensor_applied_cdc,tb_uics520_applied_status,tb_picture_ae,tb_raw_sharpen,tb_raw_sharpen_720p_timing,tb_raw_sharpen_full_width,tb_picture_quality,tb_vision_edge_modes,tb_logo_osd,tb_canny_noise,tb_target_tracking,tb_template_far_reacquire`。

已完成结果仅在相关源码、测试和编译输入仍一致时才可复用。恢复时核对 33 配置覆盖情况。

## 隔离构建节点

- `D:\Downloads\qiansai\tmp\template_fast_reacquire_20261020_a` 是旧步长实现，中途停止，不能复用。
- `D:\Downloads\qiansai\tmp\template_fast_reacquire_20261020_b` 是当前步长实现，综合主动停于 SYN Stage 2.4 Map Gate / Post LUT mapping optimization。
- B 的 `syn_1/synthesis_console.log` 尚无完整综合结束结果，没有布局布线、STA、新位流。中途 LUT 数不能当作最终资源占用。
- 恢复时创建新的隔离目录（例如不存在的 `template_fast_reacquire_20261020_c`），不要复用中断数据库，不动原工程运行数据库。
- 准备命令模板：`python tools/prepare_raw_display_build.py NEW_ROOT --flow-template D:/Downloads/qiansai/tmp/template_global_reacquire_20261020_a`。
- TD CLI：`D:/AnlogicTD-HX1P35A/bin/td_commands_prompt.exe`；检查隔离生成的 `verify.tcl`，先完成综合，再布局布线和 STA。真实错误需报告准确阶段和内容并停止，不能生成位流。
- 发布前用准备工具 `--verify` 核对当前工作区与隔离源码指纹。全部验证通过后才允许在事先确认不存在的独立目录生成唯一命名位流；绝不覆盖历史文件。

## 最后一个完整验证版本：慢速全画面找回 A

位流：`bitstreams/local_template_global_reacquire_20261020_a/camera_template_global_reacquire_20261020_a.bit`。

SHA256：`53448C5B1ECB602F91A638098D5861B0D0B91375C952F11ED6AFECAECC99F998`。
文件长度 1789539 字节，生成时间 2026-10-20 18:43:54。

此版本已通过软件及隔离实现验证，但尚未获得用户上板验证确认；不要与此前用户确认能找回的 expanded 版本混淆。

实际资源基线：Slice 17816/21216；LUT6 16149/21216；REG 15906/42432；ERAM 71/108；DSP 27/40；IO 58/160；PLL 3/6。
Setup/Hold WNS +0.179/+0.020 ns，TNS 0，违例端点 0，STA 覆盖率 95.82%（不是 100%）。保留原 I2C/O_cam24m mixed fanout 及一项 local clock route 警告。
说明：`docs/TEMPLATE_GLOBAL_REACQUIRE.md`。

快速版本资源、时序和上板速度均未完成验证，不能预先声称优于该基线。

## 续写约束

不回退 Git、不丢弃已有修改、不提交、不推送，不覆盖 best_result 或历史位流。不修改分辨率、帧率、引脚、镜头、自动曝光算法/档位/增益上限、Canny、颜色跟踪、DDR 和现有按键功能；不增加串口坐标输出。保持 RAW 锐化、OSD 和已应用传感器状态语义。

下一步只从检查工作区、补完测试和全新隔离构建开始。只有全部通过才发布独立命名位流并更新资源、时序、STA 覆盖率、操作说明与已知限制。

## 可复制的恢复指令

继续 D:\Downloads\qiansai\FPGA_AL_WZY_ERAM_OPT_GIT。先阅读 docs\PAUSE_FAST_REACQUIRE_20261020.md，检查当前工作区和 diff，从“快速粗搜已接入、完整回归和隔离综合未完成”节点继续。保留现有修改和慢速找回兜底，不回退、不覆盖历史位流、不提交推送。先补完验证，全部通过后才生成独立命名的新位流。
