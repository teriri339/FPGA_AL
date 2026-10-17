# 边缘检测核心代码整理

整理日期：2026-10-17。依据当前工程实际接入的 RTL。最初仅整理说明；现已同步更新至新增二值边缘清理/连接的版本，具体变更见第 9 节。

## 1. 看哪份代码

实际实现：`reference_edge_project/user_source/hdl_source/hx1p35_port/hx_vision_pipeline.v`，模块 `hx_vision_pipeline`。

顶层 `design_top_wrapper.v` 的 `u_hx_vision_pipeline` 接入显示像素域；`isp_top.v` 已明确旁路旧 `edge_detect_96`，不要把旧模块当成当前显示的边缘算法。

本文仅摘录核心计算，保留原信号名，省略重复的原注释。**代码块不是可独立综合的模块**：完整运行需要原文件中的 ERAM、窗口移位、坐标、复位和流水寄存器。需要编译时仍使用原工程，不能把下面的片段作为新模块重复加入 TD。

## 2. 总体流程

```text
RGB888
  → 加权灰度
  → 3×3 Gaussian 平滑
  → 3×3 Sobel：幅值和四方向
  → NMS 非极大值抑制
  → 按局部亮度选择双阈值
  → 3×3 邻域连接、去孤点、补一像素断点
  → 寄存 edge_core_q
  → 两级 5×5 去孤立小点簇、定向补 1～2 像素断口
  → 2×2 显示加粗
  → 黑底白线（I_mode == 3）
```

这是轻量化、流式 Canny 类实现，不是完整软件 Canny 的全图递归滞后追踪。检测的是亮度变化，不识别物体类别；颜色识别和黄色目标框是另一条支路。

## 3. RGB 转灰度

```verilog
wire [15:0] gray_sum = I_rgb[23:16] * 8'd77 + I_rgb[15:8] * 8'd150 + I_rgb[7:0] * 8'd29;
wire [7:0] gray = gray_sum[15:8];
```

即 `Y = floor((77R + 150G + 29B) / 256)`。输入每通道 8 位，输出灰度 8 位。

## 4. 3×3 高斯平滑

当前输入像素位于窗口右下角；前两行由 ERAM 提供，同行历史由寄存器提供：

```text
raw_top_d2   raw_top_d1   raw_top_right
raw_mid_d2   raw_mid_d1   raw_mid_right
raw_bot_d2   raw_bot_d1   gray

卷积权重：  1 2 1
            2 4 2    / 16
            1 2 1
```

```verilog
wire [11:0] gaussian_sum = {4'd0,raw_top_d2} + ({4'd0,raw_top_d1} << 1) + {4'd0,raw_top_right} +
                           ({4'd0,raw_mid_d2} << 1) + ({4'd0,raw_mid_d1} << 2) + ({4'd0,raw_mid_right} << 1) +
                           {4'd0,raw_bot_d2} + ({4'd0,raw_bot_d1} << 1) + {4'd0,gray};
wire [7:0] gaussian_gray = gaussian_sum[11:4];
```

系数用移位实现，除以 16 用截位实现。输出经过 `gaussian_gray_q`、`gaussian_gray_d` 等寄存器与行缓存数据对齐后，进入 Sobel。

## 5. Sobel 梯度：核心算子

Sobel 窗口与上一节同样排列，但使用平滑后的灰度：

```text
top_d2   top_d1   top_right
mid_d2   mid_d1   mid_right
bot_d2   bot_d1   gaussian_gray_d

Gx 核： -1  0  1       Gy 核：  1  2  1
        -2  0  2                0  0  0
        -1  0  1               -1 -2 -1
```

```verilog
wire [10:0] gx_pos = {3'd0,top_right} + ({3'd0,mid_right} << 1) + {3'd0,gaussian_gray_d};
wire [10:0] gx_neg = {3'd0,top_d2} + ({3'd0,mid_d2} << 1) + {3'd0,bot_d2};
wire [10:0] gy_pos = {3'd0,top_d2} + ({3'd0,top_d1} << 1) + {3'd0,top_right};
wire [10:0] gy_neg = {3'd0,bot_d2} + ({3'd0,bot_d1} << 1) + {3'd0,gaussian_gray_d};
wire [10:0] gx_abs = (gx_pos >= gx_neg) ? (gx_pos - gx_neg) : (gx_neg - gx_pos);
wire [10:0] gy_abs = (gy_pos >= gy_neg) ? (gy_pos - gy_neg) : (gy_neg - gy_pos);
wire [11:0] sobel_mag = {1'b0,gx_abs} + {1'b0,gy_abs};
```

