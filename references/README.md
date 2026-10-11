# 图像链路参考工程库（安路 FPGA 移植用）

下载时间：2026-10-12
用途：为「摄像头采集 → 预处理 → JPEG 压缩 → 显示」链路提供可查阅的 RTL / 算法 / 架构参考。
所有仓库均为 `--depth 1` 浅克隆，版本已冻结，适合直接翻阅，不适合 `git pull` 长期跟随。

---

## 目录结构

```
references/
├── 01_jpeg/                   JPEG / 无损压缩
│   ├── frame-codebase/        brilliantlabsAR 视频链路里的 JPEG RTL（已稀疏检出）
│   ├── FPGA-JPEG-LS-encoder/  wangxuan95 JPEG-LS 无损编码器
│   ├── FPGA-QOI/              wangxuan95 QOI 编解码器
│   └── openeye-CamSI/         CamSI 摄像头串行接口工程（含 JPEG 工程说明文档）
├── 02_camera_pipeline/        采集到显示完整链路
├── 03_preprocess/             实时预处理（灰度/中值/Sobel）
├── 04_sobel_linebuffer/       行缓存 + 3×3 窗口 + 边缘检测
├── 05_isp/                    综合 ISP 模块拆分参考
└── 06_articles/               CSDN 文献核实记录（非代码）
```

---

## 01_jpeg —— JPEG 压缩

### frame-codebase（JPEG encoder）
- 本地路径：`01_jpeg/frame-codebase/source/fpga/modules/camera/jpeg_encoder/`
- 原始地址：https://github.com/brilliantlabsAR/frame-codebase/tree/main/source/fpga/modules/camera/jpeg_encoder
- 版本：`d309634`（2025-10-05），**已用 sparse-checkout 只检出 camera 目录**，仓库主体未下载
- 检出内容：`jenc/`（DCT、量化、zigzag、熵编码、huff 表）、`jisp/`（rgb2yuv、subsample、mcu_buffer）、`jlib/`（afifo、dp_ram、huffman ROM）
- 可借鉴：这是**有真实视频链路验证**的 JPEG RTL，SystemVerilog 编写，模块切分干净（ISP 前处理 / 编码核 / 通用库三层分离），适合当作"接口与时钟域如何组织"的样板
- 注意点：
  - 顶层是 `.sv`，安路工具链对 SystemVerilog 的支持度需先确认，必要时改写成 Verilog-2001
  - 同目录下的 `camera.sv / crop.sv / debayer.sv / gamma_correction.sv` 已一并检出，可对照看**缺哪些预处理环节**
  - 依赖 `jlib` 里的 afifo/dp_ram，移植时要连这些基础件一起搬
  - 上位机侧接口是 Ambiq SoC，**不是标准 AXI-Stream/Video**，需自己加接口适配

### FPGA-JPEG-LS-encoder
- 本地路径：`01_jpeg/FPGA-JPEG-LS-encoder/`（`RTL/jls_encoder.v` 单文件）
- 原始地址：https://gitee.com/wangxuan95/FPGA-JPEG-LS-encoder
- 版本：`6bce7c5`（2024-09-18）
- 可借鉴：JPEG-LS 近无损/无损编码的完整 Verilog 实现，**单文件、无 IP 依赖**，是评估"无损路线硬件代价"的最佳对照物；作者另有配套仿真与上位机解码脚本
- 注意点：JPEG-LS 码流**不是**通用 JPEG，普通浏览器/上位机解不开，全链路都要自己实现；压缩比与画面质量的关系与 JPEG 完全不同，不能只看"能综合"

### FPGA-QOI
- 本地路径：`01_jpeg/FPGA-QOI/`（`RTL/qoi_compressor.v`、`RTL/qoi_decompressor.v`）
- 原始地址：https://gitee.com/wangxuan95/FPGA-QOI
- 版本：`ee189f8`（2024-09-18）
- 可借鉴：QOI 是极简无损格式，压缩/解压各一个 Verilog 文件，**是三者里硬件代价最低的**；适合先拿它把"压缩 → 存储 → 解压 → 显示"的完整数据通路跑通，再换 JPEG 换压缩比
- 注意点：QOI 压缩比通常明显不如 JPEG-LS，优势只在逻辑面积和延迟；三者（JPEG / JPEG-LS / QOI）必须按"压缩比 × 面积 × 延迟 × 解码端复杂度"四维一起比

