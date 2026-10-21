# 颜色跟踪：迟滞门槛与有限漏检保持

## 本次改动

针对 `hx_vision_pipeline.v` 中“一帧不足 800 像素就立即取消目标”的行为，保留已有 RGB 颜色判定、同色邻域筛选和包围框平滑，只修改帧边界的发布逻辑及状态显示。

| 参数 | 默认值 | 含义 |
| --- | --- | --- |
| `MIN_TARGET_PIXELS` | 800 | 未锁定时，至少这么多有效像素才获取目标 |
| `TARGET_RELEASE_PIXELS` | 前者的一半，默认 400，最小 1 | 已锁定时，本帧至少这么多有效像素即可继续更新 |
| `TARGET_HOLD_FRAMES` | 10 | 连续漏检可保留的完整帧数；第 11 次连续漏检取消锁定 |

当前源码默认值为 10，HOLD=10 的 RTL 仿真已通过。`camera_target_tracking_20261017.bit` 与 `best_result` 的构建记录早于本次默认值调整，仍对应 4 帧默认配置；本次未重新综合、未替换位流、未烧录。要在板上使用 10 帧设置，须另行完成构建和实板回归。

两个门槛均包含等号，零像素永远不是有效测量。保持时间以完成帧计数，不是固定毫秒；若实际处理帧率为 60 fps，10 帧约 167 ms，具体时长须以实测帧率计算。设置 `TARGET_HOLD_FRAMES=0` 可关闭保持；同时把释放门槛设为获取门槛，可恢复原来的单门槛判定（P 显示仍采用本帧实测）。参数要求保持帧数非负、释放门槛在 1 到获取门槛之间。

## 屏幕与信号语义

| 状态 | 上方状态字/文字颜色 | C/X/Y | P | COLOR 目标框 |
| --- | --- | --- | --- | --- |
| TRACK | 绿色 | 最新有效帧测量；坐标沿用 1/2 包围框平滑 | 最新完成帧的实际计数 | 黄色 |
| HOLD | 橙色 | 上次有效 C/X/Y，明确属于旧数据 | 最新完成帧的实际计数，允许为 0 | 原位置橙色框，不预测运动 |
| LOST | 红色 | 显示 `-`，坐标与框寄存器清零 | 最新完成帧的实际计数，不隐藏低于门槛的诊断值 | 不画框 |

- `O_target_found` 现在表示跟踪锁定，TRACK/HOLD 都为 1；**不能单独用它声称本帧检测成功**。内部 `target_fresh` 为本帧有效测量标志，`target_holding` 为保留状态。
- `O_target_pixels` 始终是实际完成帧计数，保持期间也不替换成旧面积；OSD 的 P 转 BCD 后最多显示 999999。
- 计数在下一次 `I_user && I_de` 时发布，与原工程相同；没有添加额外图像延迟或改变 ERAM 读写时序。
- 漏检恢复后计数清零；用较低门槛恢复仅适用于锁定尚未到期。确认 LOST 后必须重新达到获取门槛。
- 目标首次出现沿驱动的蜂鸣器在 HOLD 内恢复时不会再次触发；确认 LOST 后重新获取才产生新的出现沿。原始顶层告警连线未改。
- 第一行第 22～26 列显示 TRACK/HOLD/LOST，第二行仍显示 C/X/Y/P；原 Logo、模式与曝光显示保留。

## 来源与限制