使用 `M = |Gx| + |Gy|`，不计算平方根；梯度越大，局部亮度变化越明显。

### 四方向量化

```verilog
wire gx_dominant = {1'b0,gx_abs} >= ({1'b0,gy_abs} << 1);
wire gy_dominant = {1'b0,gy_abs} >= ({1'b0,gx_abs} << 1);
wire gx_positive = (gx_pos >= gx_neg);
wire gy_positive = (gy_pos >= gy_neg);
wire [1:0] sobel_direction = gx_dominant ? 2'd0 : gy_dominant ? 2'd2 :
                              ((gx_positive == gy_positive) ? 2'd1 : 2'd3);
```

不计算 `atan2`，通过大小和符号比较量化成四个比较方向。方向表示梯度方向，不是轮廓线的走向；具体相邻像素配对以 NMS 代码为准。

## 6. NMS：只保留局部峰值

幅值也构成一个 3×3 窗口，中心为 `mag_mid_d1`；右下角为新得到的 `sobel_mag`。`dir_mid_d1` 是随中心幅值一起延迟的方向。

```verilog
reg nms_peak;
always @(*) begin
    case (dir_mid_d1)
        2'd0: nms_peak = (mag_mid_d1 >= mag_mid_d2) && (mag_mid_d1 > mag_mid_right);
        2'd1: nms_peak = (mag_mid_d1 >= mag_top_right) && (mag_mid_d1 > mag_bot_d2);
        2'd2: nms_peak = (mag_mid_d1 >= mag_top_d1) && (mag_mid_d1 > mag_bot_d1);
        default: nms_peak = (mag_mid_d1 >= mag_top_d2) && (mag_mid_d1 > sobel_mag);
    endcase
end
```

分别比较左右、右上/左下、上下、左上/右下。两侧比较采用一侧 `>=`、另一侧 `>`，对相等平台作不对称取舍，避免把整个平坦平台都保留下来。

## 7. 按局部亮度选择双阈值

参数默认值如下，当前顶层未覆盖这六个参数：

| 局部灰度条件 | 弱候选阈值 | 强候选阈值 |
| --- | ---: | ---: |
| `top_d2 < 96` | 40 | 72 |
| `96 <= top_d2 < 176` | 60 | 96 |
| `top_d2 >= 176` | 64 | 112 |

这些是梯度幅值阈值，不是原图的灰度阈值。

```verilog
wire local_dark_region = (top_d2 < 8'd96);
wire local_bright_region = (top_d2 >= 8'd176);
wire [11:0] sobel_threshold = local_dark_region ? SOBEL_THRESHOLD_DARK :
                              local_bright_region ? SOBEL_THRESHOLD_BRIGHT : SOBEL_THRESHOLD_NORMAL;
wire [11:0] sobel_strong_threshold = local_dark_region ? SOBEL_STRONG_THRESHOLD_DARK :
                                     local_bright_region ? SOBEL_STRONG_THRESHOLD_BRIGHT : SOBEL_STRONG_THRESHOLD_NORMAL;
wire weak_edge_pixel = nms_valid && nms_peak && (mag_mid_d1 >= sobel_threshold);
wire strong_edge_pixel = nms_valid && nms_peak && (mag_mid_d1 >= sobel_strong_threshold);
```

注意 `weak_edge_pixel` 表示“达到低阈值的候选”，**包含强候选**，不是仅指介于两个阈值之间的像素。

## 8. 邻域连接与去孤点

将上一步的候选继续送入 3×3 窗口，中心是 `weak_hyst_mid_d1` / `strong_hyst_mid_d1`；右下角是本拍的 `weak_edge_pixel` / `strong_edge_pixel`。