### openeye-CamSI（文档载体）
- 本地路径：`01_jpeg/openeye-CamSI/`
- 原始地址：https://github.com/chili-chips-ba/openeye-CamSI
- 版本：`c112967`（2026-05-07），体积 985 MB，其中 `0.doc` 单文件 732 MB
- 可借鉴：RISC-V/开源芯片培训课程工程，`0.doc` 是整套 JPEG 工程的图文讲解，`1.hw / 2.sim / 3.build / 4.lint` 是各环节目录
- 注意点：**732 MB 的 doc 打开会很慢**，建议按需查阅；该仓库是课程工程，不是可移植的 IP 库

---

## 02_camera_pipeline —— 采集到显示的完整链路

### fpga-camera-pipeline
- 本地路径：`02_camera_pipeline/fpga-camera-pipeline/`
- 原始地址：https://github.com/RSoleym/fpga-camera-pipeline
- 版本：`bce328e`（2026-05-10），2 MB
- 目录：`rtl/`（`full_camera`、`frame_buffer`、`fifo_to_frame_buffer`）、`constraints/`、`sim/`、`docs/`、`tools/`
- 可借鉴：**优先精读这一个**。OV7670 采集 → RGB565 → 帧缓存 → FIFO → VGA 输出的完整数据流与缓存结构都在 `rtl/` 下，模块粒度和本项目的链路需求最接近
- 注意点：接口和时序约束是 Basys 3 + OV7670 的**不能直接套到安路板卡**；帧缓存很可能依赖 BRAM 原语，安路需换成自己的 `Gowin_*`/`AL_*` 等价原语或推 IP

---

## 03_preprocess —— 实时预处理

### image-process-on-fpga
- 本地路径：`03_preprocess/image-process-on-fpga/`
- 原始地址：https://github.com/YenLaurent/image-process-on-fpga
- 版本：`396d16b`（2025-09-29），22 MB
- 目录：`sources/`、`sim/`、`constrs/`、`pc_viewer/`、`results/`、`bitstream/`
- 可借鉴：OV5640 输入，灰度 + 中值 + Sobel 流水处理，**带完整仿真资料和 PC 端查看程序**（`pc_viewer/`），适合当"采集后预处理"的模块参考；有中英文双份说明（`README.md` / `README_SC.md`）
- 注意点：面向 Artix-7，**时钟、约束、板级接口都要移植**；`bitstream/` 只对本板有意义

---

## 04_sobel_linebuffer —— 行缓存与边缘检测

### FPGA_RealTime_and_Static_Sobel_Edge_Detection
- 本地路径：`04_sobel_linebuffer/FPGA_RealTime_and_Static_Sobel_Edge_Detection/`（`src1/`、`src2/`）
- 原始地址：https://github.com/AngeloJacobo/FPGA_RealTime_and_Static_Sobel_Edge_Detection
- 版本：`61d28b5`（2021-11-02）
- 可借鉴：实时 + 静态两种模式的 OV7670 Sobel 工程，**3×3 窗口生成、行缓存、像素流水、边界处理**这套结构是灰度/滤波/Sobel 等一切邻域运算的基础
- 注意点：年代较早（2021），代码风格偏老式 Verilog，需要自己核对行缓存深度与位宽

### Microchip fpga-hls-examples（sobel_tutorial）
- 本地路径：`04_sobel_linebuffer/fpga-hls-examples/sobel_tutorial/`
- 原始地址：https://github.com/MicrochipTech/fpga-hls-examples/blob/main/sobel_tutorial/trainingdoc.md
- 版本：`e3f6e60`（2026-06-29），整个仓库 224 MB（**只看了 `sobel_tutorial/` 一个目录**）
- 目录：`trainingdoc.md` + `part1/ part2/ part3/`（分阶段教程）+ `media/`
- 可借鉴：**行缓存的原理讲解最清晰**，`trainingdoc.md` 从 3×3 窗口怎么用行缓存凑出来讲起，适合先建立概念再看 RTL
- 注意点：教程用 SmartHLS（C++/HLS 流程），**逻辑结构可参考，代码接口不能直接移植**；仓库里其余几十个例程与本项目无关，占了大部分体积

---

## 05_isp —— 综合图像处理模块

