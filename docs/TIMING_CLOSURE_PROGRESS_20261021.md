# 时序/CDC 闭环处理记录（2026-10-21，已采用并独立生成，待上板）

## 最新采用状态（10:38）

用户确认采用后，已通过 apply_patch 将 D 的 6 个差异文件合入原工作区；生产与隔离 D 的 223 个设计文件全部匹配 `validated_source_manifest.json`。原运行数据库不变，使用 D 的已验证 routed DB 再次更新时序，结果仍为 Setup/Hold +0.116/+0.020 ns、TNS 0，然后实际运行 bitgen 成功生成新文件。交付目录为 `bitstreams/timing_closure_20261021_a/`，标准文件 `camera_timing_closure_20261021_a.bit`；完整 SHA256 和上板验收见该目录 README。未覆盖历史位流、未提交/推送、未自动烧录。下文是隔离验证阶段记录，提及“未采用/未生成”均为当时状态；以本节为准。现有 patch 是采用前差异存档，不能再次应用到已采用源码。

## 边界

对应 `docs/TIMING_SAFETY_AUDIT_20261020.md`。用户允许 DDR 在隔离副本中修改、验证，验证后再决定是否采用；没有授权直接烧录。原工程的 DDR、引脚、视频模式/帧率、镜头、曝光门限/档位/增益上限、Canny、颜色跟踪和模板匹配算法未改。不提交、不推送、不回退或覆盖历史位流。

隔离版 D 已完成软件侧回归和路由时序验证；尚不能作板级签核，也没有生成任何新位流。下表中工具流程退出码 0 不等于时序通过。

## 当前生产工作区修改

- `ae_set.v`：只修正测光数据跨域的消费时序，多等待一个 24 MHz 接收周期，不改曝光决策规则。新增 13 ns 总线偏差测试先复现旧逻辑混合/过期数据，再验证修复；42 种相位通过。
- `uicfgcs520.v`：SC520 实例改用文件内新增的 `hx_sc520_i2c_ce`。所有寄存器使用主配置时钟，分频相位只作数据/使能，不再作逻辑时钟。旧 `uii2c.v` 保留，作为真实总线仿真对照，也不影响其他使用者。
- I2C 总线周期仍为 `2*(floor(CLK_DIV/2)+1)`，实际 `CLK_DIV=237`，周期 238 个源时钟；OFFSET 规则保留。SDA 增加两级采样。已验证 6 次真实事务、144 个线端 SCL 周期、地址/数据 ACK/NACK、重复 START 读回和中途复位恢复。
- `hx_vision_pipeline.v`：新增通用两级 `hx_reset_release` 定义；原工程顶层尚未使用它。原图/锐化、统计、Canny、颜色与模板跟踪的数据通路未变。
- 补充 CDC、复位、I2C、DDR 参数与串行器测试及旧串行器参考；测试脚本可编译新增的通用单元测试。

原工程顶层、SDC、`video_in.v`、串行器和 DDR IP 修改尚未从隔离副本采用。

## 隔离实现

| 版本 | 主要内容 | 实现结果 | 处理 |
| --- | --- | --- | --- |
| A：`timing_closure_build_20261020_a` | DDR 参考接现有 100 MHz，原 I2C 补生成时钟 | Setup +0.142 ns；Hold -2.583 ns，TNS -62.940 ns；覆盖率 96.22% | 不通过，不生成位流。证明补约束不能代替修复逻辑分频时钟问题 |
| B：`timing_closure_build_20261021_b` | AE/I2C 修复、分域复位、有限 CDC 延迟约束、DDR 100 MHz 参考 | Setup -0.284 ns、TNS -0.929 ns；Hold +0.020 ns、TNS 0；覆盖率 98.47% | 不通过。负路径为像素域复位送串行域，以及 DDR 用户域到 APB；另有旧 sys50 名称造成的 4 个无效约束 |
| C：`timing_closure_build_20261021_c` | 在 B 基础上对齐 DDR tCK=1875 ps | Setup -1.052 ns、TNS -3.634 ns；Hold +0.020 ns、TNS 0 | 不通过，不生成位流 |
| D：`timing_closure_build_20261021_d` | 在 C 基础上给串行域单独同步释放；APB 约束改到实际 100 MHz | 综合/布局布线完成；Setup +0.116 ns、Hold +0.020 ns，TNS 均 0、违例端点均 0；覆盖率 98.49% | 软件侧通过，未生成位流；待采用决定和上板验证 |