```verilog
wire strong_hyst_neighborhood = strong_hyst_top_d2 || strong_hyst_top_d1 || strong_hyst_top_right ||
                                strong_hyst_mid_d2 || strong_hyst_mid_right ||
                                strong_hyst_bot_d2 || strong_hyst_bot_d1 || strong_edge_pixel;
wire weak_hyst_any_a = weak_hyst_top_d2 || weak_hyst_top_d1 || weak_hyst_top_right || weak_hyst_mid_d2;
wire weak_hyst_any_b = weak_hyst_mid_right || weak_hyst_bot_d2 || weak_hyst_bot_d1 || weak_edge_pixel;
wire weak_hyst_has_neighbor = weak_hyst_any_a || weak_hyst_any_b;
wire weak_hyst_pair_a = (weak_hyst_top_d2 && (weak_hyst_top_d1 || weak_hyst_top_right || weak_hyst_mid_d2)) ||
                        (weak_hyst_top_d1 && (weak_hyst_top_right || weak_hyst_mid_d2)) ||
                        (weak_hyst_top_right && weak_hyst_mid_d2);
wire weak_hyst_pair_b = (weak_hyst_mid_right && (weak_hyst_bot_d2 || weak_hyst_bot_d1 || weak_edge_pixel)) ||
                        (weak_hyst_bot_d2 && (weak_hyst_bot_d1 || weak_edge_pixel)) ||
                        (weak_hyst_bot_d1 && weak_edge_pixel);
wire weak_hyst_has_two_neighbors = weak_hyst_pair_a || weak_hyst_pair_b || (weak_hyst_any_a && weak_hyst_any_b);
wire symmetric_hyst_edge = hyst_window_valid && weak_hyst_mid_d1 && strong_hyst_neighborhood &&
                           weak_hyst_has_two_neighbors;
wire supported_strong_edge = hyst_window_valid && strong_hyst_mid_d1 && weak_hyst_has_neighbor;
```

规则：强候选也要有至少一个低阈值候选邻居，删除完全孤立点；低阈值候选要邻接强候选，且八邻域至少有两个低阈值候选，才通过连接支路。

这里是单次局部判断，不会沿着长弱边链条反复迭代传播，因此不能等同于完整 Canny 的递归滞后追踪。

### 单像素断点补齐

```verilog
wire horizontal_one_pixel_gap = weak_hyst_mid_d2 && weak_hyst_mid_right &&
                                (strong_hyst_mid_d2 || strong_hyst_mid_right);
wire vertical_one_pixel_gap = weak_hyst_top_d1 && weak_hyst_bot_d1 &&
                              (strong_hyst_top_d1 || strong_hyst_bot_d1);
wire diagonal_down_one_pixel_gap = weak_hyst_top_d2 && weak_edge_pixel &&
                                   (strong_hyst_top_d2 || strong_edge_pixel);
wire diagonal_up_one_pixel_gap = weak_hyst_top_right && weak_hyst_bot_d2 &&
                                 (strong_hyst_top_right || strong_hyst_bot_d2);
wire one_pixel_gap_edge = hyst_window_valid && !weak_hyst_mid_d1 &&
                          (horizontal_one_pixel_gap || vertical_one_pixel_gap ||
                           diagonal_down_one_pixel_gap || diagonal_up_one_pixel_gap);
wire edge_core = supported_strong_edge || symmetric_hyst_edge || one_pixel_gap_edge;
```

四个方向中，对向两点均为低阈值候选、且至少一侧为强候选时，允许填补中间没有候选的一点。这是本工程额外的连接规则。

## 9. 新增：去小点簇、短断口连接、输出加粗

`edge_core` 先寄存为 `edge_core_q`，然后默认经过 `hx_edge_binary_refine`：先清理无延伸支撑的小点簇，再定向补短断口。两级均采用 5×5 窗口，完整实现仍位于同一个 `.v` 文件内。新逻辑和限制见 [边缘清理与连接](EDGE_REFINEMENT.md)。

`ENABLE_EDGE_REFINEMENT=0` 可恢复原来的旁路路径。默认启用时，加粗输入改为 `refined_edge`，对应扫描坐标为 `refined_x`：

