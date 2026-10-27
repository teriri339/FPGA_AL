`timescale 1ns / 1ps
//【HX1P35A-移植适配】HDMI 像素域视觉流水线：灰度、3x3 Sobel、三原色目标、平滑跟踪框和信息 OSD。
module hx_vision_pipeline #(
    parameter IMAGE_WIDTH = 1280,
    parameter MIN_TARGET_PIXELS = 24'd800,
<<<<<<< Updated upstream
    parameter SOBEL_THRESHOLD_DARK = 12'd40, //【HX1P35A-移植适配】暗区弱边缘门限适度降低，补回人脸明暗、衣纹和墙板接缝。
    parameter SOBEL_THRESHOLD_NORMAL = 12'd60, //【HX1P35A-移植适配】普通室内照明增强文字、线缆和人物内部纹理。
    parameter SOBEL_THRESHOLD_BRIGHT = 12'd64, //【HX1P35A-移植适配】亮区低对比门限降低，使灯管与浅色天花板之间的边界进入候选。
    parameter SOBEL_STRONG_THRESHOLD_DARK = 12'd72, //【HX1P35A-移植适配】暗区增加可靠锚点，Gaussian、NMS 与连续性判断共同抑制噪声。
    parameter SOBEL_STRONG_THRESHOLD_NORMAL = 12'd96, //【HX1P35A-移植适配】普通照明补回主体细节，同时仍由 NMS 限制线宽。
    parameter SOBEL_STRONG_THRESHOLD_BRIGHT = 12'd112, //【HX1P35A-移植适配】降低亮区强门限，避免灯管轮廓因局部高亮分类而消失。
    parameter SOBEL_DETAIL_THRESHOLD_DARK = 12'd112, //【HX1P35A-移植适配】暗光下恢复较强的非极大值邻边，增强头发和衣物纹理。
    parameter SOBEL_DETAIL_THRESHOLD_NORMAL = 12'd144, //【HX1P35A-移植适配】普通照明细节补偿门限兼顾密度和噪声。
    parameter SOBEL_DETAIL_THRESHOLD_BRIGHT = 12'd176 //【HX1P35A-移植适配】亮区保留灯管、窗框等连续细节，避免原 256 门限过度删除。
=======
    // Mild Canny-only noise tuning; no change to exposure or RGB display.
    parameter SOBEL_THRESHOLD_DARK = 12'd48,
    parameter SOBEL_THRESHOLD_NORMAL = 12'd64,
    parameter SOBEL_THRESHOLD_BRIGHT = 12'd68,
    parameter SOBEL_STRONG_THRESHOLD_DARK = 12'd80,
    parameter SOBEL_STRONG_THRESHOLD_NORMAL = 12'd104,
    parameter SOBEL_STRONG_THRESHOLD_BRIGHT = 12'd120,
    parameter ENABLE_STATUS_OSD = 1'b1, // 恢复左上角模式、曝光、颜色目标坐标/面积文字。
    parameter ENABLE_ANLOGIC_LOGO = 1'b1, // 显示末端叠加右上角安路 Logo，不进入视觉统计。
    parameter ENABLE_EDGE_REFINEMENT = 1'b1, // 加粗前去除无延伸支撑的小点簇，再定向连接 1~2 像素断口。
    parameter ENABLE_CAL_STATUS = 0,
    // Restore direct RAW/GRAY display; optional enhancements remain available.
    parameter ENABLE_DISPLAY_DENOISE = 1'b0,
    parameter ENABLE_SHADOW_LIFT = 1'b0,
    parameter ENABLE_RAW_SHARPEN = 1'b1,
    parameter [3:0] GRAD_SHIFT = 4'd2, //【GRAD 模式】Sobel 幅值右移位数；0 最亮、3 最暗，默认 2。
    parameter [7:0] RAW_SHARPEN_NOISE_GATE = 8'd6,
    parameter [7:0] RAW_SHARPEN_MAX_DELTA = 8'd8,
    parameter integer RAW_SHARPEN_GAIN_SHIFT = 1,
    // Acquire at the original threshold; a locked target may use a lower one.
    parameter TARGET_RELEASE_PIXELS = (MIN_TARGET_PIXELS > 1) ? (MIN_TARGET_PIXELS >> 1) : 1,
    parameter integer TARGET_HOLD_FRAMES = 10, // Hold ten missed frames; lose lock on the eleventh. Zero disables holding.
    //【抖动抑制】模板跟踪框显示坐标一阶逼近参数（只影响 OSD 画框，不影响搜索与判定）。
    // 置 0 可关闭平滑，使 template_cx/cy 严格等于跟踪中心（回归测试用）。
    parameter integer TEMPLATE_DISP_SMOOTH_SHIFT = 2,
    parameter integer TEMPLATE_DISP_DEADBAND = 2,
    //【过曝检测】逐通道削顶门限。旧实现只看 BT.601 灰度 >= 245，暖光/单色高亮场景下
    // 灰度可能只有 210 左右（例如 R=255,G=200,B=180 时灰度仅 214），AE 完全看不见这类
    // 削顶，于是越调越亮直到整片死白。改为"任一通道接近削顶且整体亮度不低"。
    parameter [7:0] HIGHLIGHT_CHANNEL_LEVEL = 8'd250, // 单通道削顶门限，取满量程 255 的 98%。
    parameter [7:0] HIGHLIGHT_LUMA_GATE = 8'd180, // 参与削顶判定的最低整体亮度，用于排除纯色物体。
    parameter [7:0] HIGHLIGHT_LUMA_LEVEL = 8'd245 // 原有灰度门限，保留用于中性灰近削顶场景。
>>>>>>> Stashed changes
) (
    input wire I_clk, input wire I_rst_n,
    input wire I_vsync, input wire I_hsync, input wire I_de,
    input wire I_user, input wire I_last, input wire [23:0] I_rgb,
    input wire [2:0] I_mode,
    input wire [1:0] I_exposure_level, //【HX1P35A-移植适配】在 HDMI OSD 中显示当前曝光档位。
    input wire I_auto_exposure, //【HX1P35A-移植适配】OSD 显示 AUTO 状态。
    output reg O_vsync, output reg O_hsync, output reg O_de,
    output reg O_user, output reg O_last, output reg [23:0] O_rgb,
    output reg O_target_found, output reg [23:0] O_target_pixels,
    output reg [7:0] O_frame_luma, //【HX1P35A-移植适配】整帧稀疏采样平均亮度，供自动曝光使用。
    output reg [11:0] O_frame_highlights, //【HX1P35A-移植适配】逐帧接近饱和样点数量，供自动曝光保护高光。
    output reg [11:0] O_frame_shadows, //【HX1P35A-移植适配】逐帧深暗样点数量，防止高光保护把主体压成全黑。
    output reg O_frame_luma_toggle //【HX1P35A-移植适配】每完成一帧翻转，用于跨时钟域传递亮度。
);
    //【HX1P35A-移植适配】坐标使用 VTC 的 user/last 标志；frame_start 当前像素固定为 (0,0)。
    reg [10:0] x, y;
    wire frame_start = I_user && I_de;
    wire [10:0] pix_x = frame_start ? 11'd0 : x;
    wire [10:0] pix_y = frame_start ? 11'd0 : y;

    //【HX1P35A-移植适配】BT.601 灰度近似，最大值 65280，不发生 16 位溢出。
    wire [15:0] gray_sum = I_rgb[23:16] * 8'd77 + I_rgb[15:8] * 8'd150 + I_rgb[7:0] * 8'd29;
    wire [7:0] gray = gray_sum[15:8];

    //【HX1P35A-移植适配】每 16 行、每 16 像素取样一次；3600 个样点除以 4096 得到 0~224 的稳定亮度量。
    wire luma_sample = I_de && (pix_x[3:0] == 4'd0) && (pix_y[3:0] == 4'd0); //【HX1P35A-移植适配】覆盖整幅画面而非局部亮点。
    //【过曝检测】三通道取最大值：三个比较器加两个二选一，约 3 个 LUT6，无额外时序压力。
    wire [7:0] max_channel = (I_rgb[23:16] >= I_rgb[15:8])
        ? ((I_rgb[23:16] >= I_rgb[7:0]) ? I_rgb[23:16] : I_rgb[7:0])
        : ((I_rgb[15:8]  >= I_rgb[7:0]) ? I_rgb[15:8]  : I_rgb[7:0]);
    //【过曝检测】"某通道削顶 + 整体亮度不低" 才算过曝。
    //   - 暖光灯 R=255/G=200/B=180：max=255 且灰度 214 >= 180 → 判为过曝（旧实现漏判）。
    //   - 纯红物体 R=255/G=20/B=20：max=255 但灰度仅 90 < 180 → 不判为过曝，避免 AE 把
    //     大面积饱和色物体误当削顶而压暗整幅画面。
    wire channel_clipped = (max_channel >= HIGHLIGHT_CHANNEL_LEVEL) && (gray >= HIGHLIGHT_LUMA_GATE);
    wire highlight_pixel = channel_clipped || (gray >= HIGHLIGHT_LUMA_LEVEL); // 中性灰近削顶仍按原门限统计。
    wire highlight_sample = luma_sample && highlight_pixel; //【HX1P35A-移植适配】只统计真正接近削顶的高光，避免把正常浅色墙面误作过曝。
    wire shadow_sample = luma_sample && (gray <= 8'd48); //【HX1P35A-移植适配】统计缺少可辨纹理的深暗区域，用于亮暗共存测光。
    reg [19:0] frame_luma_sum; //【HX1P35A-移植适配】最大 3600*255，小于 20 位上限。
    reg [11:0] frame_highlight_count; //【HX1P35A-移植适配】3600 个样点的高光计数。
    reg [11:0] frame_shadow_count; //【HX1P35A-移植适配】3600 个样点的深暗计数。

    //【HX1P35A-移植适配】第一组两行缓存构成 3x3 Gaussian 窗口，先抑制传感器噪点和高频细碎纹理。
    reg [7:0] raw_gray_line1 [0:IMAGE_WIDTH-1]; //【HX1P35A-移植适配】Gaussian 原始灰度上一行缓存。
    reg [7:0] raw_gray_line2 [0:IMAGE_WIDTH-1]; //【HX1P35A-移植适配】Gaussian 原始灰度上两行缓存。
    reg [7:0] raw_top_d2, raw_top_d1, raw_mid_d2, raw_mid_d1, raw_bot_d2, raw_bot_d1; //【HX1P35A-移植适配】Gaussian 3x3 滑动窗口。
    wire [7:0] raw_top_right = (pix_x < IMAGE_WIDTH) ? raw_gray_line2[pix_x] : 8'd0; //【HX1P35A-移植适配】Gaussian 窗口右上像素。
    wire [7:0] raw_mid_right = (pix_x < IMAGE_WIDTH) ? raw_gray_line1[pix_x] : 8'd0; //【HX1P35A-移植适配】Gaussian 窗口右中像素。
    wire [11:0] gaussian_sum = {4'd0,raw_top_d2} + ({4'd0,raw_top_d1} << 1) + {4'd0,raw_top_right} +
                               ({4'd0,raw_mid_d2} << 1) + ({4'd0,raw_mid_d1} << 2) + ({4'd0,raw_mid_right} << 1) +
                               {4'd0,raw_bot_d2} + ({4'd0,raw_bot_d1} << 1) + {4'd0,gray}; //【HX1P35A-移植适配】1-2-1 Gaussian 核，总权重 16。
    wire [7:0] gaussian_gray = gaussian_sum[11:4]; //【HX1P35A-移植适配】右移四位归一化，无需除法器。
    reg [7:0] gaussian_gray_q; //【HX1P35A-移植适配】Gaussian 输出寄存一级，切断平滑与 Sobel 之间的长组合路径。
    reg [10:0] gaussian_x_q, gaussian_y_q; //【HX1P35A-移植适配】随 Gaussian 数据延迟的像素坐标。
    reg gaussian_de_q; //【HX1P35A-移植适配】随 Gaussian 数据延迟的有效标志。

    //【HX1P35A-移植适配】第二组两行缓存对 Gaussian 输出执行真正的 3x3 Sobel。
    reg [7:0] gray_line1 [0:IMAGE_WIDTH-1];
    reg [7:0] gray_line2 [0:IMAGE_WIDTH-1];
    reg [7:0] top_d2, top_d1, mid_d2, mid_d1, bot_d2, bot_d1;
    wire [7:0] top_right = (gaussian_x_q < IMAGE_WIDTH) ? gray_line2[gaussian_x_q] : 8'd0; //【HX1P35A-移植适配】按流水坐标读取 Gaussian 上两行。
    wire [7:0] mid_right = (gaussian_x_q < IMAGE_WIDTH) ? gray_line1[gaussian_x_q] : 8'd0; //【HX1P35A-移植适配】按流水坐标读取 Gaussian 上一行。
    wire [10:0] gx_pos = {3'd0,top_right} + ({3'd0,mid_right} << 1) + {3'd0,gaussian_gray_q}; //【HX1P35A-移植适配】Sobel 右下输入使用寄存后的 Gaussian 像素。
    wire [10:0] gx_neg = {3'd0,top_d2} + ({3'd0,mid_d2} << 1) + {3'd0,bot_d2};
    wire [10:0] gy_pos = {3'd0,top_d2} + ({3'd0,top_d1} << 1) + {3'd0,top_right};
    wire [10:0] gy_neg = {3'd0,bot_d2} + ({3'd0,bot_d1} << 1) + {3'd0,gaussian_gray_q}; //【HX1P35A-移植适配】Sobel 下行输入使用寄存后的 Gaussian 像素。
    wire [10:0] gx_abs = (gx_pos >= gx_neg) ? (gx_pos - gx_neg) : (gx_neg - gx_pos);
    wire [10:0] gy_abs = (gy_pos >= gy_neg) ? (gy_pos - gy_neg) : (gy_neg - gy_pos);
    wire [11:0] sobel_mag = {1'b0,gx_abs} + {1'b0,gy_abs};
    wire sobel_valid = gaussian_de_q && (gaussian_x_q >= 11'd4) && (gaussian_y_q >= 11'd4); //【HX1P35A-移植适配】使用延迟坐标判断 Gaussian 与 Sobel 两级窗口完整。
    wire local_dark_region = (top_d2 < 8'd96); //【HX1P35A-移植适配】top_d2 与 NMS 中心梯度对齐，明窗与暗墙可分别选择门限。
    wire local_bright_region = (top_d2 >= 8'd176); //【HX1P35A-移植适配】局部高亮区域继续使用严格门限，防止窗格和灯具周围铺满噪声。
    wire [11:0] sobel_threshold = local_dark_region ? SOBEL_THRESHOLD_DARK :
                                  local_bright_region ? SOBEL_THRESHOLD_BRIGHT : SOBEL_THRESHOLD_NORMAL; //【HX1P35A-移植适配】按局部而非整帧亮度选择弱门限，保留同帧暗区细节。
    wire [11:0] sobel_strong_threshold = local_dark_region ? SOBEL_STRONG_THRESHOLD_DARK :
                                         local_bright_region ? SOBEL_STRONG_THRESHOLD_BRIGHT : SOBEL_STRONG_THRESHOLD_NORMAL; //【HX1P35A-移植适配】局部强门限为暗墙弱轮廓提供锚点。
    wire [11:0] sobel_detail_threshold = local_dark_region ? SOBEL_DETAIL_THRESHOLD_DARK :
                                         local_bright_region ? SOBEL_DETAIL_THRESHOLD_BRIGHT : SOBEL_DETAIL_THRESHOLD_NORMAL; //【HX1P35A-移植适配】非 NMS 强细节也按局部亮度选择，线宽策略保持不变。
    wire gx_dominant = {1'b0,gx_abs} >= ({1'b0,gy_abs} << 1); //【HX1P35A-移植适配】梯度接近水平方向，局部峰值沿左右比较。
    wire gy_dominant = {1'b0,gy_abs} >= ({1'b0,gx_abs} << 1); //【HX1P35A-移植适配】梯度接近垂直方向，局部峰值沿上下比较。
    wire gx_positive = (gx_pos >= gx_neg); //【HX1P35A-移植适配】保留 Gx 符号以区分两种对角方向。
    wire gy_positive = (gy_pos >= gy_neg); //【HX1P35A-移植适配】保留 Gy 符号以区分两种对角方向。
    wire [1:0] sobel_direction = gx_dominant ? 2'd0 : gy_dominant ? 2'd2 :
                                  ((gx_positive == gy_positive) ? 2'd1 : 2'd3); //【HX1P35A-移植适配】量化为 0/45/90/135 度四方向。
    reg [11:0] mag_line1 [0:IMAGE_WIDTH-1]; //【HX1P35A-移植适配】保存上一行 Sobel 幅值，构成局部极大值窗口。
    reg [11:0] mag_line2 [0:IMAGE_WIDTH-1]; //【HX1P35A-移植适配】保存上两行 Sobel 幅值，供纵向梯度峰值比较。
    reg [1:0]   dir_line1 [0:IMAGE_WIDTH-1]; //【HX1P35A-移植适配】保存上一行四方向梯度编码。
    reg [11:0] mag_top_d2, mag_top_d1, mag_mid_d2, mag_mid_d1, mag_bot_d2, mag_bot_d1; //【HX1P35A-移植适配】Sobel 幅值 3x3 滑动窗口。
    reg [1:0] dir_mid_d2, dir_mid_d1; //【HX1P35A-移植适配】上一行相邻像素的四方向梯度编码。
    wire [11:0] mag_top_right = (gaussian_x_q < IMAGE_WIDTH) ? mag_line2[gaussian_x_q] : 12'd0; //【HX1P35A-移植适配】按流水坐标读取局部极大值窗口右上幅值。
    wire [11:0] mag_mid_right = (gaussian_x_q < IMAGE_WIDTH) ? mag_line1[gaussian_x_q] : 12'd0; //【HX1P35A-移植适配】按流水坐标读取局部极大值窗口右侧幅值。
    wire [1:0] dir_mid_right = (gaussian_x_q < IMAGE_WIDTH) ? dir_line1[gaussian_x_q] : 2'd0; //【HX1P35A-移植适配】按流水坐标读取上一行四方向编码。
    wire nms_valid = sobel_valid && (gaussian_x_q >= 11'd6) && (gaussian_y_q >= 11'd6); //【HX1P35A-移植适配】使用延迟坐标等待三级窗口全部完整。
    reg nms_peak; //【HX1P35A-移植适配】四方向局部极大值判断结果。
    always @(*) begin
        case (dir_mid_d1)
            2'd0: nms_peak = (mag_mid_d1 >= mag_mid_d2) && (mag_mid_d1 > mag_mid_right); //【HX1P35A-移植适配】0 度：比较左右梯度幅值。
            2'd1: nms_peak = (mag_mid_d1 >= mag_top_right) && (mag_mid_d1 > mag_bot_d2); //【HX1P35A-移植适配】45 度：比较右上与左下幅值。
            2'd2: nms_peak = (mag_mid_d1 >= mag_top_d1) && (mag_mid_d1 > mag_bot_d1); //【HX1P35A-移植适配】90 度：比较上下梯度幅值。
            default: nms_peak = (mag_mid_d1 >= mag_top_d2) && (mag_mid_d1 > sobel_mag); //【HX1P35A-移植适配】135 度：比较左上与右下幅值。
        endcase
    end
    wire weak_edge_pixel = nms_valid && nms_peak && (mag_mid_d1 >= sobel_threshold); //【HX1P35A-移植适配】细化后的弱边缘候选，用于补全低对比度轮廓。
    wire strong_edge_pixel = nms_valid && nms_peak && (mag_mid_d1 >= sobel_strong_threshold); //【HX1P35A-移植适配】强边缘作为滞后筛选锚点。
    reg weak_line [0:IMAGE_WIDTH-1]; //【HX1P35A-移植适配】保存上一行弱边缘，用连续性恢复人物纹理和灯管等低对比结构。
    reg weak_left, weak_above_left; //【HX1P35A-移植适配】当前行左邻及上一行左上弱边缘状态。
    wire weak_above = (gaussian_x_q < IMAGE_WIDTH) ? weak_line[gaussian_x_q] : 1'b0; //【HX1P35A-移植适配】读取上一行同列弱边缘。
    wire weak_above_right = (gaussian_x_q < IMAGE_WIDTH-1) ? weak_line[gaussian_x_q+1'b1] : 1'b0; //【HX1P35A-移植适配】读取上一行右上弱边缘，保留另一方向斜线。
    wire weak_connected_to_weak = ((gaussian_x_q != 0) && weak_left) || weak_above || ((gaussian_x_q != 0) && weak_above_left) || weak_above_right; //【HX1P35A-移植适配】只有形成连续结构的弱边缘才可独立进入输出。
    wire coherent_weak_edge = weak_edge_pixel && weak_connected_to_weak; //【HX1P35A-移植适配】恢复连续弱纹理，仍拒绝孤立的传感器噪点。
    reg strong_line [0:IMAGE_WIDTH-1]; //【HX1P35A-移植适配】保存上一行强边缘，建立因果 3 邻域连接关系。
    reg strong_left, strong_above_left; //【HX1P35A-移植适配】当前行左邻和上一行左上邻强边缘状态。
    wire strong_above = (gaussian_x_q < IMAGE_WIDTH) ? strong_line[gaussian_x_q] : 1'b0; //【HX1P35A-移植适配】按流水坐标读取上一行同列强边缘。
    wire strong_above_right = (gaussian_x_q < IMAGE_WIDTH-1) ? strong_line[gaussian_x_q+1'b1] : 1'b0; //【HX1P35A-移植适配】上一行右上像素尚未被本行覆盖，可补齐另一方向的斜线连接。
    wire weak_connected_to_strong = ((gaussian_x_q != 0) && strong_left) || strong_above || ((gaussian_x_q != 0) && strong_above_left) || strong_above_right; //【HX1P35A-移植适配】使用完整的因果四邻域连接强弱边缘，减少斜向细节断裂。
    wire edge_seed = strong_edge_pixel || (weak_edge_pixel && weak_connected_to_strong); //【HX1P35A-移植适配】第一步只接受强边缘及其直接相邻弱边缘。
    reg bridge_line [0:IMAGE_WIDTH-1]; //【HX1P35A-移植适配】保存第一步边缘种子，仅供一次受控断点连接。
    reg bridge_left, bridge_above_left; //【HX1P35A-移植适配】保存边缘种子的左邻与左上邻状态。
    wire bridge_above = (gaussian_x_q < IMAGE_WIDTH) ? bridge_line[gaussian_x_q] : 1'b0; //【HX1P35A-移植适配】读取上一行同列边缘种子。
    wire bridge_above_right = (gaussian_x_q < IMAGE_WIDTH-1) ? bridge_line[gaussian_x_q+1'b1] : 1'b0; //【HX1P35A-移植适配】补充右上方向的一次性弱边缘连接。
    wire weak_connected_to_seed = ((gaussian_x_q != 0) && bridge_left) || bridge_above || ((gaussian_x_q != 0) && bridge_above_left) || bridge_above_right; //【HX1P35A-移植适配】允许弱边缘沿四个已到达方向延伸一个像素，但不无限传播。
    wire edge_pixel = edge_seed || (weak_edge_pixel && weak_connected_to_seed); //【HX1P35A-移植适配】补齐短断点但不回写最终结果，阻止弱纹理无限传播。
    //【HX1P35A-移植适配】参考流式 Canny 的 3x3 行缓存做法，将双阈值候选延迟到窗口中心再判定。
    // 这样弱边能看到右侧、下侧的强边锚点，补足仅按扫描方向判断时容易丢失的灯管、发丝和斜线。
    reg weak_hyst_line1 [0:IMAGE_WIDTH-1], weak_hyst_line2 [0:IMAGE_WIDTH-1];
    reg strong_hyst_line1 [0:IMAGE_WIDTH-1], strong_hyst_line2 [0:IMAGE_WIDTH-1];
    reg weak_hyst_top_d2, weak_hyst_top_d1, weak_hyst_mid_d2, weak_hyst_mid_d1, weak_hyst_bot_d2, weak_hyst_bot_d1;
    reg strong_hyst_top_d2, strong_hyst_top_d1, strong_hyst_mid_d2, strong_hyst_mid_d1, strong_hyst_bot_d2, strong_hyst_bot_d1;
    wire weak_hyst_top_right = (gaussian_x_q < IMAGE_WIDTH) ? weak_hyst_line2[gaussian_x_q] : 1'b0;
    wire weak_hyst_mid_right = (gaussian_x_q < IMAGE_WIDTH) ? weak_hyst_line1[gaussian_x_q] : 1'b0;
    wire strong_hyst_top_right = (gaussian_x_q < IMAGE_WIDTH) ? strong_hyst_line2[gaussian_x_q] : 1'b0;
    wire strong_hyst_mid_right = (gaussian_x_q < IMAGE_WIDTH) ? strong_hyst_line1[gaussian_x_q] : 1'b0;
    wire hyst_window_valid = nms_valid && (gaussian_x_q >= 11'd8) && (gaussian_y_q >= 11'd8); //【HX1P35A-移植适配】等待候选的完整 3x3 窗口，边界不引用上一帧残留。
    wire strong_hyst_neighborhood = strong_hyst_top_d2 || strong_hyst_top_d1 || strong_hyst_top_right ||
                                    strong_hyst_mid_d2 || strong_hyst_mid_right ||
                                    strong_hyst_bot_d2 || strong_hyst_bot_d1 || strong_edge_pixel; //【HX1P35A-移植适配】中心以外的八个方向均可作为弱边的强锚点。
    wire weak_hyst_any_a = weak_hyst_top_d2 || weak_hyst_top_d1 || weak_hyst_top_right || weak_hyst_mid_d2;
    wire weak_hyst_any_b = weak_hyst_mid_right || weak_hyst_bot_d2 || weak_hyst_bot_d1 || weak_edge_pixel;
    wire weak_hyst_pair_a = (weak_hyst_top_d2 && (weak_hyst_top_d1 || weak_hyst_top_right || weak_hyst_mid_d2)) ||
                            (weak_hyst_top_d1 && (weak_hyst_top_right || weak_hyst_mid_d2)) ||
                            (weak_hyst_top_right && weak_hyst_mid_d2);
    wire weak_hyst_pair_b = (weak_hyst_mid_right && (weak_hyst_bot_d2 || weak_hyst_bot_d1 || weak_edge_pixel)) ||
                            (weak_hyst_bot_d2 && (weak_hyst_bot_d1 || weak_edge_pixel)) ||
                            (weak_hyst_bot_d1 && weak_edge_pixel);
    wire weak_hyst_has_two_neighbors = weak_hyst_pair_a || weak_hyst_pair_b || (weak_hyst_any_a && weak_hyst_any_b); //【HX1P35A-移植适配】并行判断八邻域至少两个弱候选，避免串行加法器进入像素关键路径。
    wire symmetric_hyst_edge = hyst_window_valid && weak_hyst_mid_d1 && strong_hyst_neighborhood &&
                               weak_hyst_has_two_neighbors; //【HX1P35A-移植适配】仅救回连接强边且自身形成连续结构的弱边；强边由原通路输出，避免重复加粗孤立噪点。
    wire detail_edge_pixel = nms_valid && (mag_mid_d1 >= sobel_detail_threshold); //【HX1P35A-移植适配】对足够强的梯度取消局部极大值限制，恢复参考效果中的粗亮细节。
    wire edge_core = edge_pixel || symmetric_hyst_edge || coherent_weak_edge || detail_edge_pixel; //【HX1P35A-移植适配】融合因果连接、对称 8 邻域连接、连续弱纹理与强细节。
    reg edge_core_q, edge_core_de_q; //【HX1P35A-移植适配】融合边缘增加一级寄存，切断梯度比较到 HDMI 输出的长组合路径。
    reg [10:0] edge_x_q; //【HX1P35A-移植适配】保存融合边缘对应横坐标，驱动后级加粗行缓存。
    reg edge_dilate_line [0:IMAGE_WIDTH-1]; //【HX1P35A-移植适配】保存上一行融合边缘，用于低成本 2x2 形态学膨胀。
    reg edge_dilate_left, edge_dilate_above_left; //【HX1P35A-移植适配】保存左邻和左上邻边缘，提升 HDMI 上的线条可见度。
    wire edge_dilate_above = (edge_x_q < IMAGE_WIDTH) ? edge_dilate_line[edge_x_q] : 1'b0; //【HX1P35A-移植适配】读取上一行同列融合边缘。
    wire edge_display_pixel = edge_core_q ||
                              ((edge_x_q != 0) && edge_dilate_left) ||
                              edge_dilate_above ||
                              ((edge_x_q != 0) && edge_dilate_above_left); //【HX1P35A-移植适配】边缘向右、向下各扩展一像素，接近参考画面的粗亮轮廓。

    //【GRAD 模式】梯度幅值灰阶显示：取 NMS 中心对齐的 Gaussian+Sobel 幅值，
    // 只做移位缩放和饱和，不经过局部极大值抑制、双阈值和滞后连接，
    // 因此输出连续灰阶（平坦区黑、弱边灰、强边白）而非二值细线。
    wire [11:0] grad_scaled = mag_mid_d1 >> GRAD_SHIFT;
    wire [7:0] grad_gray = (grad_scaled[11:8] != 4'd0) ? 8'd255 : grad_scaled[7:0];

    //【HX1P35A-移植适配】先用亮度与通道差筛选颜色候选，再用同色邻域一致性抑制暗光 Bayer/增益噪点。
    wire raw_red_hit = (I_rgb[23:16] >= 8'd96) && ({1'b0,I_rgb[23:16]} >= ({1'b0,I_rgb[15:8]} + 9'd40)) && ({1'b0,I_rgb[23:16]} >= ({1'b0,I_rgb[7:0]} + 9'd40)); //【HX1P35A-移植适配】红色候选需具备足够亮度和饱和度。
    wire raw_green_hit = (I_rgb[15:8] >= 8'd64) && ({1'b0,I_rgb[15:8]} >= ({1'b0,I_rgb[23:16]} + 9'd16)) && ({1'b0,I_rgb[15:8]} >= ({1'b0,I_rgb[7:0]} + 9'd16)); //【HX1P35A-移植适配】放宽绿色候选以识别偏暗、印刷和偏黄绿色包装；邻域一致性继续过滤孤立噪点。
    wire raw_blue_hit = (I_rgb[7:0] >= 8'd96) && ({1'b0,I_rgb[7:0]} >= ({1'b0,I_rgb[23:16]} + 9'd40)) && ({1'b0,I_rgb[7:0]} >= ({1'b0,I_rgb[15:8]} + 9'd40)); //【HX1P35A-移植适配】蓝色候选需具备足够亮度和饱和度。
    wire [1:0] raw_color = raw_red_hit ? 2'd1 : raw_green_hit ? 2'd2 : raw_blue_hit ? 2'd3 : 2'd0; //【HX1P35A-移植适配】将三色候选编码后共用一套行邻域滤波器。
    reg [1:0] color_line [0:IMAGE_WIDTH-1]; //【HX1P35A-移植适配】保存上一行原始颜色候选，用于排除孤立色噪点。
    reg [1:0] color_left, color_above_left; //【HX1P35A-移植适配】保存当前行左邻及上一行左上邻的原始颜色。
    wire [1:0] color_above = ((pix_y != 0) && (pix_x < IMAGE_WIDTH)) ? color_line[pix_x] : 2'd0; //【HX1P35A-移植适配】首行不引用上一帧残留行缓存。
    wire color_match_left = (pix_x != 0) && (raw_color != 0) && (raw_color == color_left); //【HX1P35A-移植适配】当前颜色与左邻一致。
    wire color_match_above = (raw_color != 0) && (raw_color == color_above); //【HX1P35A-移植适配】当前颜色与上邻一致。
    wire color_match_above_left = (pix_x != 0) && (pix_y != 0) && (raw_color != 0) && (raw_color == color_above_left); //【HX1P35A-移植适配】当前颜色与左上邻一致。
    wire color_coherent = (color_match_left && color_match_above) || (color_match_left && color_match_above_left) || (color_match_above && color_match_above_left); //【HX1P35A-移植适配】三个已到达邻居中至少两个同色才确认目标像素。
    wire red_hit = I_de && color_coherent && (raw_color == 2'd1); //【HX1P35A-移植适配】仅连续成片的红色像素进入显示、统计和告警。
    wire green_hit = I_de && color_coherent && (raw_color == 2'd2); //【HX1P35A-移植适配】仅连续成片的绿色像素进入显示、统计和告警。
    wire blue_hit = I_de && color_coherent && (raw_color == 2'd3); //【HX1P35A-移植适配】仅连续成片的蓝色像素进入显示、统计和告警。
    wire target_hit = I_de && (red_hit || green_hit || blue_hit);
    wire [23:0] target_mask_rgb = red_hit ? 24'hff0000 : green_hit ? 24'h00ff00 : blue_hit ? 24'h0000ff : 24'h000000;
    wire [23:0] dim_rgb = {1'b0,I_rgb[23:17],1'b0,I_rgb[15:9],1'b0,I_rgb[7:1]}; //【HX1P35A-移植适配】保留半亮原图作为 COLOR 背景。
    wire [23:0] color_overlay_rgb = target_hit ? target_mask_rgb : dim_rgb; //【HX1P35A-移植适配】目标高亮，未命中区域仍可观察。

<<<<<<< Updated upstream
=======
    //【资源优化】ERAM 在 I_clk 下降沿预读当前地址，上升沿沿用原流水处理并写回，避免增加整拍延迟。
    hx_eram_line_store #(.DATA_WIDTH(18)) u_raw_color_line_store (
        .clk(I_clk), .rd_addr(pix_x), .wr_addr(pix_x),
        .wr_en(I_de && (pix_x < IMAGE_WIDTH)), .wr_data(raw_line_wr), .rd_data(raw_line_rd)
    );
    hx_eram_line_store #(.DATA_WIDTH(46)) u_edge_line_store (
        .clk(I_clk), .rd_addr(gaussian_x_q), .wr_addr(gaussian_x_d),
        .wr_en(gaussian_de_d && (gaussian_x_d < IMAGE_WIDTH)), .wr_data(edge_line_wr), .rd_data(edge_line_rd)
    );
    hx_eram_line_store #(.DATA_WIDTH(1)) u_dilate_line_store (
        .clk(I_clk), .rd_addr(refined_x), .wr_addr(refined_x),
        .wr_en(refined_de && (refined_x < IMAGE_WIDTH)), .wr_data(refined_edge), .rd_data(dilate_line_rd)
    );

    wire raw_sharpen_selected = ENABLE_RAW_SHARPEN && I_raw_sharpen_enable && (I_mode == 3'd0);
    wire [2:0] template_status;
    wire [3:0] template_reason;
    wire [14:0] template_best,template_margin;
    wire [4:0] template_misses;
    wire [10:0] template_cx,template_cy;
    generate if(ENABLE_TEMPLATE_TRACKING)begin : g_template
        hx_template_tracker #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT),
            .DISP_SMOOTH_SHIFT(TEMPLATE_DISP_SMOOTH_SHIFT),.DISP_DEADBAND(TEMPLATE_DISP_DEADBAND)) u_tracker (
            .clk(I_clk),.rst_n(I_rst_n),.command(I_template_command),
            .de(gaussian_de_q),.x(gaussian_x_q),.y(gaussian_y_q),.luma(gaussian_gray_q),
            .status(template_status),.center_x(template_cx),.center_y(template_cy),.busy(),
            .debug_reason(template_reason),.debug_best(template_best),
            .debug_margin(template_margin),.debug_misses(template_misses)
        );
    end else begin : g_no_template
        assign template_status=0;assign template_cx=IMAGE_WIDTH/2;assign template_cy=IMAGE_HEIGHT/2;
        assign template_reason=0;assign template_best=0;assign template_margin=0;assign template_misses=0;
    end endgenerate

>>>>>>> Stashed changes
    //【HX1P35A-移植适配】逐帧统计目标总面积、各颜色面积和外接矩形。
    reg [10:0] cur_xmin, cur_xmax, cur_ymin, cur_ymax;
    reg [10:0] box_xmin, box_xmax, box_ymin, box_ymax;
    reg [23:0] cur_count, cur_red_count, cur_green_count, cur_blue_count;
    reg [1:0] box_color; // 0:无，1:红，2:绿，3:蓝。【HX1P35A-移植适配】
    wire cur_frame_valid = (cur_count >= MIN_TARGET_PIXELS);

    //【HX1P35A-移植适配】连续检测时对包围框做 1/2 帧间平滑，减小边框抖动。
    wire [10:0] next_box_xmin = (cur_frame_valid && O_target_found) ? (({1'b0,box_xmin}+{1'b0,cur_xmin}) >> 1) : cur_xmin;
    wire [10:0] next_box_xmax = (cur_frame_valid && O_target_found) ? (({1'b0,box_xmax}+{1'b0,cur_xmax}) >> 1) : cur_xmax;
    wire [10:0] next_box_ymin = (cur_frame_valid && O_target_found) ? (({1'b0,box_ymin}+{1'b0,cur_ymin}) >> 1) : cur_ymin;
    wire [10:0] next_box_ymax = (cur_frame_valid && O_target_found) ? (({1'b0,box_ymax}+{1'b0,cur_ymax}) >> 1) : cur_ymax;
    wire [11:0] next_center_x_sum = {1'b0,next_box_xmin} + {1'b0,next_box_xmax};
    wire [11:0] next_center_y_sum = {1'b0,next_box_ymin} + {1'b0,next_box_ymax};
    wire [10:0] next_center_x = next_center_x_sum[11:1];
    wire [10:0] next_center_y = next_center_y_sum[11:1];
    wire [23:0] clipped_count = (cur_count > 24'd999999) ? 24'd999999 : cur_count;

    //【HX1P35A-移植适配】Double-Dabble 转 BCD，仅在帧边界锁存，避免像素域使用除法器。
    function [15:0] bin11_to_bcd4;
        input [10:0] bin;
        integer i, j;
        reg [15:0] bcd;
        begin
            bcd = 16'd0;
            for (i=10; i>=0; i=i-1) begin
                for (j=0; j<4; j=j+1)
                    if (bcd[j*4 +: 4] >= 5) bcd[j*4 +: 4] = bcd[j*4 +: 4] + 3;
                bcd = {bcd[14:0],bin[i]};
            end
            bin11_to_bcd4 = bcd;
        end
    endfunction

    function [23:0] bin24_to_bcd6;
        input [23:0] bin;
        integer i, j;
        reg [23:0] bcd;
        begin
            bcd = 24'd0;
            for (i=23; i>=0; i=i-1) begin
                for (j=0; j<6; j=j+1)
                    if (bcd[j*4 +: 4] >= 5) bcd[j*4 +: 4] = bcd[j*4 +: 4] + 3;
                bcd = {bcd[22:0],bin[i]};
            end
            bin24_to_bcd6 = bcd;
        end
    endfunction

    reg [15:0] center_x_bcd, center_y_bcd;
    reg [23:0] pixel_count_bcd;

    //【HX1P35A-移植适配】5x7 字模，2 倍放大后在 HDMI 顶部显示模式、主颜色、坐标和面积。
    function [4:0] font5x7;
        input [7:0] ch;
        input [2:0] row;
        begin
            font5x7 = 5'b00000;
            case (ch)
                "0": case(row) 0:font5x7=5'b01110;1:font5x7=5'b10001;2:font5x7=5'b10011;3:font5x7=5'b10101;4:font5x7=5'b11001;5:font5x7=5'b10001;6:font5x7=5'b01110;endcase
                "1": case(row) 0:font5x7=5'b00100;1:font5x7=5'b01100;2:font5x7=5'b00100;3:font5x7=5'b00100;4:font5x7=5'b00100;5:font5x7=5'b00100;6:font5x7=5'b01110;endcase
                "2": case(row) 0:font5x7=5'b01110;1:font5x7=5'b10001;2:font5x7=5'b00001;3:font5x7=5'b00010;4:font5x7=5'b00100;5:font5x7=5'b01000;6:font5x7=5'b11111;endcase
                "3": case(row) 0:font5x7=5'b11110;1:font5x7=5'b00001;2:font5x7=5'b00001;3:font5x7=5'b01110;4:font5x7=5'b00001;5:font5x7=5'b00001;6:font5x7=5'b11110;endcase
                "4": case(row) 0:font5x7=5'b00010;1:font5x7=5'b00110;2:font5x7=5'b01010;3:font5x7=5'b10010;4:font5x7=5'b11111;5:font5x7=5'b00010;6:font5x7=5'b00010;endcase
                "5": case(row) 0:font5x7=5'b11111;1:font5x7=5'b10000;2:font5x7=5'b10000;3:font5x7=5'b11110;4:font5x7=5'b00001;5:font5x7=5'b00001;6:font5x7=5'b11110;endcase
                "6": case(row) 0:font5x7=5'b01110;1:font5x7=5'b10000;2:font5x7=5'b10000;3:font5x7=5'b11110;4:font5x7=5'b10001;5:font5x7=5'b10001;6:font5x7=5'b01110;endcase
                "7": case(row) 0:font5x7=5'b11111;1:font5x7=5'b00001;2:font5x7=5'b00010;3:font5x7=5'b00100;4:font5x7=5'b01000;5:font5x7=5'b01000;6:font5x7=5'b01000;endcase
                "8": case(row) 0:font5x7=5'b01110;1:font5x7=5'b10001;2:font5x7=5'b10001;3:font5x7=5'b01110;4:font5x7=5'b10001;5:font5x7=5'b10001;6:font5x7=5'b01110;endcase
                "9": case(row) 0:font5x7=5'b01110;1:font5x7=5'b10001;2:font5x7=5'b10001;3:font5x7=5'b01111;4:font5x7=5'b00001;5:font5x7=5'b00001;6:font5x7=5'b01110;endcase
                "A": case(row) 0:font5x7=5'b01110;1:font5x7=5'b10001;2:font5x7=5'b10001;3:font5x7=5'b11111;4:font5x7=5'b10001;5:font5x7=5'b10001;6:font5x7=5'b10001;endcase
                "B": case(row) 0:font5x7=5'b11110;1:font5x7=5'b10001;2:font5x7=5'b10001;3:font5x7=5'b11110;4:font5x7=5'b10001;5:font5x7=5'b10001;6:font5x7=5'b11110;endcase
                "C": case(row) 0:font5x7=5'b01111;1:font5x7=5'b10000;2:font5x7=5'b10000;3:font5x7=5'b10000;4:font5x7=5'b10000;5:font5x7=5'b10000;6:font5x7=5'b01111;endcase
                "D": case(row) 0:font5x7=5'b11110;1:font5x7=5'b10001;2:font5x7=5'b10001;3:font5x7=5'b10001;4:font5x7=5'b10001;5:font5x7=5'b10001;6:font5x7=5'b11110;endcase
                "E": case(row) 0:font5x7=5'b11111;1:font5x7=5'b10000;2:font5x7=5'b10000;3:font5x7=5'b11110;4:font5x7=5'b10000;5:font5x7=5'b10000;6:font5x7=5'b11111;endcase
                "G": case(row) 0:font5x7=5'b01111;1:font5x7=5'b10000;2:font5x7=5'b10000;3:font5x7=5'b10111;4:font5x7=5'b10001;5:font5x7=5'b10001;6:font5x7=5'b01111;endcase
                "L": case(row) 0:font5x7=5'b10000;1:font5x7=5'b10000;2:font5x7=5'b10000;3:font5x7=5'b10000;4:font5x7=5'b10000;5:font5x7=5'b10000;6:font5x7=5'b11111;endcase
                "M": case(row) 0:font5x7=5'b10001;1:font5x7=5'b11011;2:font5x7=5'b10101;3:font5x7=5'b10101;4:font5x7=5'b10001;5:font5x7=5'b10001;6:font5x7=5'b10001;endcase
                "N": case(row) 0:font5x7=5'b10001;1:font5x7=5'b11001;2:font5x7=5'b11001;3:font5x7=5'b10101;4:font5x7=5'b10011;5:font5x7=5'b10011;6:font5x7=5'b10001;endcase //【HX1P35A-移植适配】CANNY 模式字模。
                "O": case(row) 0:font5x7=5'b01110;1:font5x7=5'b10001;2:font5x7=5'b10001;3:font5x7=5'b10001;4:font5x7=5'b10001;5:font5x7=5'b10001;6:font5x7=5'b01110;endcase
                "P": case(row) 0:font5x7=5'b11110;1:font5x7=5'b10001;2:font5x7=5'b10001;3:font5x7=5'b11110;4:font5x7=5'b10000;5:font5x7=5'b10000;6:font5x7=5'b10000;endcase
                "R": case(row) 0:font5x7=5'b11110;1:font5x7=5'b10001;2:font5x7=5'b10001;3:font5x7=5'b11110;4:font5x7=5'b10100;5:font5x7=5'b10010;6:font5x7=5'b10001;endcase
                "S": case(row) 0:font5x7=5'b01111;1:font5x7=5'b10000;2:font5x7=5'b10000;3:font5x7=5'b01110;4:font5x7=5'b00001;5:font5x7=5'b00001;6:font5x7=5'b11110;endcase
                "W": case(row) 0:font5x7=5'b10001;1:font5x7=5'b10001;2:font5x7=5'b10001;3:font5x7=5'b10101;4:font5x7=5'b10101;5:font5x7=5'b10101;6:font5x7=5'b01010;endcase
                "X": case(row) 0:font5x7=5'b10001;1:font5x7=5'b10001;2:font5x7=5'b01010;3:font5x7=5'b00100;4:font5x7=5'b01010;5:font5x7=5'b10001;6:font5x7=5'b10001;endcase
                "Y": case(row) 0:font5x7=5'b10001;1:font5x7=5'b10001;2:font5x7=5'b01010;3:font5x7=5'b00100;4:font5x7=5'b00100;5:font5x7=5'b00100;6:font5x7=5'b00100;endcase
                ":": case(row) 2:font5x7=5'b00100;4:font5x7=5'b00100;default:font5x7=5'b00000;endcase
                "-": case(row) 3:font5x7=5'b11111;default:font5x7=5'b00000;endcase
                default: font5x7=5'b00000;
            endcase
        end
    endfunction

    function [7:0] bcd_ascii;
        input [3:0] digit;
        begin bcd_ascii = "0" + digit; end
    endfunction

    //【HX1P35A-移植适配】将算法结果与叠加绘制拆成两级流水，保证 75MHz HDMI 像素时序。
    reg stage_vsync, stage_hsync, stage_de, stage_user, stage_last;
    reg [23:0] stage_rgb;
<<<<<<< Updated upstream
    reg [10:0] draw_x, draw_y;

    wire box_border = (I_mode == 2'd2) && O_target_found && stage_de && //【HX1P35A-移植适配】目标框只在 COLOR 模式显示，避免干扰 Sobel 观察。
=======
    reg [10:0] source_x, source_y;
    reg [2:0] prefetch_mode, stage_mode;
    reg prefetch_sharp, stage_sharp;
    wire [10:0] draw_x, draw_y, logo_input_x, logo_input_y;
    wire [4:0] final_ctrl;
    wire [23:0] final_rgb;
    wire [2:0] final_mode;
    wire logo_input_de;
    generate if (ENABLE_RAW_SHARPEN) begin : g_centered_display
        wire [55:0] delayed;
        wire signed [8:0] delta;
        reg [55:0] d1, d2;
        reg [23:0] enhanced1, enhanced2;
        hx_centered_display #(.IMAGE_WIDTH(IMAGE_WIDTH),
            .NOISE_GATE(RAW_SHARPEN_NOISE_GATE), .MAX_DELTA(RAW_SHARPEN_MAX_DELTA),
            .GAIN_SHIFT(RAW_SHARPEN_GAIN_SHIFT)) u_display (
            .clk(I_clk), .rst_n(I_rst_n),
            .payload({stage_mode==0,stage_sharp,stage_mode,
                stage_vsync,stage_hsync,stage_de,stage_user,stage_last,source_x,source_y,stage_rgb}),
            .delayed(delayed), .delta(delta)
        );
        function [7:0] adjust;
            input [7:0] value;
            input signed [8:0] amount;
            reg signed [9:0] result;
            begin
                result=$signed({1'b0,value})+amount;
                adjust=result<0 ? 8'd0 : result>255 ? 8'd255 : result[7:0];
            end
        endfunction
        always @(posedge I_clk or negedge I_rst_n) begin
            if(!I_rst_n) begin d1<=0; d2<=0; enhanced1<=0; enhanced2<=0; end
            else begin
                d1<=delayed; d2<=d1;
                enhanced1 <= delayed[54] ?
                    {adjust(delayed[23:16],delta),adjust(delayed[15:8],delta),adjust(delayed[7:0],delta)} : delayed[23:0];
                enhanced2<=enhanced1;
            end
        end
        assign logo_input_x=delayed[45:35];
        assign logo_input_y=delayed[34:24];
        assign logo_input_de=delayed[48];
        assign draw_x=d2[45:35]; assign draw_y=d2[34:24];
        assign final_ctrl=d2[50:46]; assign final_mode=d2[53:51]; assign final_rgb=enhanced2;
    end else begin : g_direct_display
        assign final_ctrl={stage_vsync,stage_hsync,stage_de,stage_user,stage_last};
        assign final_rgb=stage_rgb; assign final_mode=stage_mode;
        assign draw_x=source_x; assign draw_y=source_y;
        assign logo_input_x=pix_x; assign logo_input_y=pix_y; assign logo_input_de=I_de;
    end endgenerate

    // lab_ex3_osd/hdmi_mixer.v logo block, adapted to this pipeline's stage_rgb.
    // Keep the example's 160x160 addressing, RGB888 and bit-24 transparency.
    // Address prefetch and the complete video stream advance together. Output
    // latency is three registers. No crop, palette or colour conversion.
    localparam LOGO_X = IMAGE_WIDTH - 176;
    localparam LOGO_Y = 8;
    wire [24:0] logo_pixel_q;
    wire logo_active_q;
    generate if (ENABLE_ANLOGIC_LOGO && IMAGE_WIDTH >= 192) begin : g_anlogic_logo
        wire logo_active = logo_input_de && (logo_input_x >= LOGO_X) && (logo_input_x < LOGO_X+160) &&
                           (logo_input_y >= LOGO_Y) && (logo_input_y < LOGO_Y+160);
        wire [11:0] S_logo_x = logo_input_x - LOGO_X;
        wire [11:0] S_logo_y = logo_input_y - LOGO_Y;
        wire [14:0] S_logo_addr = logo_active ? (S_logo_y * 15'd160 + S_logo_x) : 15'd0;
        reg [14:0] addr_q;
        wire [24:0] S_logo_pixel;
        reg [24:0] pixel_q;
        reg active_q, active_d;
        assign logo_active_q = active_d;
        assign logo_pixel_q = pixel_q;
        anlogic_logo_rom u_anlogic_logo_rom (
            .I_addr(addr_q), .O_pixel(S_logo_pixel)
        );
        always @(posedge I_clk or negedge I_rst_n) begin
            if (!I_rst_n) begin active_q <= 1'b0; active_d <= 1'b0; addr_q <= 0; pixel_q <= 25'd0; end
            else begin addr_q <= S_logo_addr; active_q <= logo_active; active_d <= active_q; pixel_q <= S_logo_pixel; end
        end
    end else begin : g_anlogic_logo_disabled
        assign logo_pixel_q = 25'd0;
        assign logo_active_q = 1'b0;
    end endgenerate

    wire box_border = (final_mode == 3'd2) && O_target_found && final_ctrl[2] && // Display mode travels with its pixels.
>>>>>>> Stashed changes
        ((((draw_x == box_xmin) || (draw_x == box_xmax)) && (draw_y >= box_ymin) && (draw_y <= box_ymax)) ||
         (((draw_y == box_ymin) || (draw_y == box_ymax)) && (draw_x >= box_xmin) && (draw_x <= box_xmax)));

    wire [6:0] osd_col = draw_x[10:4];
    wire osd_line = draw_y[4];
    wire [2:0] glyph_x = draw_x[3:1];
    wire [2:0] glyph_y = draw_y[3:1];
    reg [7:0] osd_char;
    reg [23:0] osd_fg;
    wire [4:0] glyph_bits = font5x7(osd_char,glyph_y);
    wire osd_background = stage_de && (draw_x < 11'd432) && (draw_y < 11'd32);
    wire osd_glyph = osd_background && (glyph_x < 3'd5) && (glyph_y < 3'd7) && glyph_bits[4-glyph_x];
<<<<<<< Updated upstream
=======
    wire [23:0] osd_pixel_fg = template_osd_region ? template_fg : applied_osd_region ? applied_osd_fg : osd_fg;
    wire template_border=ENABLE_TEMPLATE_TRACKING && (final_mode <= 3'd1) && final_ctrl[2] &&
        ((((draw_x==template_cx-32)||(draw_x==template_cx+31)) && draw_y>=template_cy-32 && draw_y<template_cy+32) ||
         (((draw_y==template_cy-32)||(draw_y==template_cy+31)) && draw_x>=template_cx-32 && draw_x<template_cx+32));
>>>>>>> Stashed changes

    //【HX1P35A-移植适配】第一行显示算法模式和 EXP:0~3 曝光档；第二行显示主颜色、目标中心坐标和像素面积。
    always @(*) begin
        osd_char = " ";
        osd_fg = 24'hffffff;
        if (!osd_line) begin
            osd_fg = 24'h40e0ff;
            case (osd_col)
                0:osd_char="M"; 1:osd_char="O"; 2:osd_char="D"; 3:osd_char="E"; 4:osd_char=":";
                14:osd_char="E"; 15:osd_char="X"; 16:osd_char="P"; 17:osd_char=":"; 18:osd_char=I_auto_exposure ? "A" : bcd_ascii({2'b00,I_exposure_level}); //【HX1P35A-移植适配】自动曝光显示 EXP:A。
                default: begin
<<<<<<< Updated upstream
                    case (I_mode)
                        2'd0: case(osd_col) 6:osd_char="R";7:osd_char="A";8:osd_char="W";default:osd_char=" ";endcase
                        2'd1: case(osd_col) 6:osd_char="G";7:osd_char="R";8:osd_char="A";9:osd_char="Y";default:osd_char=" ";endcase
                        2'd2: case(osd_col) 6:osd_char="C";7:osd_char="O";8:osd_char="L";9:osd_char="O";10:osd_char="R";default:osd_char=" ";endcase
                        default: case(osd_col) 6:osd_char="C";7:osd_char="A";8:osd_char="N";9:osd_char="N";10:osd_char="Y";default:osd_char=" ";endcase //【HX1P35A-移植适配】全屏边缘模式升级为轻量 Canny。
=======
                    case (final_mode)
                        3'd0: case(osd_col)
                            6:osd_char="R";7:osd_char="A";8:osd_char="W";
                            9:osd_char=I_raw_sharpen_enable && ENABLE_RAW_SHARPEN ? "S" : " ";
                            10:osd_char=I_raw_sharpen_enable && ENABLE_RAW_SHARPEN ? "H" : " ";
                            11:osd_char=I_raw_sharpen_enable && ENABLE_RAW_SHARPEN ? "A" : " ";
                            12:osd_char=I_raw_sharpen_enable && ENABLE_RAW_SHARPEN ? "R" : " ";
                            13:osd_char=I_raw_sharpen_enable && ENABLE_RAW_SHARPEN ? "P" : " ";
                            default:osd_char=" ";
                        endcase
                        3'd1: case(osd_col) 6:osd_char="G";7:osd_char="R";8:osd_char="A";9:osd_char="Y";default:osd_char=" ";endcase
                        3'd2: case(osd_col) 6:osd_char="C";7:osd_char="O";8:osd_char="L";9:osd_char="O";10:osd_char="R";default:osd_char=" ";endcase
                        3'd3: case(osd_col) 6:osd_char="C";7:osd_char="A";8:osd_char="N";9:osd_char="N";10:osd_char="Y";default:osd_char=" ";endcase
                        default: case(osd_col) 6:osd_char="G";7:osd_char="R";8:osd_char="A";9:osd_char="D";default:osd_char=" ";endcase //【GRAD】梯度幅值灰阶模式。
>>>>>>> Stashed changes
                    endcase
                end
            endcase
        end else begin
            osd_fg = O_target_found ? 24'h60ff60 : 24'hff6060;
            case (osd_col)
                0:osd_char="C"; 1:osd_char=":";
                2:osd_char=!O_target_found ? "-" : (box_color==2'd1 ? "R" : box_color==2'd2 ? "G" : "B");
                4:osd_char="X"; 5:osd_char=":";
                6:osd_char=O_target_found ? bcd_ascii(center_x_bcd[15:12]) : "-";
                7:osd_char=O_target_found ? bcd_ascii(center_x_bcd[11:8])  : "-";
                8:osd_char=O_target_found ? bcd_ascii(center_x_bcd[7:4])   : "-";
                9:osd_char=O_target_found ? bcd_ascii(center_x_bcd[3:0])   : "-";
                11:osd_char="Y"; 12:osd_char=":";
                13:osd_char=O_target_found ? bcd_ascii(center_y_bcd[15:12]) : "-";
                14:osd_char=O_target_found ? bcd_ascii(center_y_bcd[11:8])  : "-";
                15:osd_char=O_target_found ? bcd_ascii(center_y_bcd[7:4])   : "-";
                16:osd_char=O_target_found ? bcd_ascii(center_y_bcd[3:0])   : "-";
                18:osd_char="P"; 19:osd_char=":";
                20:osd_char=O_target_found ? bcd_ascii(pixel_count_bcd[23:20]) : "-";
                21:osd_char=O_target_found ? bcd_ascii(pixel_count_bcd[19:16]) : "-";
                22:osd_char=O_target_found ? bcd_ascii(pixel_count_bcd[15:12]) : "-";
                23:osd_char=O_target_found ? bcd_ascii(pixel_count_bcd[11:8])  : "-";
                24:osd_char=O_target_found ? bcd_ascii(pixel_count_bcd[7:4])   : "-";
                25:osd_char=O_target_found ? bcd_ascii(pixel_count_bcd[3:0])   : "-";
                default:osd_char=" ";
            endcase
        end
    end

    reg [23:0] base_rgb;
<<<<<<< Updated upstream
=======
    // Do not feed the Canny/overlay mux into the denoiser's half-cycle path.
    // Other modes bypass filtering downstream; history only needs RAW/GRAY.
    wire [23:0] display_source = I_mode[0] ? {gray,gray,gray} : I_rgb;
    // Display-only, causal 2x2 filter: no line/coordinate displacement.
    // Reject the entire window if any channel differs by more than 24.
    // Thus equal-luma chromatic edges are protected as well as luma edges.
    wire [26:0] display_above;
    reg [26:0] display_left, display_above_left;
    reg [29:0] display_sum_q;
    reg display_flat_q;
    function near_rgb;
        input [23:0] a, b;
        integer c;
        reg [7:0] av, bv;
        begin
            near_rgb = 1'b1;
            for (c=0; c<3; c=c+1) begin
                av = a >> (c*8); bv = b >> (c*8);
                if ((av > bv ? av-bv : bv-av) > 8'd24) near_rgb = 1'b0;
            end
        end
    endfunction
    function [7:0] lift_shadow;
        input [7:0] v;
        begin
            if (v < 64) lift_shadow = v + (v >> 2);
            else if (v < 128) lift_shadow = v + ((8'd128-v) >> 2);
            else lift_shadow = v;
        end
    endfunction
    wire [23:0] display_filtered = display_flat_q ?
        {display_sum_q[29:22],display_sum_q[19:12],display_sum_q[9:2]} : prefetch_rgb;
    generate if (ENABLE_DISPLAY_DENOISE) begin : g_display_denoise
        hx_eram_line_store #(.DATA_WIDTH(27)) u_display_row (
            .clk(I_clk), .rd_addr(pix_x), .wr_addr(pix_x),
            .wr_en(I_rst_n && I_de && (pix_x < IMAGE_WIDTH)),
            .wr_data({I_mode,display_source}), .rd_data(display_above)
        );
    end else begin : g_no_display_denoise
        assign display_above = 27'd0;
    end endgenerate
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            display_left <= 0; display_above_left <= 0;
            display_sum_q <= 0; display_flat_q <= 0;
        end else begin
            display_flat_q <= ENABLE_DISPLAY_DENOISE && I_de && !I_mode[1] &&
                (pix_x > 0) && (pix_y > 0) &&
                (display_left[26:24] == I_mode) && (display_above[26:24] == I_mode) &&
                (display_above_left[26:24] == I_mode) &&
                near_rgb(display_source,display_left[23:0]) &&
                near_rgb(display_source,display_above[23:0]) &&
                near_rgb(display_source,display_above_left[23:0]);
            display_sum_q <= {
                ({2'd0,display_source[23:16]} + {2'd0,display_left[23:16]} + {2'd0,display_above[23:16]} + {2'd0,display_above_left[23:16]} + 10'd2),
                ({2'd0,display_source[15:8]} + {2'd0,display_left[15:8]} + {2'd0,display_above[15:8]} + {2'd0,display_above_left[15:8]} + 10'd2),
                ({2'd0,display_source[7:0]} + {2'd0,display_left[7:0]} + {2'd0,display_above[7:0]} + {2'd0,display_above_left[7:0]} + 10'd2)};
            if (I_de) begin
                display_left <= {I_mode,display_source};
                display_above_left <= display_above;
            end
        end
    end
>>>>>>> Stashed changes
    reg [23:0] overlay_rgb;
    //【HX1P35A-移植适配】000 原图、001 灰度、010 彩色目标掩膜、011 全屏轻量 Canny 边缘、100 梯度幅值灰阶。
    always @(*) begin
        case(I_mode)
            3'd1: base_rgb = {gray,gray,gray};
            3'd2: base_rgb = color_overlay_rgb; //【HX1P35A-移植适配】COLOR 不再因未命中目标而整屏全黑。
            3'd3: base_rgb = edge_display_pixel ? 24'hffffff : 24'h000000; //【HX1P35A-移植适配】Canny 输出使用强细节补偿和 2x2 加粗后的边缘。
            3'd4: base_rgb = {grad_gray,grad_gray,grad_gray}; //【GRAD】Gaussian+Sobel 幅值灰阶，不做 NMS 与二值化。
            default: base_rgb = I_rgb;
        endcase
    end

    always @(*) begin
        overlay_rgb = stage_rgb;
        if (osd_glyph) overlay_rgb = osd_fg;
        else if (osd_background) overlay_rgb = 24'h101018;
        else if (box_border) overlay_rgb = 24'hffff00;
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            x <= 0; y <= 0;
            raw_top_d2 <= 0; raw_top_d1 <= 0; raw_mid_d2 <= 0; raw_mid_d1 <= 0; raw_bot_d2 <= 0; raw_bot_d1 <= 0; //【HX1P35A-移植适配】复位 Gaussian 滑动窗口。
            gaussian_gray_q <= 0; gaussian_x_q <= 0; gaussian_y_q <= 0; gaussian_de_q <= 0; //【HX1P35A-移植适配】复位 Gaussian 流水寄存器及坐标。
            top_d2 <= 0; top_d1 <= 0; mid_d2 <= 0; mid_d1 <= 0; bot_d2 <= 0; bot_d1 <= 0;
            mag_top_d2 <= 0; mag_top_d1 <= 0; mag_mid_d2 <= 0; mag_mid_d1 <= 0; mag_bot_d2 <= 0; mag_bot_d1 <= 0; //【HX1P35A-移植适配】复位 Sobel 幅值细化窗口。
            dir_mid_d2 <= 0; dir_mid_d1 <= 0; //【HX1P35A-移植适配】复位局部极大值方向窗口。
            weak_left <= 0; weak_above_left <= 0; //【HX1P35A-移植适配】复位连续弱纹理状态。
            strong_left <= 0; strong_above_left <= 0; //【HX1P35A-移植适配】复位 Sobel 双阈值连接状态。
            bridge_left <= 0; bridge_above_left <= 0; //【HX1P35A-移植适配】复位单像素断点连接状态。
            weak_hyst_top_d2 <= 0; weak_hyst_top_d1 <= 0; weak_hyst_mid_d2 <= 0; weak_hyst_mid_d1 <= 0; weak_hyst_bot_d2 <= 0; weak_hyst_bot_d1 <= 0;
            strong_hyst_top_d2 <= 0; strong_hyst_top_d1 <= 0; strong_hyst_mid_d2 <= 0; strong_hyst_mid_d1 <= 0; strong_hyst_bot_d2 <= 0; strong_hyst_bot_d1 <= 0; //【HX1P35A-移植适配】复位对称 8 邻域滞后窗口。
            edge_core_q <= 0; edge_core_de_q <= 0; edge_x_q <= 0; //【HX1P35A-移植适配】复位强细节补偿流水级。
            edge_dilate_left <= 0; edge_dilate_above_left <= 0; //【HX1P35A-移植适配】复位边缘加粗邻域状态。
            color_left <= 0; color_above_left <= 0; //【HX1P35A-移植适配】复位颜色邻域一致性状态。
            cur_count <= 0; cur_red_count <= 0; cur_green_count <= 0; cur_blue_count <= 0;
            cur_xmin <= 11'd2047; cur_ymin <= 11'd2047; cur_xmax <= 0; cur_ymax <= 0;
            box_xmin <= 0; box_ymin <= 0; box_xmax <= 0; box_ymax <= 0; box_color <= 0;
            center_x_bcd <= 0; center_y_bcd <= 0; pixel_count_bcd <= 0;
            O_target_found <= 0; O_target_pixels <= 0;
            frame_luma_sum <= 0; frame_highlight_count <= 0; frame_shadow_count <= 0; O_frame_luma <= 0; O_frame_highlights <= 0; O_frame_shadows <= 0; O_frame_luma_toggle <= 0; //【HX1P35A-移植适配】复位自动曝光亮度、高光及暗部统计。
            stage_vsync <= 0; stage_hsync <= 0; stage_de <= 0; stage_user <= 0; stage_last <= 0;
            stage_rgb <= 0; draw_x <= 0; draw_y <= 0;
            O_vsync <= 0; O_hsync <= 0; O_de <= 0; O_user <= 0; O_last <= 0; O_rgb <= 0;
        end else begin
            //【HX1P35A-移植适配】第一级锁存算法画面和坐标，第二级锁存 OSD/包围框画面；标志同步延迟。
            stage_vsync <= I_vsync; stage_hsync <= I_hsync; stage_de <= I_de;
            stage_user <= I_user; stage_last <= I_last;
            stage_rgb <= I_de ? base_rgb : 24'h000000;
            draw_x <= pix_x; draw_y <= pix_y;
            O_vsync <= stage_vsync; O_hsync <= stage_hsync; O_de <= stage_de;
            O_user <= stage_user; O_last <= stage_last;
            O_rgb <= stage_de ? overlay_rgb : 24'h000000;

            gaussian_de_q <= I_de; //【HX1P35A-移植适配】Gaussian 输出有效标志延迟一级以切断长组合路径。
            edge_core_de_q <= gaussian_de_q; //【HX1P35A-移植适配】边缘融合有效信号随结果再延迟一级。
            if (gaussian_de_q) begin
                edge_core_q <= edge_core; //【HX1P35A-移植适配】寄存融合边缘，保证 HDMI 像素时序。
                edge_x_q <= gaussian_x_q; //【HX1P35A-移植适配】坐标与寄存后的融合边缘保持同拍。
            end
            if (I_de) begin
                gaussian_gray_q <= gaussian_gray; //【HX1P35A-移植适配】寄存平滑结果后再进入 Sobel。
                gaussian_x_q <= pix_x; gaussian_y_q <= pix_y; //【HX1P35A-移植适配】锁存与平滑结果对应的坐标。
            end

            if (frame_start) begin //【HX1P35A-移植适配】帧首发布上一帧亮度，并从当前首像素重新累计。
                O_frame_luma <= frame_luma_sum[19:12]; //【HX1P35A-移植适配】用移位代替除法器，降低逻辑和时序开销。
                O_frame_highlights <= frame_highlight_count; //【HX1P35A-移植适配】锁存上一帧高光面积用于防过曝。
                O_frame_shadows <= frame_shadow_count; //【HX1P35A-移植适配】锁存上一帧深暗面积用于保护暗部结构。
                O_frame_luma_toggle <= ~O_frame_luma_toggle; //【HX1P35A-移植适配】跨域接收端据此识别新一帧统计值。
                frame_luma_sum <= {12'd0,gray}; //【HX1P35A-移植适配】当前 (0,0) 像素作为新一帧第一个样点。
                frame_highlight_count <= highlight_pixel ? 12'd1 : 12'd0; //【HX1P35A-移植适配】从新帧首像素重新统计真正接近削顶的高光。
                frame_shadow_count <= (gray <= 8'd48) ? 12'd1 : 12'd0; //【HX1P35A-移植适配】从新帧首像素重新统计深暗区域。
            end else if (luma_sample) begin
                frame_luma_sum <= frame_luma_sum + gray; //【HX1P35A-移植适配】全画面稀疏亮度累加。
                if (highlight_sample) frame_highlight_count <= frame_highlight_count + 1'b1; //【HX1P35A-移植适配】累计饱和区域面积。
                if (shadow_sample) frame_shadow_count <= frame_shadow_count + 1'b1; //【HX1P35A-移植适配】累计深暗区域面积。
            end

            if (I_de && (pix_x < IMAGE_WIDTH)) begin
                raw_gray_line2[pix_x] <= raw_gray_line1[pix_x]; //【HX1P35A-移植适配】推进 Gaussian 原始灰度行缓存。
                raw_gray_line1[pix_x] <= gray; //【HX1P35A-移植适配】保存当前原始灰度供下一行平滑。
                color_line[pix_x] <= raw_color; //【HX1P35A-移植适配】写入本行原始颜色候选，供下一行空间一致性判断。
                color_left <= raw_color; //【HX1P35A-移植适配】保存当前候选供下一像素水平邻域判断。
                color_above_left <= (pix_x == 0) ? 2'd0 : color_above; //【HX1P35A-移植适配】保存尚未被覆盖的上一行左上颜色。
                if (pix_x == 0) begin
                    raw_top_d2 <= 0; raw_top_d1 <= raw_top_right; //【HX1P35A-移植适配】新行重新装载 Gaussian 上行。
                    raw_mid_d2 <= 0; raw_mid_d1 <= raw_mid_right; //【HX1P35A-移植适配】新行重新装载 Gaussian 中行。
                    raw_bot_d2 <= 0; raw_bot_d1 <= gray; //【HX1P35A-移植适配】新行重新装载 Gaussian 当前行。
                end else begin
                    raw_top_d2 <= raw_top_d1; raw_top_d1 <= raw_top_right; //【HX1P35A-移植适配】Gaussian 上行窗口水平滑动。
                    raw_mid_d2 <= raw_mid_d1; raw_mid_d1 <= raw_mid_right; //【HX1P35A-移植适配】Gaussian 中行窗口水平滑动。
                    raw_bot_d2 <= raw_bot_d1; raw_bot_d1 <= gray; //【HX1P35A-移植适配】Gaussian 当前行窗口水平滑动。
                end
            end

            if (gaussian_de_q && (gaussian_x_q < IMAGE_WIDTH)) begin //【HX1P35A-移植适配】Gaussian 后半段使用独立流水坐标推进。
                weak_line[gaussian_x_q] <= weak_edge_pixel; //【HX1P35A-移植适配】保存当前弱边缘供下一行连续性判断。
                weak_left <= weak_edge_pixel; //【HX1P35A-移植适配】保存当前弱边缘供下一像素水平连续性判断。
                weak_above_left <= (gaussian_x_q == 0) ? 1'b0 : weak_above; //【HX1P35A-移植适配】保存尚未覆盖的上一行左上弱边缘。
                strong_line[gaussian_x_q] <= strong_edge_pixel; //【HX1P35A-移植适配】写入本行强边缘，供下一行滞后连接判断。
                strong_left <= strong_edge_pixel; //【HX1P35A-移植适配】保存当前强边缘供下一像素水平连接判断。
                strong_above_left <= (gaussian_x_q == 0) ? 1'b0 : strong_above; //【HX1P35A-移植适配】保存左上强边缘，支持斜向轮廓。
                bridge_line[gaussian_x_q] <= edge_seed; //【HX1P35A-移植适配】仅存第一步种子，限制断点连接深度。
                bridge_left <= edge_seed; //【HX1P35A-移植适配】保存当前种子供下一像素连接。
                bridge_above_left <= (gaussian_x_q == 0) ? 1'b0 : bridge_above; //【HX1P35A-移植适配】保存左上种子以补斜向短断点。
                weak_hyst_line2[gaussian_x_q] <= weak_hyst_line1[gaussian_x_q];
                weak_hyst_line1[gaussian_x_q] <= weak_edge_pixel;
                strong_hyst_line2[gaussian_x_q] <= strong_hyst_line1[gaussian_x_q];
                strong_hyst_line1[gaussian_x_q] <= strong_edge_pixel; //【HX1P35A-移植适配】保存双阈值候选，供下一行组成完整 3x3 滞后窗口。
                mag_line2[gaussian_x_q] <= mag_line1[gaussian_x_q]; //【HX1P35A-移植适配】Sobel 幅值行缓存向上两行推进。
                mag_line1[gaussian_x_q] <= sobel_mag; //【HX1P35A-移植适配】保存当前 Sobel 幅值供下一行细化。
                dir_line1[gaussian_x_q] <= sobel_direction; //【HX1P35A-移植适配】保存当前四方向编码供下一行峰值比较。
                gray_line2[gaussian_x_q] <= gray_line1[gaussian_x_q]; //【HX1P35A-移植适配】推进 Gaussian 平滑结果行缓存。
                gray_line1[gaussian_x_q] <= gaussian_gray_q; //【HX1P35A-移植适配】写入寄存后的 Gaussian 灰度。
                if (gaussian_x_q == 0) begin
                    top_d2 <= 0; top_d1 <= top_right; //【HX1P35A-移植适配】新行重新装载 Sobel 上行。
                    mid_d2 <= 0; mid_d1 <= mid_right; //【HX1P35A-移植适配】新行重新装载 Sobel 中行。
                    bot_d2 <= 0; bot_d1 <= gaussian_gray_q; //【HX1P35A-移植适配】Sobel 新行装载寄存后的平滑像素。
                    mag_top_d2 <= 0; mag_top_d1 <= mag_top_right; //【HX1P35A-移植适配】新行重新装载幅值窗口上行。
                    mag_mid_d2 <= 0; mag_mid_d1 <= mag_mid_right; //【HX1P35A-移植适配】新行重新装载幅值窗口中行。
                    mag_bot_d2 <= 0; mag_bot_d1 <= sobel_mag; //【HX1P35A-移植适配】新行重新装载幅值窗口下行。
                    dir_mid_d2 <= 0; dir_mid_d1 <= dir_mid_right; //【HX1P35A-移植适配】新行重新装载方向窗口。
                    weak_hyst_top_d2 <= 0; weak_hyst_top_d1 <= weak_hyst_top_right;
                    weak_hyst_mid_d2 <= 0; weak_hyst_mid_d1 <= weak_hyst_mid_right;
                    weak_hyst_bot_d2 <= 0; weak_hyst_bot_d1 <= weak_edge_pixel;
                    strong_hyst_top_d2 <= 0; strong_hyst_top_d1 <= strong_hyst_top_right;
                    strong_hyst_mid_d2 <= 0; strong_hyst_mid_d1 <= strong_hyst_mid_right;
                    strong_hyst_bot_d2 <= 0; strong_hyst_bot_d1 <= strong_edge_pixel; //【HX1P35A-移植适配】行首重置对称滞后窗口，防止跨行连接。
                end else begin
                    top_d2 <= top_d1; top_d1 <= top_right;
                    mid_d2 <= mid_d1; mid_d1 <= mid_right;
                    bot_d2 <= bot_d1; bot_d1 <= gaussian_gray_q; //【HX1P35A-移植适配】Sobel 当前行窗口输入寄存后的平滑灰度。
                    mag_top_d2 <= mag_top_d1; mag_top_d1 <= mag_top_right; //【HX1P35A-移植适配】幅值窗口上行水平滑动。
                    mag_mid_d2 <= mag_mid_d1; mag_mid_d1 <= mag_mid_right; //【HX1P35A-移植适配】幅值窗口中行水平滑动。
                    mag_bot_d2 <= mag_bot_d1; mag_bot_d1 <= sobel_mag; //【HX1P35A-移植适配】幅值窗口下行水平滑动。
                    dir_mid_d2 <= dir_mid_d1; dir_mid_d1 <= dir_mid_right; //【HX1P35A-移植适配】方向窗口水平滑动。
                    weak_hyst_top_d2 <= weak_hyst_top_d1; weak_hyst_top_d1 <= weak_hyst_top_right;
                    weak_hyst_mid_d2 <= weak_hyst_mid_d1; weak_hyst_mid_d1 <= weak_hyst_mid_right;
                    weak_hyst_bot_d2 <= weak_hyst_bot_d1; weak_hyst_bot_d1 <= weak_edge_pixel;
                    strong_hyst_top_d2 <= strong_hyst_top_d1; strong_hyst_top_d1 <= strong_hyst_top_right;
                    strong_hyst_mid_d2 <= strong_hyst_mid_d1; strong_hyst_mid_d1 <= strong_hyst_mid_right;
                    strong_hyst_bot_d2 <= strong_hyst_bot_d1; strong_hyst_bot_d1 <= strong_edge_pixel; //【HX1P35A-移植适配】每像素推进 3x3 双阈值窗口。
                end
            end

            if (edge_core_de_q && (edge_x_q < IMAGE_WIDTH)) begin
                edge_dilate_line[edge_x_q] <= edge_core_q; //【HX1P35A-移植适配】写入寄存后的融合边缘供下一行加粗。
                edge_dilate_left <= edge_core_q; //【HX1P35A-移植适配】保存寄存后的融合边缘供下一像素水平加粗。
                edge_dilate_above_left <= (edge_x_q == 0) ? 1'b0 : edge_dilate_above; //【HX1P35A-移植适配】保存上一行左上边缘供斜向加粗。
            end

            if (frame_start) begin
                //【HX1P35A-移植适配】锁存上一帧跟踪结果、BCD 信息及主颜色，再初始化本帧统计。
                O_target_found <= cur_frame_valid;
                O_target_pixels <= cur_count;
                if (cur_frame_valid) begin
                    box_xmin <= next_box_xmin; box_xmax <= next_box_xmax;
                    box_ymin <= next_box_ymin; box_ymax <= next_box_ymax;
                    center_x_bcd <= bin11_to_bcd4(next_center_x);
                    center_y_bcd <= bin11_to_bcd4(next_center_y);
                    pixel_count_bcd <= bin24_to_bcd6(clipped_count);
                    if ((cur_red_count >= cur_green_count) && (cur_red_count >= cur_blue_count)) box_color <= 2'd1;
                    else if (cur_green_count >= cur_blue_count) box_color <= 2'd2;
                    else box_color <= 2'd3;
                end else begin
                    box_color <= 2'd0;
                    center_x_bcd <= 0; center_y_bcd <= 0; pixel_count_bcd <= 0;
                end
                cur_count <= target_hit ? 24'd1 : 24'd0;
                cur_red_count <= red_hit ? 24'd1 : 24'd0;
                cur_green_count <= green_hit ? 24'd1 : 24'd0;
                cur_blue_count <= blue_hit ? 24'd1 : 24'd0;
                cur_xmin <= target_hit ? 11'd0 : 11'd2047;
                cur_xmax <= 11'd0;
                cur_ymin <= target_hit ? 11'd0 : 11'd2047;
                cur_ymax <= 11'd0;
                x <= I_last ? 11'd0 : 11'd1;
                y <= 11'd0;
            end else if (I_de) begin
                if (I_last) begin x <= 0; y <= y + 1'b1; end
                else x <= x + 1'b1;
                if (target_hit) begin
                    if (cur_count != 24'hffffff) cur_count <= cur_count + 1'b1;
                    if (red_hit && cur_red_count != 24'hffffff) cur_red_count <= cur_red_count + 1'b1;
                    if (green_hit && cur_green_count != 24'hffffff) cur_green_count <= cur_green_count + 1'b1;
                    if (blue_hit && cur_blue_count != 24'hffffff) cur_blue_count <= cur_blue_count + 1'b1;
                    if (pix_x < cur_xmin) cur_xmin <= pix_x;
                    if (pix_x > cur_xmax) cur_xmax <= pix_x;
                    if (pix_y < cur_ymin) cur_ymin <= pix_y;
                    if (pix_y > cur_ymax) cur_ymax <= pix_y;
                end
            end
        end
    end
endmodule
<<<<<<< Updated upstream
=======

// Binary edge postprocessing BEFORE dilation: never feed filled pixels back into
// the same pass. Two independent windows keep removed speckles out of bridging.
module hx_edge_binary_refine #(
    parameter IMAGE_WIDTH = 1280
) (
    input wire I_clk, I_rst_n, I_de,
    input wire [10:0] I_x, I_y,
    input wire I_edge,
    output wire O_de,
    output wire [10:0] O_x,
    output wire O_edge
);
    wire clean_de, clean_edge;
    wire [10:0] clean_x, clean_y;
    hx_edge_window5 #(.IMAGE_WIDTH(IMAGE_WIDTH), .BRIDGE(0)) u_clean (
        .I_clk(I_clk), .I_rst_n(I_rst_n), .I_de(I_de), .I_x(I_x), .I_y(I_y), .I_edge(I_edge),
        .O_de(clean_de), .O_x(clean_x), .O_y(clean_y), .O_edge(clean_edge)
    );
    hx_edge_window5 #(.IMAGE_WIDTH(IMAGE_WIDTH), .BRIDGE(1)) u_bridge (
        .I_clk(I_clk), .I_rst_n(I_rst_n), .I_de(clean_de), .I_x(clean_x), .I_y(clean_y), .I_edge(clean_edge),
        .O_de(O_de), .O_x(O_x), .O_y(), .O_edge(O_edge)
    );
endmodule

// Display-only lookahead: retain EVERY clock slot (including blanking) for
// 2048 clocks. Production line period is 1650 clocks, leaving >380 clocks
// for the pipelined correction to arrive. Pixels are never cropped/shifted.
module hx_centered_display #(
    parameter integer IMAGE_WIDTH=1280,
    parameter [7:0] NOISE_GATE=6, MAX_DELTA=8,
    parameter integer GAIN_SHIFT=1
) (
    input wire clk,rst_n,
    input wire [55:0] payload,
    output reg [55:0] delayed,
    output reg signed [8:0] delta
);
    reg [10:0] slot;
    reg [11:0] warm;
    wire de=payload[48];
    wire [10:0] x=payload[45:35], y=payload[34:24];
    wire [15:0] luma_sum=payload[23:16]*8'd77+payload[15:8]*8'd150+payload[7:0]*8'd29;
    wire [7:0] gray=luma_sum[15:8];
    wire [55:0] fifo_read;
    wire [28:0] rows;
    // Two luma rows + two mode-valid rows + previous row's clock-slot tag.
    hx_eram_line_store #(.DATA_WIDTH(29)) u_rows (
        .clk(clk),.rd_addr(x),.wr_addr(x),.wr_en(rst_n && de && x<IMAGE_WIDTH),
        .wr_data({slot,rows[16],payload[55],rows[7:0],gray}),.rd_data(rows)
    );
    hx_eram_line_store #(.DATA_WIDTH(56)) u_video_slots (
        .clk(clk),.rd_addr(slot),.wr_addr(slot),.wr_en(rst_n),
        .wr_data(payload),.rd_data(fifo_read)
    );
    reg [7:0] top2,top1,mid2,mid1,bot2,bot1;
    reg topv2,topv1,midv2,midv1,botv2,botv1;
    reg [10:0] midtag1;
    reg [7:0] taps[0:8];
    reg [7:0] center0,center1,center2;
    reg [9:0] row0,row1,row2;
    reg [11:0] blur2;
    reg signed [8:0] hp3;
    reg [8:0] magnitude4;
    reg negative4;
    reg signed [8:0] correction5;
    reg [10:0] tag[0:5];
    reg [5:0] valid;
    wire [8:0] gated=(magnitude4>NOISE_GATE) ? ((magnitude4-NOISE_GATE)>>GAIN_SHIFT) : 9'd0;
    wire [8:0] limited=(gated>MAX_DELTA) ? {1'b0,MAX_DELTA} : gated;
    wire [8:0] correction_read;
    // Read-before-clear on port A; corrections are written by port B BEFORE
    // their original video slot is consumed. No RAM initialization assumption.
    hx_correction_slots u_corrections (
        .clk(clk),.read_clear_addr(slot),.patch_addr(tag[5]),
        .patch_enable(rst_n && valid[5]),.patch(correction5),.result(correction_read)
    );
    integer k;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            slot<=0;warm<=0;delayed<=0;delta<=0;
            top2<=0;top1<=0;mid2<=0;mid1<=0;bot2<=0;bot1<=0;
            topv2<=0;topv1<=0;midv2<=0;midv1<=0;botv2<=0;botv1<=0;midtag1<=0;
            center0<=0;center1<=0;center2<=0;row0<=0;row1<=0;row2<=0;blur2<=0;
            hp3<=0;magnitude4<=0;negative4<=0;correction5<=0;valid<=0;
            for(k=0;k<9;k=k+1)taps[k]<=0;
            for(k=0;k<6;k=k+1)tag[k]<=0;
        end else begin
            slot<=slot+1'b1;
            if(warm<2048)warm<=warm+1'b1;
            delayed<=warm==2048 ? fifo_read : 56'd0;
            delta<=warm==2048 ? $signed(correction_read) : 9'sd0;
            // First stage only captures RAM outputs. Arithmetic starts on a
            // full-cycle registered path, not the half-cycle ERAM read path.
            taps[0]<=top2;taps[1]<=top1;taps[2]<=rows[15:8];
            taps[3]<=mid2;taps[4]<=mid1;taps[5]<=rows[7:0];
            taps[6]<=bot2;taps[7]<=bot1;taps[8]<=gray;
            center0<=mid1;tag[0]<=midtag1;
            valid[0]<=de && x>=2 && y>=2 && x<IMAGE_WIDTH &&
                topv2 && topv1 && rows[17] && midv2 && midv1 && rows[16] &&
                botv2 && botv1 && payload[55];
            for(k=1;k<6;k=k+1)begin valid[k]<=valid[k-1];tag[k]<=tag[k-1];end
            row0<={2'd0,taps[0]}+({2'd0,taps[1]}<<1)+{2'd0,taps[2]};
            row1<={2'd0,taps[3]}+({2'd0,taps[4]}<<1)+{2'd0,taps[5]};
            row2<={2'd0,taps[6]}+({2'd0,taps[7]}<<1)+{2'd0,taps[8]};
            center1<=center0;
            blur2<={2'd0,row0}+({2'd0,row1}<<1)+{2'd0,row2};center2<=center1;
            hp3<=$signed({1'b0,center2})-$signed({1'b0,blur2[11:4]});
            magnitude4<=hp3[8] ? $unsigned(-hp3) : $unsigned(hp3);negative4<=hp3[8];
            correction5<=negative4 ? -$signed(limited) : $signed(limited);
            if(de && x<IMAGE_WIDTH) begin
                if(x==0) begin
                    top2<=0;top1<=rows[15:8];mid2<=0;mid1<=rows[7:0];bot2<=0;bot1<=gray;
                    topv2<=0;topv1<=rows[17];midv2<=0;midv1<=rows[16];botv2<=0;botv1<=payload[55];
                end else begin
                    top2<=top1;top1<=rows[15:8];mid2<=mid1;mid1<=rows[7:0];bot2<=bot1;bot1<=gray;
                    topv2<=topv1;topv1<=rows[17];midv2<=midv1;midv1<=rows[16];botv2<=botv1;botv1<=payload[55];
                end
                midtag1<=rows[28:18];
            end
        end
    end
endmodule

module hx_correction_slots (
    input wire clk,
    input wire [10:0] read_clear_addr,patch_addr,
    input wire patch_enable,
    input wire [8:0] patch,
    output wire [8:0] result
);
    wire [8:0] unused_b;
    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A(9),.DATA_WIDTH_B(9),.ADDR_WIDTH_A(11),.ADDR_WIDTH_B(11),
        .DATA_DEPTH_A(2048),.DATA_DEPTH_B(2048),.MODE("DP"),
        .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .WRITEMODE_A("READBEFOREWRITE"),.WRITEMODE_B("READBEFOREWRITE"),
        .IMPLEMENT("20K(FAST)"),.ECC_ENCODE("DISABLE"),.ECC_DECODE("DISABLE"),
        .CLKMODE("ASYNC"),.SSROVERCE("DISABLE"),.OREGSET_A("RESET"),.OREGSET_B("RESET"),
        .RESETMODE_A("ASYNC"),.RESETMODE_B("ASYNC"),
        .ASYNC_RESET_RELEASE_A("ASYNC"),.ASYNC_RESET_RELEASE_B("ASYNC"),
        .INIT_FILE("NONE"),.FILL_ALL("NONE")
    ) u_ram (
        .dia(9'd0),.dib(patch),.addra(read_clear_addr),.addrb(patch_addr),
        .cea(1'b1),.ceb(1'b1),.ocea(1'b0),.oceb(1'b0),.clka(~clk),.clkb(clk),
        .wea(1'b1),.web(patch_enable),.bea(1'b0),.beb(1'b0),.rsta(1'b0),.rstb(1'b0),
        .doa(result),.dob(unused_b),.ecc_sbiterr(),.ecc_dbiterr(),.ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0)
    );
endmodule


// One 5x5 raster window, four prior rows packed into a 4-bit ERAM.
// Output uses the current raster slot; window centre is (x-2,y-2).
// No frame buffer/flush: incomplete top/left windows output zero. Two stages
// shift interior edge content by 4 rows/columns plus register latency; the
// bottom/right tail is cropped. Non-edge display modes do not use this data.
module hx_edge_window5 #(
    parameter IMAGE_WIDTH = 1280,
    parameter BRIDGE = 0
) (
    input wire I_clk, I_rst_n, I_de,
    input wire [10:0] I_x, I_y,
    input wire I_edge,
    output reg O_de,
    output reg [10:0] O_x, O_y,
    output reg O_edge
);
    wire active = I_de && (I_x < IMAGE_WIDTH);
    wire [3:0] line_rd;
    wire [4:0] right_col = {(I_y >= 4) && line_rd[3], (I_y >= 3) && line_rd[2],
                            (I_y >= 2) && line_rd[1], (I_y >= 1) && line_rd[0], I_edge};
    reg [3:0] row0, row1, row2, row3, row4;
    wire [4:0] w0 = {row0, right_col[4]};
    wire [4:0] w1 = {row1, right_col[3]};
    wire [4:0] w2 = {row2, right_col[2]};
    wire [4:0] w3 = {row3, right_col[1]};
    wire [4:0] w4 = {row4, right_col[0]};

    hx_eram_line_store #(.DATA_WIDTH(4)) u_rows (
        .clk(I_clk), .rd_addr(I_x), .wr_addr(I_x),
        .wr_en(active), .wr_data({line_rd[2:0], I_edge}), .rd_data(line_rd)
    );

    wire near_any = (|w1[3:1]) || w2[3] || w2[1] || (|w3[3:1]);
    wire ring_any = (|w0) || (|w4) || w1[4] || w1[0] || w2[4] || w2[0] || w3[4] || w3[0];
    wire through = (w2[3] && w2[1]) || (w1[2] && w3[2]) ||
                   (w1[3] && w3[1]) || (w1[1] && w3[3]);
    // Preserve supported endpoints and through-lines, not only dense blobs.
    // A lone pixel, isolated pair, or isolated 2x2 patch has no such support.
    wire clean_pixel = w2[2] && ((near_any && ring_any) || through);

    function bridge_axis;
        input m2, m1, p1, p2;
        begin
            // One empty pixel: opposite endpoints plus one outward support.
            // Two empty pixels: two samples on one side and one on the other.
            bridge_axis = (m1 && p1 && (m2 || p2)) ||
                          (m2 && m1 && p2) || (m2 && p1 && p2);
        end
    endfunction
    wire bridge_pixel = w2[2] ||
                        bridge_axis(w2[4], w2[3], w2[1], w2[0]) ||
                        bridge_axis(w0[2], w1[2], w3[2], w4[2]) ||
                        bridge_axis(w0[4], w1[3], w3[1], w4[0]) ||
                        bridge_axis(w0[0], w1[1], w3[3], w4[4]);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            row0 <= 0; row1 <= 0; row2 <= 0; row3 <= 0; row4 <= 0;
            O_de <= 0; O_x <= 0; O_y <= 0; O_edge <= 0;
        end else begin
            O_de <= active;
            O_edge <= active && (I_x >= 4) && (I_y >= 4) && (BRIDGE ? bridge_pixel : clean_pixel);
            if (active) begin
                O_x <= I_x; O_y <= I_y;
                if (I_x == 0) begin
                    row0 <= {3'd0, right_col[4]}; row1 <= {3'd0, right_col[3]};
                    row2 <= {3'd0, right_col[2]}; row3 <= {3'd0, right_col[1]};
                    row4 <= {3'd0, right_col[0]};
                end else begin
                    row0 <= {row0[2:0], right_col[4]}; row1 <= {row1[2:0], right_col[3]};
                    row2 <= {row2[2:0], right_col[2]}; row3 <= {row3[2:0], right_col[1]};
                    row4 <= {row4[2:0], right_col[0]};
                end
            end
        end
    end
endmodule

//【资源优化】PH1P35 片上 ERAM 双口行缓存：A 口下降沿读，B 口上升沿写。
// 使用 2048 深度覆盖 1280 像素行；未用地址不参与画面处理。
module hx_eram_line_store #(
    parameter DATA_WIDTH = 8
) (
    input  wire                  clk,
    input  wire [10:0]           rd_addr,
    input  wire [10:0]           wr_addr,
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] wr_data,
    output wire [DATA_WIDTH-1:0] rd_data
);
    wire [DATA_WIDTH-1:0] unused_write_port_data;

    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A(DATA_WIDTH),
        .DATA_WIDTH_B(DATA_WIDTH),
        .ADDR_WIDTH_A(11),
        .ADDR_WIDTH_B(11),
        .DATA_DEPTH_A(2048),
        .DATA_DEPTH_B(2048),
        .MODE("DP"),
        .REGMODE_A("NOREG"),
        .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),
        .WRITEMODE_B("READBEFOREWRITE"),
        .IMPLEMENT("20K(FAST)"),
        .ECC_ENCODE("DISABLE"),
        .ECC_DECODE("DISABLE"),
        .CLKMODE("ASYNC"),
        .SSROVERCE("DISABLE"),
        .OREGSET_A("RESET"),
        .OREGSET_B("RESET"),
        .RESETMODE_A("ASYNC"),
        .RESETMODE_B("ASYNC"),
        .ASYNC_RESET_RELEASE_A("ASYNC"),
        .ASYNC_RESET_RELEASE_B("ASYNC"),
        .INIT_FILE("NONE"),
        .FILL_ALL("NONE")
    ) u_line_eram (
        .dia({DATA_WIDTH{1'b0}}),
        .dib(wr_data),
        .addra(rd_addr),
        .addrb(wr_addr),
        .cea(1'b1),
        .ceb(1'b1),
        .ocea(1'b0),
        .oceb(1'b0),
        .clka(~clk),
        .clkb(clk),
        .wea(1'b0),
        .web(wr_en),
        .bea(1'b0),
        .beb(1'b0),
        .rsta(1'b0),
        .rstb(1'b0),
        .doa(rd_data),
        .dob(unused_write_port_data),
        .ecc_sbiterr(),
        .ecc_dbiterr(),
        .ecc_sbiterrinj(1'b0),
        .ecc_dbiterrinj(1'b0)
    );
endmodule

// Coherent bundled-data mailbox for confirmed sensor register snapshots.
// The source must keep the payload stable until O_src_ack_toggle matches its request.
module hx_sensor_applied_cdc (
    input wire src_req_toggle,
    input wire [15:0] src_exposure,
    input wire [23:0] src_gain_regs,
    input wire [1:0] src_status,
    input wire src_has_value,
    input wire dst_clk,
    input wire dst_rst_n,
    output reg src_ack_toggle,
    output reg [15:0] dst_exposure,
    output reg [23:0] dst_gain_regs,
    output reg [1:0] dst_status,
    output reg dst_has_value,
    output reg dst_update_toggle
);
    (* async_reg = "true" *) reg [1:0] req_sync;

    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            req_sync <= 2'b00;
            src_ack_toggle <= 1'b0;
            dst_exposure <= 16'd0;
            dst_gain_regs <= 24'd0;
            dst_status <= 2'd0;
            dst_has_value <= 1'b0;
            dst_update_toggle <= 1'b0;
        end else begin
            req_sync <= {req_sync[0], src_req_toggle};
            if (req_sync[1] != src_ack_toggle) begin
                dst_exposure <= src_exposure;
                dst_gain_regs <= src_gain_regs;
                dst_status <= src_status;
                dst_has_value <= src_has_value;
                src_ack_toggle <= req_sync[1];
                dst_update_toggle <= req_sync[1];
            end
        end
    end
endmodule

// Reset assertion is asynchronous; release is local to the receiving clock.
// A stopped clock therefore holds the domain in reset until two real edges.
module hx_reset_release (
    input wire clk,
    input wire async_rst_n,
    output wire rst_n
);
    (* async_reg="true" *) reg [1:0] release_sync=2'b00;
    always @(posedge clk or negedge async_rst_n) begin
        if(!async_rst_n) release_sync<=2'b00;
        else release_sync<={release_sync[0],1'b1};
    end
    assign rst_n=release_sync[1];
endmodule
>>>>>>> Stashed changes