路径根目录均为 `D:/Downloads/qiansai/tmp/`，每版独立目录，未覆盖任何旧运行数据库。A/B/C 是失败/诊断实验，不得用于烧录。

## DDR 周期与写恢复

现有 DDR IP 标称参考 100 MHz、DDR2-1066，但原来实际接 50 MHz。隔离副本接到已有 PLL 的 100 MHz 输出后，PLL0 的整数倍分频得到 DDR 533.333 MHz、用户 133.333 MHz，最终检查的 PLL 频率一致性问题已降为 0。

另外发现参数 `tCK=1876` 不等于实际 1875 ps。供应的初始化 RTL 用 `nWR=15000/tCK` 向下取整，1876 会得到 7 周期，对应实际 13125 ps，不满足该 RTL 自己标注的 15000 ps 最低写恢复时间。C/D 仅在隔离副本将 wrapper 和 Design.xml 的 tCK 对齐为 1875，得到 8 周期 / 15000 ps；没有篡改库代码的计算公式。

`tb_ddr_clock_contract.sv` 已复现旧参数失败并验证新参数通过。这是参数级合同检查，不是完整 DDR 颗粒/PHY 仿真，也不替代上板内存稳定性验证。

## CDC 与复位验证

- `tb_sensor_applied_cdc.sv`：原 3 次快照、28 种启动相位、接收时钟暂停/恢复、未完成握手期间共同复位及错峰释放通过。该两相邮箱不承诺支持单边任意复位；隔离顶层保证共同异步复位源，摄像头配置端按上电流程延迟释放。
- `tb_reset_release.sv`：15 个相位/停钟用例，通过异步置复位、两个本地有效时钟沿后同步释放。
- `tb_serializer_reset.sv`：D 串行器与旧 RTL 对照，20 种释放相位、10331 次边沿/移位数据比较通过。ODDR 使用行为比较模型，仅验证 RTL 序列和复位处理，不冒充厂商 I/O 电气/延迟模型。
- 有限数据路径约束取代原来部分整域异步/false-path 屏蔽；不改变实际时钟或提高允许延迟来迎合违例。需要以 D 的最终 `check_timing`、exceptions 和具体路径报告为准，不能沿用试探文件的结果。
- 双向 FIFO、硬 IP、外设接口与复位的模拟行为仍有工具/上板验证边界，不宣称形式化 CDC/RDC 全覆盖。

## 测试进度与证据

38 个通用独立配置（原 35 加 AE CDC/I2C CE/复位同步器）以及 DDR 参数合同、串行器比较，合计 40 个独立配置全部通过。按测试名去重，不将多个目录重复执行计为新增覆盖。集成叠加显示测试完整运行结束；Python 17 项于最终核查再次通过。

复核命令：`python tools/summarize_timing_closure_tests.py 'D:/Downloads/qiansai/tmp/timing_closure_tests_20261021_*' --extra 'tb_ddr_clock_contract=D:/Downloads/qiansai/tmp/ddr_clock_contract_20261021_c/fixed_period.log' --extra 'tb_serializer_reset=D:/Downloads/qiansai/tmp/serializer_reset_20261021_d/serializer.log'`，结果 expected=40、passed=40、pending=[]。跟踪组尾部另在 `timing_closure_tests_20261021_d_tail_{resource,pipeline,misc}` 分组完成，保留原日志。

四组日志：`D:/Downloads/qiansai/tmp/timing_closure_20261020_a/full_b_{equiv,search,tracking,regression}.log`。

其他证据：

- `D:/Downloads/qiansai/tmp/ae_cdc_baseline_20261020_a/baseline.log`：预期失败，证明旧 AE 消费时序问题；其 ModelSim 进程退出码不能代替 Fatal 日志判断。
- `D:/Downloads/qiansai/tmp/timing_closure_i2c_tests_20261021_a/`：真实总线对照、状态发布、CDC、AE 的针对性回归通过。
- `D:/Downloads/qiansai/tmp/timing_closure_i2c_period_20261021_b/`：6 事务、144 次 SCL 周期检查通过。
- `D:/Downloads/qiansai/tmp/ddr_clock_contract_20261021_c/`：原周期参数预期失败，新周期参数通过。
- `D:/Downloads/qiansai/tmp/serializer_reset_20261021_d/serializer.log`：D 串行器 RTL 对照通过。
- `D:/Downloads/qiansai/tmp/timing_closure_20261020_a/experiment_a_*`、`experiment_b_*`：深度时序检查与具体违例证据。
- 之前 `timing_closure_full_regression_20261020_a` 的串行回归中途被会话中断，不计为整套通过；已用上述四组新目录重跑。

