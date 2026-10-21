# RAW 显示锐化与传感器写入状态

本页保留第一轮失败构建记录。2026-10-20 后续中心对齐/流水线修复已通过时序并独立发布，当前烧录与操作请看 [后续修复报告](RAW_CENTERED_PIPELINE.md)，不要将下文历史“未生成位流”状态当作最新结果。

## 范围与操作

本功能不修改采集分辨率、帧率、引脚、镜头设置、自动曝光算法/档位/增益上限、Canny、颜色跟踪或 DDR 链路。已有未提交修改保留，不执行提交/推送。

- 上电默认 RAW 原图、锐化关闭，作为可恢复的基准。
- KEY2 短按：松开后切换显示模式；长按约 1 秒：仅翻转 RAW 锐化开关，松开不再切模式，持续按住不会反复翻转。
- RAW 开启锐化时显示 SHARP；其他显示模式不应用锐化，开关状态保留。
- KEY3：保留原 AUTO / EXP0 / EXP1 / EXP2 / EXP3 循环。
- 当前顶层 WHITE_FIELD_SELF_CAL=0；自标定参数分支原有长按用途保留，不属于本次交付模式。

锐化参数在 hx_vision_pipeline.v 中：ENABLE_RAW_SHARPEN=1（编译支持），RAW_SHARPEN_NOISE_GATE=6，RAW_SHARPEN_MAX_DELTA=8，RAW_SHARPEN_GAIN_SHIFT=1（超过门限后的幅值减半）。运行开关默认关闭。亮度高频增量统一加到 RGB，饱和限幅；头两行/列窗口未充满时旁路。测光与颜色统计仍取未锐化输入，文字与 Logo 在显示增强之后叠加。锐化只改善观感，不能恢复失焦、曝光削顶或远距离像素不足丢失的真实细节。

## OSD 含义与确认边界

扩展区形式为 AP E:xxxxx A:xx D:xx/xx OK（字节使用十六进制）：

- E：最近一次完整曝光/增益写表成功的曝光控制值，不是毫秒。
- A：0x3e09 原始字节。
- D：0x3e06 / 0x3e07 原始字节；不是增益倍数，也不是 SC520GainTbl 的查表索引。
- WAIT：还没有完成一次可确认的曝光/增益写表。
- WR / WRITE：写入中，已有数字仍是上一笔完整成功值。
- OK：曝光/增益表的 I2C 写入完成，未观察到 ACK 错误。
- ERR：写入失败；若曾成功，保留上一笔成功数字；否则显示无数据。

这里的“已应用”依据 I2C 完成和 ACK，不包含传感器寄存器读回，也不保证哪一帧已经采用该值。失败写表可能已部分写入传感器，所以错误状态下保留值仅表示“最后完整成功记录”，不保证当前硬件仍保持旧值。

24 MHz 源域发布稳定的 exposure/gain/status/has_value mailbox 和请求翻转位，HDMI 域同步请求后整体接收，再回传 ACK；源域同步 ACK 后才允许下一次发布。HDMI OSD 从同域更新事件锁存，不能用互相独立的多位同步代替握手。SDC 的跨域例外仍要求 mailbox 稳定协议成立，时序通过不能代替 CDC 验证。

## 构建与验证

修复 design_top_wrapper 中六个纯模块输出连接对象的声明：reg 改为 wire；寄存器仍在 hx_sensor_applied_cdc 内部，不删除握手。

隔离构建目录：D:/Downloads/qiansai/tmp/raw_sharp_status_20261019_b。tools/prepare_raw_display_build.py 使用当前工程源列表，复制设计与约束，不做参数覆盖；222 个文件 SHA256 登记。默认只生成综合/布局布线流程，不生成位流。通过 --verify 对比隔离源与当前源。

实际基线为 2026-10-19 20:06 best_result，位流 SHA256：EC67AC415EED264C264491A90EE200863C6DCB8024F4A0364083A951A550148E。其原 phy_1 报告时间匹配，资源 Slice=16456、LUT6=14356、REG=14792、ERAM=56、DSP=24；Setup WNS=0.116ns、Hold WNS=0.020ns、TNS 均为 0，STA 覆盖率 95.96%。基线报告已复制到隔离构建的 baseline 子目录，原运行数据库不修改。

## 本次最终结果：时序不合格，未生成位流

六个 wire 声明修复后，TD 综合成功；隔离布局布线成功执行到 opt_route，工具进程退出码为 0，但这不等于时序合格。完整路由报告为：

- Setup WNS=-5.355ns，TNS=-124.559ns，24 个违例端点。
- Hold WNS=+0.020ns，TNS=0，0 个违例端点。
- STA 覆盖率 95.94%，基线为 95.96%；均不是 100% 覆盖。
- 最差路径：u_hx_vision_pipeline/g_raw_sharpen$u_raw_sharpen_3x3/u_sharpen_luma_rows/u_line_eram_syn_3.clkb → u_hx_vision_pipeline/prefetch_rgb_reg[16]_syn_2.id。
- 路径从 HDMI 像素时钟下降沿的 ERAM 读出到上升沿采样，预算仅 6.667ns；数据路径延迟 11.629ns、14 级逻辑（6 级 ADDER 等），超过预算。这是功能仿真不会揭示的物理时序问题。

| 最终路由资源 | 实际基线 | 本次 | 差值 |
| --- | ---: | ---: | ---: |
| Slice | 16456 | 16688（78.66%） | +232 |
| LUT6 | 14356 | 14705 | +349 |
| REG | 14792 | 14951 | +159 |
| ERAM | 56 | 55 | -1 |
| DSP | 24 | 24 | 0 |

以上是整机重新综合/布局布线后的净变化，不代表锐化模块单独占用量；ERAM 减少也不能解释成新增模块不使用行缓存。

功能回归进程退出码 0，十项全部通过：按键、CDC、SC520 成功/失败写入、AE、锐化像素模型、图像质量、模式、Logo/OSD、Canny、HOLD=10 跟踪。锐化 20,480 像素：平坦噪声样例改动 0，细节样例 420 处增强，孤点最大增量 8，边界 956，旁路及统计隔离通过。RAW/GRAY 图像质量 3,686,400 像素通过；Logo/OSD 983,040 像素通过。SC520 状态测试模拟 busy/error，不代替真实硬件 ACK 实测。Python 17 项通过，git diff --check 通过（仅有已有换行格式提醒）。

回归日志：D:/Downloads/qiansai/tmp/raw_display_features_dcc2862675584490ab3ac16003d7d3db。

最终报告：隔离目录 phy_1/camera_to_dsi_display_pr.timing、camera_to_dsi_display_phy.ts、camera_to_dsi_display_phy.area 和 build_console.log。

**没有执行 bitgen，隔离目录没有 .bit；没有生成或交付新烧录文件，也没有覆盖 best_result 或历史位流。** 原 best_result 位流 SHA256 保持 EC67AC415EED264C264491A90EE200863C6DCB8024F4A0364083A951A550148E。不存在本功能的可推荐烧录路径，不能用该原位流冒充新功能版。

依照本次“构建仍失败则停止”的要求，不继续重构锐化流水线或放宽约束。后续若继续，应拆分行缓存读出、亮度高频计算、限幅/饱和加法等流水级，并对旁路 RGB、控制、模式和 OSD/Logo 坐标重新严格对齐，再完整回归和隔离构建；不能通过 false_path 或多周期约束掩盖此同步数据路径。