设计调研参考：[Zhuohan-Zhou/fpga-realtime-vision](https://github.com/Zhuohan-Zhou/fpga-realtime-vision) 的 `color_blob_tracker.v`（连续漏检确认思路）。没有复制该仓库代码，也没有移植其 Kalman/α–β 预测、搜索窗口或除法器。该仓库未见明确许可证，不能把公开可读当成允许复制的许可。

本次仅自行实现门槛迟滞、小计数器、有限状态保持及显示适配。它减少门槛附近闪烁及短暂漏检掉零，**不提高颜色分割本身的准确率**，也不能修复原图偏绿、遮挡或同色背景干扰。当前 P/包围框仍合并所有命中的 R/G/B 像素，C 为面积最大的颜色；不是单物体连通域跟踪，没有目标身份匹配。低保持门槛可能延长误检，需要结合实拍评估。

## 可重复验证

```powershell
powershell -ExecutionPolicy Bypass -File tools/test_target_tracking.ps1
python -m unittest discover -s tests -p 'test_*.py'
```

脚本可通过 `-ModelSimBin`、`-TdRoot` 指定安装目录，始终新建独立仿真目录，不覆盖工程或已有日志。

`tests/tb_target_tracking.sv` 输入实际 RGB 矩形帧，使用厂商 ERAM/GSR 模型；独立参考按矩形邻域规则计算面积、框和平滑/状态，再用十进制除法核对 BCD。检测统计不使用 `force` 或写 DUT 寄存器；仅在空白期临时探测 OSD 显示坐标和 DE 以检查字符/颜色，随后释放。

已通过 HOLD=0/1/4/10 四种配置，分别 79/80/83/89 次帧发布，共 3,050,496 个 RGB 输入像素，无仿真错误和 vlog 编译警告，覆盖：

- 799/800 获取边界，399/400 保持边界；
- 有效色块、连续漏检、保持期恢复和超时后重新获取；
- 漏检期间保留旧色彩/坐标，不把不足门槛的另一颜色发布为新目标；
- 连续 35 帧空场不会计数回卷后恢复旧锁定；HOLD=10 时也验证了第 11 次连续漏检转为 LOST，计数不回卷；
- 初始、TRACK/HOLD 状态复位，24 组确定性伪随机色块；
- C/X/Y/P、状态文字/颜色、橙色保持框与红色丢失状态。

其他回归全部通过：

- 四模式对照 24,576 个输出像素，精修/旁路边缘差异仍为 1,838，不涉及 Canny 算法改动；
- 四模式 Logo/OSD 共 983,040 个输出像素，25,548 个原 ROM 有效 RGB 像素、76,852 个透明像素一致，叠加区域外图像与关闭叠加版本相同；
- 720p 边缘精修四帧，共 3,686,400 个像素逐点一致；
- Python 单元测试 17 项全部通过；
- 以上 RTL 仿真均通过、无 `$fatal` 失败；vlog 编译无错误/警告。ModelSim 控制台会对脚本中的 `onerror` / `onbreak` 宏命令输出提示性 warning（不是 RTL 编译警告）。旧日志目录仅记录此前版本：`D:/Downloads/qiansai/tmp/target_tracking_sim_a268679040a448238adb8f8d83690d2f/`；本次 HOLD=10 四配置回归日志：`D:/Downloads/qiansai/tmp/target_tracking_sim_b72f1589133c4e9b801fb05f0ca1cf14/`。

尚未上板验证，不将仿真通过表述为实拍问题已经解决。

## 构建与交付记录

- 独立构建目录：`D:/Downloads/qiansai/tmp/target_tracking_20261017_a/`，从当前工程源码清单准备，保留现有文件排除项；未覆盖原工程综合/布局数据库。
- 综合、布局布线和 bitgen 均完成。最终 Setup WNS +0.251 ns，Hold WNS +0.020 ns，TNS=0、违规端点 0。完整报告 `phy_1/camera_to_dsi_display_pr.timing` 的 STA coverage 为 95.94%；时序结论针对现有约束覆盖范围，不声称覆盖所有异步路径。
- Slice 16,329/21,216（76.97%），LUT6 14,275，寄存器 14,806，ERAM 56/108，DSP 24/40。ERAM/DSP 数量与上一版相同。
- 综合告警类别和数量与上一原 Logo 验证构建一致，仍含 DDR IP 未驱动端口、部分无约束路径等原有告警；并非声称整个工程构建零告警。
- 位流生成时间：2026-10-17 20:20:10（Asia/Shanghai）。标准位流 1,789,539 字节，压缩位流 1,416,689 字节。
- 存档 `bitstreams/camera_target_tracking_20261017.bit`、`camera_target_tracking_20261017_compress.bit`；摘要报告使用相同前缀 `.area.txt` / `.timing.txt`。
- 标准 SHA256：`573D02A2513EE3BFC66E46583367544CB447DA357190BBAABB4D22120929FE6C`。
- 压缩 SHA256：`E620A9994CCD24B78BB7E023B818F64AA31CFED8A5FC297D3182CB720C80A0F3`。
- 标准/压缩位流、BID、时序摘要均已同步 `reference_edge_project/td_project/camera_to_dsi_display_Runs/best_result/`，复制后 SHA256 与构建输出一致。
- 原 `best_result` 中 19:44 的标准位流 SHA256 为 `263A23FFE219C7CEEF3D1490657AAEE9F6FDD50D3FFF6312F7B0B4DFB34EBE42`；替换前全部 5 个普通文件逐个复制并核对哈希，备份在 `best_result/backup_before_target_tracking_20261017_202010/`。目录内更早的备份未修改。
- 主视觉源码与构建副本 SHA256 均为 `BCE0C25040E738271F623A6A46816E386E1A3CCD05FB6893D0279E2303EC05B7`，Logo 原 ROM 仍为 `37C76680345F17A85632B7835E46A3A197CF75FDD91CA6A970B75F5346E7A9F8`。准备脚本把构建副本的 `WHITE_FIELD_FIXED_AWB=WHITE_FIELD_SELF_CAL` 显式写为 0；在当前 `WHITE_FIELD_SELF_CAL=0` 配置下语义相同，其余顶层参数未变化。
- 该组构建位流没有烧录，也没有提交/推送 GitHub，继续遵循 `.gitignore`。之后将 `TARGET_HOLD_FRAMES` 默认值改为 10 的源码与本次回归尚未提交/推送；10 帧默认配置仍需重新构建位流。

烧录当前原目录的 `best_result/camera_to_dsi_display.bit`，切到 COLOR 模式，将彩色目标移入、短暂遮挡再移出，观察 TRACK → HOLD → LOST；保持期间坐标不应立即清零，P 则应随当前有效颜色面积下降，恢复后返回 TRACK。仍需实测快速移动、光照改变及同色背景下的误检和延迟。