```verilog
wire edge_display_pixel = refined_edge ||
                          ((refined_x != 0) && edge_dilate_left) ||
                          edge_dilate_above ||
                          ((refined_x != 0) && edge_dilate_above_left);
```

显示模式选择分支中的原代码：

```verilog
2'd3: base_rgb = edge_display_pixel ? 24'hffffff : 24'h000000;
```

`edge_core` 是原邻域融合结果，`refined_edge` 是新增清理/连接后的结果，`edge_display_pixel` 是加粗后的显示结果。加粗服务于观察，不属于 Sobel 或 NMS 本身。

## 10. 不能漏掉的硬件配套

### 行缓存

原主流水线内有三组 `hx_eram_line_store`，底层使用安路 `PH1P_LOGIC_ERAM`；新增两级清理/连接各有一组 4 位行缓存：

| 实例 | 数据宽度 | 存放内容 |
| --- | ---: | --- |
| `u_raw_color_line_store` | 18 位 | 两行原始灰度和一行颜色编码；与颜色识别共用 |
| `u_edge_line_store` | 46 位 | 两行平滑灰度、两行梯度幅值、一行方向、两行低阈值和两行强候选 |
| `u_dilate_line_store` | 1 位 | 一行融合边缘，用于 2×2 加粗 |
| `g_edge_refinement/u_refine/u_clean/u_rows` | 4 位 | 清理阶段的前四行二值边缘 |
| `g_edge_refinement/u_refine/u_bridge/u_rows` | 4 位 | 连接阶段的前四行已清理边缘 |

每组逻辑深度 2048，地址 11 位。表中为逻辑数据宽度，不能直接当作物理 ERAM 块数。

底层 A 口下降沿读、B 口上升沿写；`edge_line_rd_q` 又锁存一次读数据。抽离算法时不能用普通数组随意替换读写时序。

### 有效范围

```verilog
wire sobel_valid = gaussian_de_d && (gaussian_x_d >= 11'd4) && (gaussian_y_d >= 11'd4);
wire nms_valid = sobel_valid && (gaussian_x_d >= 11'd6) && (gaussian_y_d >= 11'd6);
wire hyst_window_valid = nms_valid && (gaussian_x_d >= 11'd8) && (gaussian_y_d >= 11'd8);
```

这是当前实现等待多级窗口建立的门控，不代表软件中对称的四周补零。不要删除这些条件，否则行首、帧首可能引用缓存残留。

### 流水寄存器与窗口推进

原文件后半部分的时序块还负责：

- `I_user && I_de` 定义帧首，`I_last` 推进行坐标；
- 原始灰度、平滑灰度、幅值/方向、候选窗口的移位和行首重装；
- `gaussian_gray_q → gaussian_gray_d` 与坐标、DE、ERAM 读数据对齐；
- `edge_core → edge_core_q` 寄存，随后维护加粗窗口；
- `stage_rgb → O_rgb` 以及显示控制信号寄存。

这些时序逻辑不是可省略的“外围代码”。本文没有把整个视频处理简化成一个固定拍数的组合函数。新增两级窗口的扫描偏移与边界裁剪已在独立参考模型中验证，详见新增说明；并未把整条原 Canny 路径重新配准到 RGB 输入，不能把边缘位图直接当成与原图同坐标的检测掩膜。

## 11. 阅读和调试入口

按原文件信号名搜索即可定位：

| 目标 | 搜索词 |
| --- | --- |
| 梯度计算 | `gx_pos`、`sobel_mag` |
| 边缘细化 | `nms_peak` |
| 检测灵敏度 | 六个 `SOBEL_*THRESHOLD*` 参数 |
| 去孤点、局部连接 | `supported_strong_edge`、`symmetric_hyst_edge` |
| 补断 | `one_pixel_gap_edge` |
| 新增小点簇清理 | `hx_edge_window5` 的 `clean_pixel` |
| 新增短断口连接 | `bridge_axis`、`bridge_pixel` |
| 最终加粗 | `edge_display_pixel` |
| 窗口和读写时序 | `edge_line_wr`、`hx_eram_line_store`、时序 `always` 块 |

降低阈值通常会同时增加细节和噪声；调边缘参数不能消除 RGB 原图中的空间偏绿。白场补偿属于前级颜色校正，不属于本算法。