### zynqmp_cam_isp_demo
- 本地路径：`05_isp/zynqmp_cam_isp_demo/`
- 原始地址：https://gitee.com/zhihuaxie007/zynqmp_cam_isp_demo
- 版本：`cf3c8b8`（2022-12-18），总 1994 MB
- **真正有用的只有**：`zynqmp_cam_isp_demo.srcs/`（5 MB，源码）、`xil_ip_repo/`（14 MB）、`Doc/`（5 MB）、`zynqmp_cam_isp_demo.xpr`
- 可借鉴：坏点校正、黑电平、去噪、白平衡、色彩转换、Gamma、裁剪、缩放、OSD 等模块**分目录存放**，是拆解功能清单、规划流水线顺序的最好素材
- 注意点：
  - **这是 Zynq/Xilinx 工程，大量模块依赖 Xilinx HLS IP**，不能当成安路可直接编译的工程
  - 约 **1.6 GB 是 Vivado 综合/实现产物**（`.runs/ .gen/ .cache/ .vitis/ .ip_user_files/`），对移植 0 价值，可按需删除（见文末清理命令）

---

## 06_articles —— CSDN 文献核实

见 `06_articles/CSDN_参考文章.md`。结论摘要：**两篇 CSDN 链接均未提供可用源码**，一篇被站点反爬拦截，另一篇的实际内容与表格描述不符。

---

## 全局注意点（移植到安路前必读）

1. **没有一个是安路工程**。参考价值集中在 RTL 结构、行缓存/窗口生成、模块切分、流水线顺序；时钟、约束、原语、接口一律要重做。
2. **SystemVerilog vs Verilog-2001** 先确认工具链支持度：`frame-codebase` 是 `.sv`，`FPGA-JPEG-LS-encoder` / `FPGA-QOI` 是纯 Verilog。
3. **IP 依赖排查**：BRAM、FIFO、乘法器/DSP 在 Xilinx 工程里多为厂商 IP，安路需换等价原语或重新推 IP。`FPGA-JPEG-LS-encoder` 与 `FPGA-QOI` 无 IP 依赖，最适合先上手。
4. **压缩格式三选一别混用**：JPEG（有损、通用、解码端简单）、JPEG-LS（无损/近无损、解码端必须自研）、QOI（极简无损、面积最小）。先定压缩比与解码端在哪一侧实现，再选路线。
5. **克隆版本已冻结**，`--depth 1` 无历史记录，不能 `git pull`。需要更新时删掉目录重新克隆。
6. **授权需逐个核对**：各仓库 LICENSE 不同（`frame-codebase` 为非商业许可，`wangxuan95` 系列多为 MIT 一类），商用前务必看各自 LICENSE 文件。

---

## 可选：释放约 1.6 GB 空间

以下目录纯粹是 Vivado 构建产物，删除不影响源码阅读（**确认后再执行**）：

```bash
cd "D:/desktop/FPGA_AL/模块/references/05_isp/zynqmp_cam_isp_demo"
rm -rf zynqmp_cam_isp_demo.runs zynqmp_cam_isp_demo.gen \
       zynqmp_cam_isp_demo.cache zynqmp_cam_isp_demo.vitis \
       zynqmp_cam_isp_demo.ip_user_files
```

同理，`04_sobel_linebuffer/fpga-hls-examples/` 若只需 Sobel 教程，可只保留 `sobel_tutorial/`，再省约 200 MB。

---

## 原始清单与本地路径对照

| 方向 | 参考项目 | 本地路径 | 状态 |
|---|---|---|---|
| JPEG 压缩 | frame-codebase JPEG encoder | `01_jpeg/frame-codebase` | 已下载（稀疏） |
| JPEG 压缩 | FPGA-JPEG-LS-encoder | `01_jpeg/FPGA-JPEG-LS-encoder` | 已下载 |
| JPEG 压缩 | FPGA-QOI | `01_jpeg/FPGA-QOI` | 已下载 |
| JPEG 工程说明 | openeye-CamSI | `01_jpeg/openeye-CamSI` | 已下载 |
| 完整链路 | fpga-camera-pipeline | `02_camera_pipeline/fpga-camera-pipeline` | 已下载 |
| 实时预处理 | image-process-on-fpga | `03_preprocess/image-process-on-fpga` | 已下载 |
| 行缓存/边缘检测 | AngeloJacobo Sobel | `04_sobel_linebuffer/FPGA_RealTime_and_Static_Sobel_Edge_Detection` | 已下载 |
| 行缓存教程 | Microchip sobel_tutorial | `04_sobel_linebuffer/fpga-hls-examples/sobel_tutorial` | 已下载 |
| 综合 ISP | zynqmp_cam_isp_demo | `05_isp/zynqmp_cam_isp_demo` | 已下载 |
| 文献参考 | CSDN 肤色识别（119781770） | `06_articles/CSDN_参考文章.md` | 未获取正文 |
| 文献参考 | CSDN JPEG Encoder 博客 | `06_articles/CSDN_参考文章.md` | 内容不符，无源码 |
