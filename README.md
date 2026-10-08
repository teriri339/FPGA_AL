# FPGA Real-Time Image Processing

基于 **安路 FPGA** 的实时数字图像处理系统。采集 → 处理 → 显示全流水线的硬件实现。

> 状态：脚手架阶段，功能待实现。

## 项目结构

```
.
├── board/                  # 板级资料：原理图、引脚表
├── doc/                    # 设计文档
│   └── img/                # 框图与波形图
├── hw/
│   ├── constr/             # 约束：引脚 .adc / 时序 .sdc
│   ├── ip/                 # 工具生成的 IP 核
│   ├── sim/
│   │   ├── tb/             # testbench
│   │   ├── modelsim/       # 仿真器库与脚本
│   │   ├── run/            # 仿真运行产物
│   │   └── waves/          # 波形文件
│   └── src/
│       ├── top/            # 顶层例化
│       ├── common/         # 时钟复位、CDC、通用 FIFO
│       ├── cam/            # 采集：传感器接口、Bayer 转换
│       ├── proc/           # 处理：行缓存、滤波、算法核心
│       ├── disp/           # 显示：时序生成、输出接口
│       └── util/           # 零散小模块
├── scripts/                # 综合 / 实现 / 下载脚本
├── sw/
│   ├── host/               # 上位机工具（抓图、调参）
│   └── mcu/                # 配套固件（如需要）
└── tools/                  # 第三方工具依赖说明
```

## 数据通路

```
摄像头 ──> 采集 ──> 行缓存 ──> 算法流水线 ──> 显示时序 ──> 显示屏
```

## 环境

| 工具 | 版本 | 用途 |
| :--- | :--- | :--- |
| TangDynasty | TODO | 综合、布局布线、下载 |
| ModelSim / Icarus Verilog | TODO | 功能仿真 |
| Python | 3.x | 上位机脚本 |

器件型号：TODO（例：`EG4S20BG256`）／开发板：TODO

## 构建

```bash
# 功能仿真
make sim MOD=<模块名>

# 综合 → 位流
make bit DEVICE=<器件型号>

# 下载到板卡
make prog
```

脚本细节见 `scripts/`，或直接在 TangDynasty GUI 中导入 `hw/src` 与 `hw/constr`。

## 开发约定

- 一个模块一个文件，文件名 = 模块名，全小写 + 下划线。
- 跨时钟域信号必须显式同步，并在 `doc` 中登记路径。
- 每个流水线级的延迟需在模块头部注释中标明。

## License

MIT — 见 [LICENSE](./LICENSE)。