## D 最终时序、资源与可复核边界

深度报告位于 `D:/Downloads/qiansai/tmp/timing_closure_20261020_a/experiment_d_{check,timing,violations,exceptions,ignored,clocks,area,multi_drive}.rpt`。最终 routed DB 为 `D:/Downloads/qiansai/tmp/timing_closure_build_20261021_d/phy_1/camera_to_dsi_display_pr.db`。

- Slow/Fast 的 Max/Min 均分析，Setup/Hold WNS +0.116/+0.020 ns，TNS 均 0，违例端点均 0。覆盖率由原实际基线的 95.86% 增至 98.49%，不等于形式化 CDC 或板级电气全覆盖。
- 缺失时钟、无效约束、PLL 频率不匹配、组合环、无路径约束均为 0；多驱动检查报告为空。仍保留 4 类库模型 dummy-node 提示，不宣称所有告警为零。
- FIFO 灰码最大延迟约束每条覆盖 18 条路径、预算 7.200 ns，Ignored=0。4 组时钟对约束各有 9 条 Shadowed 路径，由更具体、同样有界的 IP 灰码约束接管，不是整域忽略。原审计中的 18 条 Ignored 风险已不再出现在 D 的对应灰码约束中。
- 普通 IO 13 位、集成 DDR IO 45 位的位置/标准核查通过；自动 TMDS 负端 4 位单列，MIPI 专用 PAD 10 位通过 DPHY0 固定宏分类。通用 IO 告警仍保留，分类不等于证明板级电气正确。

| 最终路由资源 | 原实际基线 | 隔离 D | 差值 |
| --- | ---: | ---: | ---: |
| Slice | 18300/21216 | 17544/21216（82.69%） | -756 |
| LUT6 | 16921/21216 | 16049/21216（75.65%） | -872 |
| REG | 16271/42432 | 16122/42432（37.99%） | -149 |
| ERAM | 95/108 | 92/108（85.19%） | -3 |
| DSP | 27/40 | 27/40（67.50%） | 0 |

IO 为 58/160，PLL 3/6，GCLK 7/32，SCLK 19/48。以上是整体重实现后的实际差异，不能将全部下降归功于某一段代码，也没有通过删除跟踪/搜索功能换取资源。

最终 223 个设计文件的指纹保存在隔离目录 `validated_source_manifest.json`；最终再次逐项核查无变化。原 `source_manifest.json` 是修改前基线，不冒充最终源码清单。当前生产工作区与 D 恰有 6 个设计文件不同：顶层、SDC、video_in、串行器、DDR wrapper/XML。对应差异保存在 `docs/TIMING_CLOSURE_ISOLATED_D.patch`，`git apply --check --ignore-space-change` 通过，**未应用**。其余设计文件一致，功能回归所用公共 HDL 与隔离版一致。

## 尚未闭环 / 采用前须知

1. D 的完整综合/布局布线/Setup/Hold、约束、资源、时钟和逻辑引脚核查已完成；剩余板级验证不能由软件结果代替。
2. 通用 `check_io` 的 10 项告警需按 MIPI 专用 PAD 分类核实。顶层 68 个端口位由普通 IO 13、DDR 45、MIPI 专用 PAD 10 组成；原最终 IO 报告覆盖普通/DDR 的 58 位，MIPI 通过 DPHY0 硬宏固定位置，并非可直接按 GPIO 绑定。当前不能将通用检查器的告警直接当成 10 个真实 GPIO 漏绑。
3. `check_design` 在综合后通过、映射后报 Slice 超限；最终资源报告与布线拥塞并不显示真实超限。需区分检查器适用阶段/资源单位，不能用该命令单独宣称最终物理资源溢出。
4. 检查器仍报告 no-input-delay 35、no-output-delay 63、partial-input-delay 1：涉及异步按键/复位、配置总线、MIPI/DDR 专用接口和输出口。专用硬宏不能当作普通同步 GPIO 简单填延迟；普通外设仍需真实外部时序预算。不能填零或扩大假路径凑 100%。板级时钟质量、外部时序和 DDR 实测无法由软件仿真完全证明。
5. DDR/顶层隔离修改采用前需用户决定；任何试验版均未生成或烧录位流。
