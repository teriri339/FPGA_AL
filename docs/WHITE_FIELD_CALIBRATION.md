# 白场标定与 RGB 空间校正

当前主工程默认 [免操作轻度空间补偿](WHITE_FIELD_SOFT_PRESET.md)，可选 [板上白场自标定](WHITE_FIELD_SELF_CALIBRATION.md)。本文保留离线增益表的生成方法。先前的静态表完整分辨率 RTL 仿真、综合、布局布线记录见 [静态表验证记录](WHITE_FIELD_VERIFICATION.md)。真实摄像头实拍效果仍需上板确认。

## 接入位置与开关

`design_top_wrapper` → `hx_pixel_stream_adapter` → `hx_white_field_lsc` → `hx_vision_pipeline`。
校正在 DDR 读出后的 1280×720 RGB888 单像素时钟域运行，位于颜色识别、灰度、Canny 和 OSD 之前。DDR 保存的仍是未校正 RGB。模块与适配器在同一源文件中，不需要修改现有 TD 工程文件清单。

顶层参数：

| 参数 | 默认值 | 用途 |
| --- | --- | --- |
| `WHITE_FIELD_SELF_CAL` | 0 | 1 使用 KEY2 触发的板上白场采集；0 使用静态表/内置经验补偿 |
| `WHITE_FIELD_SOFT_PRESET` | 1 | 使用基于最初白场截图估计的保守空间色彩补偿 |
| `LSC_ENABLE` | 1 | 0 为组合直通；1 启用六级寄存校正流水线 |
| `LSC_GAIN_FILE` | 空字符串 | `$readmemh` 增益表；为空时全部使用单位增益 |
| `LSC_BLACK_LEVEL` | 0 | 此 RGB 阶段实测的黑电平，范围 0..239；不要填写 RAW10 黑电平 |
| `WHITE_FIELD_FIXED_AWB` | 跟随 `WHITE_FIELD_SELF_CAL` | 1 将现有 AWB 的 R/B 增益固定为 1，G 保持现有直通处理 |

自标定模式下，上电先显示未经空间补偿的 RGB，成功标定后才应用动态增益。不会用截图或合成场景系数代替实测数据。静态表模式下，启用但不加载增益表、且黑电平为 0 时，像素值不变，仅增加六级寄存延时。VS/HS/DE/USER/LAST 全部随像素延时。USER 在首个有效像素上复位坐标，坐标仅随 DE 有效像素前进，可接受 DE 间隙；每行恰好 1280 个像素，每帧 720 行。

## 离线标定步骤（可选）

1. 以 `WHITE_FIELD_SELF_CAL=0`、`WHITE_FIELD_SOFT_PRESET=0`、`LSC_ENABLE=0`、`WHITE_FIELD_FIXED_AWB=1` 构建采集版本。KEY3 选择固定手动曝光档，等待摄像头配置稳定。现有手动曝光路径同时选择固定曝光/增益；采集期间不改变档位、光源、镜头或几何方向。
2. 用均匀照明的哑光白板覆盖整个视场，调到不过曝。采集 16～32 帧 **1280×720 RGB 数字图像**，保存为 RGB PNG/BMP/TIFF。采集点必须在 AWB 后、LSC 前且没有 OSD。当前脚本不提供板端帧导出接口，需要使用已有数字采集设备或另行接入导出链路；不能拿手机拍摄显示器的照片代替。
3. 安装 Python 的 `numpy`、`Pillow` 后，在仓库根目录执行：

   ```powershell
   python tools/calibrate_white_field.py D:/captures/white --output D:/captures/lsc_gains.mem
   ```

   默认黑电平为 0，目标灰度为全部网格通道均值的中位数。若已测得 RGB 黑电平或需要固定目标，可使用 `--black-level 4 --target 160`。脚本检查帧数、分辨率、RGB 格式、过曝、帧间漂移和过暗网格；超出 0.25～4 倍增益直接报错。曝光/增益锁定仍需采集端保证，均值检查不能替代锁定。
4. 保留生成的 `.mem` 和同名 `.json` 采集报告。保持 `WHITE_FIELD_SELF_CAL=0`，设置 `LSC_ENABLE=1`、`LSC_GAIN_FILE="D:/captures/lsc_gains.mem"`，黑电平与脚本一致，继续保持 `WHITE_FIELD_FIXED_AWB=1` 和同一手动曝光档。路径推荐使用正斜杠绝对路径；ROM 初始化在综合时读取，更新表后必须重新综合、布局布线并生成位流。检查综合日志确认文件成功读取。
5. 对比未参与标定的白场帧、灰阶与真实物体，检查边角、细节、高光裁剪以及所有模式，并重新检查资源和时序。如果重新开启动态 AWB 或更改曝光/增益，当前标定的有效性需要重新验证。显示侧校正也会改变自动曝光统计，因此当前验收应保持手动曝光。

## 表格式与运算

16×9 个节点均匀分布在图像端点，行优先，共 144 行，每行一个 9 位十六进制数。位域为 R[35:24]、G[23:12]、B[11:0]；各通道使用无符号 Q4.8，`100` 表示 1 倍。例如单位增益一行为 `100100100`。

脚本先多帧平均，再在各节点附近进行局部均值统计，以共同中性目标计算三通道增益。硬件使用 8 位小数坐标双线性插值，水平、垂直插值分别四舍五入，然后计算 `clamp(round(max(RGB-black,0)*gain),0,255)`。这里的 RGB 已经去马赛克且量化至 8 位，不能恢复之前已裁剪的高光，也不等价于 RAW 域的完整镜头标定。

本实现直接计算插值：每通道两次水平插值、一次垂直插值和一次像素增益乘法，共 12 个乘法表达式。坐标除法在 ROM 初始化时预计算，运行时经过一级同步查表，避免组合除法形成长路径。四端口增益表读可能被综合成 LUT ROM 或复制 RAM，不能承诺仅增加 3 DSP 或固定 ERAM 数量。资源、最高频率和初始化支持以目标工具综合/布局布线为准。后续若资源或时序不足，可改为按行预计算斜率并逐像素累加。

## 验证

Python 测试：`python -m unittest discover -s tests -p test_white_field.py -v`。

ModelSim 在独立临时目录创建 work 库，编译 `hx_pixel_stream_adapter.v` 与 `tests/tb_white_field_lsc.sv` 后，运行 `vsim -c work.tb_white_field_lsc -do "run -all; quit -f"`。测试覆盖单位、空间变化、大增益及全 12 位范围四张表，836 个有效像素，检查三通道、正反插值、四边、黑电平扣除、饱和、DE 间隙、复位、控制延时和默认旁路。可通过 testbench 的 `GAIN_FILE` 参数加载单位增益文件验证 ROM 文件初始化。

`tools/prepare_white_field_verification.py <不存在的输出目录>` 生成独立构建副本、合成白场增益表、完整分辨率像素向量与 NumPy 误差统计，不修改主工程参数和已有构建。该脚本需要已有 TD 基线的 `settings.cfg` / Tcl 流程文件。分别在输出目录的 `syn_1`、`phy_1` 中调用 TD 的 `td_commands_prompt.exe verify.tcl`，进行综合和布局布线，停止在布线完成后，不生成位流或烧板。

编译 `tests/tb_white_field_full.sv` 并以 `-gVECTOR_DIR=<上述输出目录>` 运行 `work.tb_white_field_full`：校验两帧 1280×720 数字图像，覆盖合成白场、高对比细节场景、处理中异步复位和所有同步标志。`tests/tb_white_field_awb.sv` 配合工程清单中实际使用的根目录 `awb.v` 验证固定及动态增益控制；其除法器和传输使用测试替身，不代表完整 ISP 动态仿真。

坏点校正、中值滤波和多帧时域降噪不在本次实现范围内；白场增益补偿不能移除固定污点或恢复遮挡处的细节。
