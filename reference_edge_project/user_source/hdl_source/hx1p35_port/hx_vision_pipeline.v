`timescale 1ns / 1ps
//【HX1P35A-移植适配】HDMI 像素域视觉流水线：灰度、3x3 Sobel、三原色目标、平滑跟踪框和信息 OSD。
module hx_vision_pipeline #(
    parameter IMAGE_WIDTH = 1280,
    parameter IMAGE_HEIGHT = 720,
    parameter ENABLE_TEMPLATE_TRACKING = 0,
    parameter MIN_TARGET_PIXELS = 24'd800,
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
    parameter [7:0] RAW_SHARPEN_NOISE_GATE = 8'd6,
    parameter [7:0] RAW_SHARPEN_MAX_DELTA = 8'd8,
    parameter integer RAW_SHARPEN_GAIN_SHIFT = 1,
    // Acquire at the original threshold; a locked target may use a lower one.
    parameter TARGET_RELEASE_PIXELS = (MIN_TARGET_PIXELS > 1) ? (MIN_TARGET_PIXELS >> 1) : 1,
    parameter integer TARGET_HOLD_FRAMES = 10 // Hold ten missed frames; lose lock on the eleventh. Zero disables holding.
) (
    input wire I_clk, input wire I_rst_n,
    input wire I_vsync, input wire I_hsync, input wire I_de,
    input wire I_user, input wire I_last, input wire [23:0] I_rgb,
    input wire [1:0] I_mode,
    input wire [1:0] I_exposure_level, //【HX1P35A-移植适配】在 HDMI OSD 中显示当前曝光档位。
    input wire I_auto_exposure, //【HX1P35A-移植适配】OSD 显示 AUTO 状态。
    input wire I_raw_sharpen_enable, // 仅 RAW 显示生效；测光、颜色统计始终取锐化前数据。
    input wire I_template_command,
    input wire [15:0] I_applied_exposure, // 最近一次已完成并确认的 SC520 曝光寄存器值。
    input wire [23:0] I_applied_gain_regs, // 0x3e09 / 0x3e06 / 0x3e07 已确认写入的原始寄存器字节。
    input wire [1:0] I_applied_status, // 0=等待, 1=写入中, 2=已确认, 3=I2C 错误。
    input wire I_applied_has_value,
    input wire I_applied_update_toggle, // 同 HDMI 像素域握手快照更新翻转位。
    input wire [1:0] I_cal_status,
    output reg O_vsync, output reg O_hsync, output reg O_de,
    output reg O_user, output reg O_last, output reg [23:0] O_rgb,
    output reg O_target_found, output reg [23:0] O_target_pixels, // found=tracking lock (including HOLD); pixels=actual last-frame measurement.
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
    wire highlight_sample = luma_sample && (gray >= 8'd245); //【HX1P35A-移植适配】只统计真正接近削顶的高光，避免把正常浅色墙面误作过曝。
    wire shadow_sample = luma_sample && (gray <= 8'd48); //【HX1P35A-移植适配】统计缺少可辨纹理的深暗区域，用于亮暗共存测光。
    reg [19:0] frame_luma_sum; //【HX1P35A-移植适配】最大 3600*255，小于 20 位上限。
    reg [11:0] frame_highlight_count; //【HX1P35A-移植适配】3600 个样点的高光计数。
    reg [11:0] frame_shadow_count; //【HX1P35A-移植适配】3600 个样点的深暗计数。

    //【资源优化】把同拍访问的两行原始灰度和颜色候选打包进一组显式 ERAM；功能与原三组分布式行缓存一致。
    wire [17:0] raw_line_rd;
    wire [17:0] raw_line_wr;
    reg [7:0] raw_top_d2, raw_top_d1, raw_mid_d2, raw_mid_d1, raw_bot_d2, raw_bot_d1; //【HX1P35A-移植适配】Gaussian 3x3 滑动窗口。
    wire [7:0] raw_top_right = (pix_x < IMAGE_WIDTH) ? raw_line_rd[17:10] : 8'd0; //【HX1P35A-移植适配】Gaussian 窗口右上像素。
    wire [7:0] raw_mid_right = (pix_x < IMAGE_WIDTH) ? raw_line_rd[9:2] : 8'd0; //【HX1P35A-移植适配】Gaussian 窗口右中像素。
    wire [11:0] gaussian_sum = {4'd0,raw_top_d2} + ({4'd0,raw_top_d1} << 1) + {4'd0,raw_top_right} +
                               ({4'd0,raw_mid_d2} << 1) + ({4'd0,raw_mid_d1} << 2) + ({4'd0,raw_mid_right} << 1) +
                               {4'd0,raw_bot_d2} + ({4'd0,raw_bot_d1} << 1) + {4'd0,gray}; //【HX1P35A-移植适配】1-2-1 Gaussian 核，总权重 16。
    wire [7:0] gaussian_gray = gaussian_sum[11:4]; //【HX1P35A-移植适配】右移四位归一化，无需除法器。
    reg [7:0] gaussian_gray_q; //【HX1P35A-移植适配】Gaussian 输出寄存一级，切断平滑与 Sobel 之间的长组合路径。
    reg [10:0] gaussian_x_q, gaussian_y_q; //【HX1P35A-移植适配】随 Gaussian 数据延迟的像素坐标。
    reg gaussian_de_q; //【HX1P35A-移植适配】随 Gaussian 数据延迟的有效标志。
    reg [7:0] gaussian_gray_d;
    reg [10:0] gaussian_x_d, gaussian_y_d;
    reg gaussian_de_d;

    //【资源优化】Gaussian、Sobel/NMS 和双阈值滞后均使用相同地址，合并为一组 46 位 ERAM 行状态。
    wire [45:0] edge_line_rd;
    reg [45:0] edge_line_rd_q; //【资源优化】锁存 ERAM 读数据，将半周期读路径切成完整一拍的算法路径。
    reg [7:0] top_d2, top_d1, mid_d2, mid_d1, bot_d2, bot_d1;
    wire [7:0] top_right = (gaussian_x_d < IMAGE_WIDTH) ? edge_line_rd_q[45:38] : 8'd0; //【HX1P35A-移植适配】按流水坐标读取 Gaussian 上两行。
    wire [7:0] mid_right = (gaussian_x_d < IMAGE_WIDTH) ? edge_line_rd_q[37:30] : 8'd0; //【HX1P35A-移植适配】按流水坐标读取 Gaussian 上一行。
    wire [10:0] gx_pos = {3'd0,top_right} + ({3'd0,mid_right} << 1) + {3'd0,gaussian_gray_d}; //【HX1P35A-移植适配】Sobel 右下输入使用寄存后的 Gaussian 像素。
    wire [10:0] gx_neg = {3'd0,top_d2} + ({3'd0,mid_d2} << 1) + {3'd0,bot_d2};
    wire [10:0] gy_pos = {3'd0,top_d2} + ({3'd0,top_d1} << 1) + {3'd0,top_right};
    wire [10:0] gy_neg = {3'd0,bot_d2} + ({3'd0,bot_d1} << 1) + {3'd0,gaussian_gray_d}; //【HX1P35A-移植适配】Sobel 下行输入使用寄存后的 Gaussian 像素。
    wire [10:0] gx_abs = (gx_pos >= gx_neg) ? (gx_pos - gx_neg) : (gx_neg - gx_pos);
    wire [10:0] gy_abs = (gy_pos >= gy_neg) ? (gy_pos - gy_neg) : (gy_neg - gy_pos);
    wire [11:0] sobel_mag = {1'b0,gx_abs} + {1'b0,gy_abs};
    wire sobel_valid = gaussian_de_d && (gaussian_x_d >= 11'd4) && (gaussian_y_d >= 11'd4); //【资源优化】使用与 ERAM 读数据同拍的延迟坐标。
    wire local_dark_region = (top_d2 < 8'd96); //【HX1P35A-移植适配】top_d2 与 NMS 中心梯度对齐，明窗与暗墙可分别选择门限。
    wire local_bright_region = (top_d2 >= 8'd176); //【HX1P35A-移植适配】局部高亮区域继续使用严格门限，防止窗格和灯具周围铺满噪声。
    wire [11:0] sobel_threshold = local_dark_region ? SOBEL_THRESHOLD_DARK :
                                  local_bright_region ? SOBEL_THRESHOLD_BRIGHT : SOBEL_THRESHOLD_NORMAL; //【HX1P35A-移植适配】按局部而非整帧亮度选择弱门限，保留同帧暗区细节。
    wire [11:0] sobel_strong_threshold = local_dark_region ? SOBEL_STRONG_THRESHOLD_DARK :
                                         local_bright_region ? SOBEL_STRONG_THRESHOLD_BRIGHT : SOBEL_STRONG_THRESHOLD_NORMAL; //【HX1P35A-移植适配】局部强门限为暗墙弱轮廓提供锚点。
    wire gx_dominant = {1'b0,gx_abs} >= ({1'b0,gy_abs} << 1); //【HX1P35A-移植适配】梯度接近水平方向，局部峰值沿左右比较。
    wire gy_dominant = {1'b0,gy_abs} >= ({1'b0,gx_abs} << 1); //【HX1P35A-移植适配】梯度接近垂直方向，局部峰值沿上下比较。
    wire gx_positive = (gx_pos >= gx_neg); //【HX1P35A-移植适配】保留 Gx 符号以区分两种对角方向。
    wire gy_positive = (gy_pos >= gy_neg); //【HX1P35A-移植适配】保留 Gy 符号以区分两种对角方向。
    wire [1:0] sobel_direction = gx_dominant ? 2'd0 : gy_dominant ? 2'd2 :
                                  ((gx_positive == gy_positive) ? 2'd1 : 2'd3); //【HX1P35A-移植适配】量化为 0/45/90/135 度四方向。
    reg [11:0] mag_top_d2, mag_top_d1, mag_mid_d2, mag_mid_d1, mag_bot_d2, mag_bot_d1; //【HX1P35A-移植适配】Sobel 幅值 3x3 滑动窗口。
    reg [1:0] dir_mid_d2, dir_mid_d1; //【HX1P35A-移植适配】上一行相邻像素的四方向梯度编码。
    wire [11:0] mag_top_right = (gaussian_x_d < IMAGE_WIDTH) ? edge_line_rd_q[29:18] : 12'd0; //【HX1P35A-移植适配】按流水坐标读取局部极大值窗口右上幅值。
    wire [11:0] mag_mid_right = (gaussian_x_d < IMAGE_WIDTH) ? edge_line_rd_q[17:6] : 12'd0; //【HX1P35A-移植适配】按流水坐标读取局部极大值窗口右侧幅值。
    wire [1:0] dir_mid_right = (gaussian_x_d < IMAGE_WIDTH) ? edge_line_rd_q[5:4] : 2'd0; //【HX1P35A-移植适配】按流水坐标读取上一行四方向编码。
    wire nms_valid = sobel_valid && (gaussian_x_d >= 11'd6) && (gaussian_y_d >= 11'd6); //【HX1P35A-移植适配】使用延迟坐标等待三级窗口全部完整。
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
    //【HX1P35A-移植适配】参考流式 Canny 的 3x3 行缓存做法，将双阈值候选延迟到窗口中心再判定。
    // 这样弱边能看到右侧、下侧的强边锚点，补足仅按扫描方向判断时容易丢失的灯管、发丝和斜线。
    reg weak_hyst_top_d2, weak_hyst_top_d1, weak_hyst_mid_d2, weak_hyst_mid_d1, weak_hyst_bot_d2, weak_hyst_bot_d1;
    reg strong_hyst_top_d2, strong_hyst_top_d1, strong_hyst_mid_d2, strong_hyst_mid_d1, strong_hyst_bot_d2, strong_hyst_bot_d1;
    wire weak_hyst_top_right = (gaussian_x_d < IMAGE_WIDTH) ? edge_line_rd_q[3] : 1'b0;
    wire weak_hyst_mid_right = (gaussian_x_d < IMAGE_WIDTH) ? edge_line_rd_q[2] : 1'b0;
    wire strong_hyst_top_right = (gaussian_x_d < IMAGE_WIDTH) ? edge_line_rd_q[1] : 1'b0;
    wire strong_hyst_mid_right = (gaussian_x_d < IMAGE_WIDTH) ? edge_line_rd_q[0] : 1'b0;
    wire [45:0] edge_line_wr = {edge_line_rd_q[37:30], gaussian_gray_d,
                                edge_line_rd_q[17:6], sobel_mag, sobel_direction,
                                edge_line_rd_q[2], weak_edge_pixel,
                                edge_line_rd_q[0], strong_edge_pixel};
    wire hyst_window_valid = nms_valid && (gaussian_x_d >= 11'd8) && (gaussian_y_d >= 11'd8); //【HX1P35A-移植适配】等待候选的完整 3x3 窗口，边界不引用上一帧残留。
    wire strong_hyst_neighborhood = strong_hyst_top_d2 || strong_hyst_top_d1 || strong_hyst_top_right ||
                                    strong_hyst_mid_d2 || strong_hyst_mid_right ||
                                    strong_hyst_bot_d2 || strong_hyst_bot_d1 || strong_edge_pixel; //【HX1P35A-移植适配】中心以外的八个方向均可作为弱边的强锚点。
    wire weak_hyst_any_a = weak_hyst_top_d2 || weak_hyst_top_d1 || weak_hyst_top_right || weak_hyst_mid_d2;
    wire weak_hyst_any_b = weak_hyst_mid_right || weak_hyst_bot_d2 || weak_hyst_bot_d1 || weak_edge_pixel;
    wire weak_hyst_has_neighbor = weak_hyst_any_a || weak_hyst_any_b; //【HX1P35A-移植适配】中心像素八邻域中至少存在一个双阈值候选，用于删除完全孤立的白色噪点。
    wire weak_hyst_pair_a = (weak_hyst_top_d2 && (weak_hyst_top_d1 || weak_hyst_top_right || weak_hyst_mid_d2)) ||
                            (weak_hyst_top_d1 && (weak_hyst_top_right || weak_hyst_mid_d2)) ||
                            (weak_hyst_top_right && weak_hyst_mid_d2);
    wire weak_hyst_pair_b = (weak_hyst_mid_right && (weak_hyst_bot_d2 || weak_hyst_bot_d1 || weak_edge_pixel)) ||
                            (weak_hyst_bot_d2 && (weak_hyst_bot_d1 || weak_edge_pixel)) ||
                            (weak_hyst_bot_d1 && weak_edge_pixel);
    wire weak_hyst_has_two_neighbors = weak_hyst_pair_a || weak_hyst_pair_b || (weak_hyst_any_a && weak_hyst_any_b); //【HX1P35A-移植适配】并行判断八邻域至少两个弱候选，避免串行加法器进入像素关键路径。
    wire symmetric_hyst_edge = hyst_window_valid && weak_hyst_mid_d1 && strong_hyst_neighborhood &&
                               weak_hyst_has_two_neighbors; //【HX1P35A-移植适配】仅救回连接强边且自身形成连续结构的弱边，拒绝无强锚点的弱纹理噪声。
    wire supported_strong_edge = hyst_window_valid && strong_hyst_mid_d1 && weak_hyst_has_neighbor; //【HX1P35A-移植适配】强边中心若八邻域全黑则判为单点噪声并清零；存在一个邻居即保留，避免损伤细线端点。
    wire horizontal_one_pixel_gap = weak_hyst_mid_d2 && weak_hyst_mid_right &&
                                    (strong_hyst_mid_d2 || strong_hyst_mid_right); //【HX1P35A-移植适配】左右边缘相隔一个空点，且至少一侧是强边时补中间像素。
    wire vertical_one_pixel_gap = weak_hyst_top_d1 && weak_hyst_bot_d1 &&
                                  (strong_hyst_top_d1 || strong_hyst_bot_d1); //【HX1P35A-移植适配】上下方向的一像素断点连接。
    wire diagonal_down_one_pixel_gap = weak_hyst_top_d2 && weak_edge_pixel &&
                                       (strong_hyst_top_d2 || strong_edge_pixel); //【HX1P35A-移植适配】左上到右下方向的一像素断点连接。
    wire diagonal_up_one_pixel_gap = weak_hyst_top_right && weak_hyst_bot_d2 &&
                                     (strong_hyst_top_right || strong_hyst_bot_d2); //【HX1P35A-移植适配】右上到左下方向的一像素断点连接。
    wire one_pixel_gap_edge = hyst_window_valid && !weak_hyst_mid_d1 &&
                              (horizontal_one_pixel_gap || vertical_one_pixel_gap ||
                               diagonal_down_one_pixel_gap || diagonal_up_one_pixel_gap); //【HX1P35A-移植适配】只填补夹在双阈值边缘之间的单像素空洞，不扩展孤立噪点。
    wire edge_core = supported_strong_edge || symmetric_hyst_edge || one_pixel_gap_edge; //【HX1P35A-移植适配】统一输出完整 8 邻域判定结果：强边去孤点、弱边需强锚点、断点仅补一个像素。
    reg edge_core_q, edge_core_de_q; //【HX1P35A-移植适配】融合边缘增加一级寄存，切断梯度比较到 HDMI 输出的长组合路径。
    reg [10:0] edge_x_q, edge_y_q; // 融合边缘对应的扫描坐标。
    wire refined_edge, refined_de;
    wire [10:0] refined_x;
    generate if (ENABLE_EDGE_REFINEMENT) begin : g_edge_refinement
        hx_edge_binary_refine #(.IMAGE_WIDTH(IMAGE_WIDTH)) u_refine (
            .I_clk(I_clk), .I_rst_n(I_rst_n), .I_de(edge_core_de_q),
            .I_x(edge_x_q), .I_y(edge_y_q), .I_edge(edge_core_q),
            .O_de(refined_de), .O_x(refined_x), .O_edge(refined_edge)
        );
    end else begin : g_edge_refinement_bypass
        assign refined_de = edge_core_de_q;
        assign refined_x = edge_x_q;
        assign refined_edge = edge_core_q;
    end endgenerate
    wire [0:0] dilate_line_rd;
    reg edge_dilate_left, edge_dilate_above_left; //【HX1P35A-移植适配】保存左邻和左上邻边缘，提升 HDMI 上的线条可见度。
    wire edge_dilate_above = (refined_x < IMAGE_WIDTH) ? dilate_line_rd[0] : 1'b0;
    wire edge_display_pixel = refined_edge ||
                              ((refined_x != 0) && edge_dilate_left) ||
                              edge_dilate_above ||
                              ((refined_x != 0) && edge_dilate_above_left);

    //【HX1P35A-移植适配】先用亮度与通道差筛选颜色候选，再用同色邻域一致性抑制暗光 Bayer/增益噪点。
    wire raw_red_hit = (I_rgb[23:16] >= 8'd96) && ({1'b0,I_rgb[23:16]} >= ({1'b0,I_rgb[15:8]} + 9'd40)) && ({1'b0,I_rgb[23:16]} >= ({1'b0,I_rgb[7:0]} + 9'd40)); //【HX1P35A-移植适配】红色候选需具备足够亮度和饱和度。
    wire raw_green_hit = (I_rgb[15:8] >= 8'd64) && ({1'b0,I_rgb[15:8]} >= ({1'b0,I_rgb[23:16]} + 9'd16)) && ({1'b0,I_rgb[15:8]} >= ({1'b0,I_rgb[7:0]} + 9'd16)); //【HX1P35A-移植适配】放宽绿色候选以识别偏暗、印刷和偏黄绿色包装；邻域一致性继续过滤孤立噪点。
    wire raw_blue_hit = (I_rgb[7:0] >= 8'd96) && ({1'b0,I_rgb[7:0]} >= ({1'b0,I_rgb[23:16]} + 9'd40)) && ({1'b0,I_rgb[7:0]} >= ({1'b0,I_rgb[15:8]} + 9'd40)); //【HX1P35A-移植适配】蓝色候选需具备足够亮度和饱和度。
    wire [1:0] raw_color = raw_red_hit ? 2'd1 : raw_green_hit ? 2'd2 : raw_blue_hit ? 2'd3 : 2'd0; //【HX1P35A-移植适配】将三色候选编码后共用一套行邻域滤波器。
    assign raw_line_wr = {raw_line_rd[9:2], gray, raw_color}; //【资源优化】旧上一行推进为上两行，同时写入当前灰度与颜色。
    reg [1:0] color_left, color_above_left; //【HX1P35A-移植适配】保存当前行左邻及上一行左上邻的原始颜色。
    wire [1:0] color_above = ((pix_y != 0) && (pix_x < IMAGE_WIDTH)) ? raw_line_rd[1:0] : 2'd0; //【HX1P35A-移植适配】首行不引用上一帧残留行缓存。
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

    wire raw_sharpen_selected = ENABLE_RAW_SHARPEN && I_raw_sharpen_enable && (I_mode == 2'd0);
    wire [2:0] template_status;
    wire [3:0] template_reason;
    wire [14:0] template_best,template_margin;
    wire [4:0] template_misses;
    wire [10:0] template_cx,template_cy;
    generate if(ENABLE_TEMPLATE_TRACKING)begin : g_template
        hx_template_tracker #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT)) u_tracker (
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

    //【HX1P35A-移植适配】逐帧统计目标总面积、各颜色面积和外接矩形。
    reg [10:0] cur_xmin, cur_xmax, cur_ymin, cur_ymax;
    reg [10:0] box_xmin, box_xmax, box_ymin, box_ymax;
    reg [23:0] cur_count, cur_red_count, cur_green_count, cur_blue_count;
    reg [1:0] box_color; // 0:无，1:红，2:绿，3:蓝。【HX1P35A-移植适配】
    localparam TARGET_MISS_BITS = (TARGET_HOLD_FRAMES < 1) ? 1 : $clog2(TARGET_HOLD_FRAMES + 1);
    reg [TARGET_MISS_BITS-1:0] target_miss_count;
    reg target_fresh; // Last completed frame supplied a usable measurement; false while holding/lost.
    wire cur_frame_valid = (cur_count != 0) &&
        (cur_count >= (O_target_found ? TARGET_RELEASE_PIXELS : MIN_TARGET_PIXELS));
    wire target_holding = O_target_found && !target_fresh;

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

    function [19:0] bin16_to_bcd5;
        input [15:0] bin;
        integer i, j;
        reg [19:0] bcd;
        begin
            bcd = 20'd0;
            for (i=15; i>=0; i=i-1) begin
                for (j=0; j<5; j=j+1)
                    if (bcd[j*4 +: 4] >= 5) bcd[j*4 +: 4] = bcd[j*4 +: 4] + 3;
                bcd = {bcd[18:0],bin[i]};
            end
            bin16_to_bcd5 = bcd;
        end
    endfunction

    function [7:0] hex_ascii;
        input [3:0] digit;
        begin
            hex_ascii = (digit < 10) ? ("0" + digit) : ("A" + digit - 10);
        end
    endfunction

    reg [15:0] center_x_bcd, center_y_bcd;
    reg [19:0] applied_exposure_bcd;
    reg [23:0] applied_gain_regs_q;
    reg [1:0] applied_status_q;
    reg applied_has_value_q, applied_toggle_seen;
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
                "F": case(row) 0:font5x7=5'b11111;1:font5x7=5'b10000;2:font5x7=5'b10000;3:font5x7=5'b11110;4:font5x7=5'b10000;5:font5x7=5'b10000;6:font5x7=5'b10000;endcase
                "G": case(row) 0:font5x7=5'b01111;1:font5x7=5'b10000;2:font5x7=5'b10000;3:font5x7=5'b10111;4:font5x7=5'b10001;5:font5x7=5'b10001;6:font5x7=5'b01111;endcase
                "H": case(row) 0:font5x7=5'b10001;1:font5x7=5'b10001;2:font5x7=5'b10001;3:font5x7=5'b11111;4:font5x7=5'b10001;5:font5x7=5'b10001;6:font5x7=5'b10001;endcase
                "I": case(row) 0:font5x7=5'b01110;1:font5x7=5'b00100;2:font5x7=5'b00100;3:font5x7=5'b00100;4:font5x7=5'b00100;5:font5x7=5'b00100;6:font5x7=5'b01110;endcase
                "K": case(row) 0:font5x7=5'b10001;1:font5x7=5'b10010;2:font5x7=5'b10100;3:font5x7=5'b11000;4:font5x7=5'b10100;5:font5x7=5'b10010;6:font5x7=5'b10001;endcase
                "L": case(row) 0:font5x7=5'b10000;1:font5x7=5'b10000;2:font5x7=5'b10000;3:font5x7=5'b10000;4:font5x7=5'b10000;5:font5x7=5'b10000;6:font5x7=5'b11111;endcase
                "M": case(row) 0:font5x7=5'b10001;1:font5x7=5'b11011;2:font5x7=5'b10101;3:font5x7=5'b10101;4:font5x7=5'b10001;5:font5x7=5'b10001;6:font5x7=5'b10001;endcase
                "N": case(row) 0:font5x7=5'b10001;1:font5x7=5'b11001;2:font5x7=5'b11001;3:font5x7=5'b10101;4:font5x7=5'b10011;5:font5x7=5'b10011;6:font5x7=5'b10001;endcase //【HX1P35A-移植适配】CANNY 模式字模。
                "O": case(row) 0:font5x7=5'b01110;1:font5x7=5'b10001;2:font5x7=5'b10001;3:font5x7=5'b10001;4:font5x7=5'b10001;5:font5x7=5'b10001;6:font5x7=5'b01110;endcase
                "P": case(row) 0:font5x7=5'b11110;1:font5x7=5'b10001;2:font5x7=5'b10001;3:font5x7=5'b11110;4:font5x7=5'b10000;5:font5x7=5'b10000;6:font5x7=5'b10000;endcase
                "R": case(row) 0:font5x7=5'b11110;1:font5x7=5'b10001;2:font5x7=5'b10001;3:font5x7=5'b11110;4:font5x7=5'b10100;5:font5x7=5'b10010;6:font5x7=5'b10001;endcase
                "S": case(row) 0:font5x7=5'b01111;1:font5x7=5'b10000;2:font5x7=5'b10000;3:font5x7=5'b01110;4:font5x7=5'b00001;5:font5x7=5'b00001;6:font5x7=5'b11110;endcase
                "T": case(row) 0:font5x7=5'b11111;1:font5x7=5'b00100;2:font5x7=5'b00100;3:font5x7=5'b00100;4:font5x7=5'b00100;5:font5x7=5'b00100;6:font5x7=5'b00100;endcase
                "U": case(row) 0:font5x7=5'b10001;1:font5x7=5'b10001;2:font5x7=5'b10001;3:font5x7=5'b10001;4:font5x7=5'b10001;5:font5x7=5'b10001;6:font5x7=5'b01110;endcase
                "W": case(row) 0:font5x7=5'b10001;1:font5x7=5'b10001;2:font5x7=5'b10001;3:font5x7=5'b10101;4:font5x7=5'b10101;5:font5x7=5'b10101;6:font5x7=5'b01010;endcase
                "X": case(row) 0:font5x7=5'b10001;1:font5x7=5'b10001;2:font5x7=5'b01010;3:font5x7=5'b00100;4:font5x7=5'b01010;5:font5x7=5'b10001;6:font5x7=5'b10001;endcase
                "Y": case(row) 0:font5x7=5'b10001;1:font5x7=5'b10001;2:font5x7=5'b01010;3:font5x7=5'b00100;4:font5x7=5'b00100;5:font5x7=5'b00100;6:font5x7=5'b00100;endcase
                ":": case(row) 2:font5x7=5'b00100;4:font5x7=5'b00100;default:font5x7=5'b00000;endcase
                "/": case(row) 0:font5x7=5'b00001;1:font5x7=5'b00010;2:font5x7=5'b00100;3:font5x7=5'b01000;4:font5x7=5'b10000;default:font5x7=5'b00000;endcase
                "-": case(row) 3:font5x7=5'b11111;default:font5x7=5'b00000;endcase
                "V": case(row) 0:font5x7=5'b10001;1:font5x7=5'b10001;2:font5x7=5'b10001;3:font5x7=5'b10001;4:font5x7=5'b10001;5:font5x7=5'b01010;6:font5x7=5'b00100;endcase
                default: font5x7=5'b00000;
            endcase
        end
    endfunction

    function [7:0] bcd_ascii;
        input [3:0] digit;
        begin bcd_ascii = "0" + digit; end
    endfunction

    // Three aligned stages: address/data prefetch, original ROM lookup, overlay.
    // The untouched example's combinational ROM needs a full clock by itself.
    reg prefetch_vsync, prefetch_hsync, prefetch_de, prefetch_user, prefetch_last;
    reg [23:0] prefetch_rgb;
    reg prefetch_lift;
    reg [10:0] prefetch_x, prefetch_y;
    reg stage_vsync, stage_hsync, stage_de, stage_user, stage_last;
    reg [23:0] stage_rgb;
    reg [10:0] source_x, source_y;
    reg [1:0] prefetch_mode, stage_mode;
    reg prefetch_sharp, stage_sharp;
    wire [10:0] draw_x, draw_y, logo_input_x, logo_input_y;
    wire [4:0] final_ctrl;
    wire [23:0] final_rgb;
    wire [1:0] final_mode;
    wire logo_input_de;
    generate if (ENABLE_RAW_SHARPEN) begin : g_centered_display
        wire [54:0] delayed;
        wire signed [8:0] delta;
        reg [54:0] d1, d2;
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
                enhanced1 <= delayed[53] ?
                    {adjust(delayed[23:16],delta),adjust(delayed[15:8],delta),adjust(delayed[7:0],delta)} : delayed[23:0];
                enhanced2<=enhanced1;
            end
        end
        assign logo_input_x=delayed[45:35];
        assign logo_input_y=delayed[34:24];
        assign logo_input_de=delayed[48];
        assign draw_x=d2[45:35]; assign draw_y=d2[34:24];
        assign final_ctrl=d2[50:46]; assign final_mode=d2[52:51]; assign final_rgb=enhanced2;
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

    wire box_border = (final_mode == 2'd2) && O_target_found && final_ctrl[2] && // Display mode travels with its pixels.
        ((((draw_x == box_xmin) || (draw_x == box_xmax)) && (draw_y >= box_ymin) && (draw_y <= box_ymax)) ||
         (((draw_y == box_ymin) || (draw_y == box_ymax)) && (draw_x >= box_xmin) && (draw_x <= box_xmax)));

    wire [6:0] osd_col = draw_x[10:4];
    wire [1:0] osd_row = draw_y[5:4];
    wire [2:0] glyph_x = draw_x[3:1];
    wire [2:0] glyph_y = draw_y[3:1];
    reg [7:0] osd_char;
    reg [23:0] osd_fg;
    wire applied_osd_region = (osd_row == 0) && (osd_col >= 30) && (osd_col <= 53);
    reg [7:0] applied_osd_char;
    reg [23:0] applied_osd_fg;
    always @(*) begin
        applied_osd_char = " ";
        applied_osd_fg = applied_status_q == 2'd2 ? 24'h60ff60 :
                         applied_status_q == 2'd3 ? 24'hff6060 :
                         applied_status_q == 2'd1 ? 24'hffb040 : 24'hc0c0c0;
        if (!applied_has_value_q) begin
            if (applied_status_q == 2'd0) begin
                case(osd_col)
                    30:applied_osd_char="A";31:applied_osd_char="P";32:applied_osd_char=":";
                    34:applied_osd_char="W";35:applied_osd_char="A";36:applied_osd_char="I";37:applied_osd_char="T";
                    default:applied_osd_char=" ";
                endcase
            end else if (applied_status_q == 2'd1) begin
                case(osd_col)
                    30:applied_osd_char="I";31:applied_osd_char="2";32:applied_osd_char="C";33:applied_osd_char=":";
                    35:applied_osd_char="W";36:applied_osd_char="R";37:applied_osd_char="I";38:applied_osd_char="T";39:applied_osd_char="E";
                    default:applied_osd_char=" ";
                endcase
            end else begin
                case(osd_col)
                    30:applied_osd_char="I";31:applied_osd_char="2";32:applied_osd_char="C";33:applied_osd_char=":";
                    35:applied_osd_char="E";36:applied_osd_char="R";37:applied_osd_char="R";
                    39:applied_osd_char="N";40:applied_osd_char="O";42:applied_osd_char="D";43:applied_osd_char="A";44:applied_osd_char="T";45:applied_osd_char="A";
                    default:applied_osd_char=" ";
                endcase
            end
        end else begin
            case(osd_col)
                30:applied_osd_char="A";31:applied_osd_char="P";
                33:applied_osd_char="E";34:applied_osd_char=":";
                35:applied_osd_char=bcd_ascii(applied_exposure_bcd[19:16]);
                36:applied_osd_char=bcd_ascii(applied_exposure_bcd[15:12]);
                37:applied_osd_char=bcd_ascii(applied_exposure_bcd[11:8]);
                38:applied_osd_char=bcd_ascii(applied_exposure_bcd[7:4]);
                39:applied_osd_char=bcd_ascii(applied_exposure_bcd[3:0]);
                40:applied_osd_char="A";41:applied_osd_char=":";
                42:applied_osd_char=hex_ascii(applied_gain_regs_q[23:20]);
                43:applied_osd_char=hex_ascii(applied_gain_regs_q[19:16]);
                44:applied_osd_char="D";45:applied_osd_char=":";
                46:applied_osd_char=hex_ascii(applied_gain_regs_q[15:12]);
                47:applied_osd_char=hex_ascii(applied_gain_regs_q[11:8]);
                48:applied_osd_char="/";
                49:applied_osd_char=hex_ascii(applied_gain_regs_q[7:4]);
                50:applied_osd_char=hex_ascii(applied_gain_regs_q[3:0]);
                52:applied_osd_char=applied_status_q==2'd2 ? "O" : applied_status_q==2'd1 ? "W" : "E";
                53:applied_osd_char=applied_status_q==2'd2 ? "K" : "R";
                default:applied_osd_char=" ";
            endcase
        end
    end
    wire template_osd_region=ENABLE_TEMPLATE_TRACKING && osd_row==2 && osd_col<38 && draw_y<48;
    reg [63:0] template_text;
    reg [23:0] template_fg;
    reg [7:0] template_char;
    always @(*)begin
        template_fg=24'h40e0ff;
        case(template_status)
            1:begin template_text="LEARN   ";template_fg=24'hffff00;end
            2:begin template_text="TRACK   ";template_fg=24'h60ff60;end
            3:begin template_text="HOLD    ";template_fg=24'hffb040;end
            4:begin template_text="LOST    ";template_fg=24'hff6060;end
            5:begin template_text="FLAT    ";template_fg=24'hff60ff;end
            6:begin template_text="VERIFY  ";template_fg=24'hffff00;end
            default:template_text="READY   ";
        endcase
        case(osd_col)
            0:template_char="T";1:template_char="P";2:template_char="L";3:template_char=":";4:template_char=" ";
            14:template_char="E";15:template_char=":";
            16:template_char=hex_ascii({1'b0,template_best[14:12]});
            17:template_char=hex_ascii(template_best[11:8]);
            18:template_char=hex_ascii(template_best[7:4]);
            19:template_char=hex_ascii(template_best[3:0]);
            21:template_char="U";22:template_char=":";
            23:template_char=hex_ascii({1'b0,template_margin[14:12]});
            24:template_char=hex_ascii(template_margin[11:8]);
            25:template_char=hex_ascii(template_margin[7:4]);
            26:template_char=hex_ascii(template_margin[3:0]);
            28:template_char="R";29:template_char=":";30:template_char=hex_ascii(template_reason);
            32:template_char="M";33:template_char=":";
            34:template_char=hex_ascii({3'b000,template_misses[4]});
            35:template_char=hex_ascii(template_misses[3:0]);
            default:template_char=(osd_col>=5 && osd_col<13) ? (template_text >> ((12-osd_col)*8)) : " ";
        endcase
    end
    wire [4:0] glyph_bits = font5x7(template_osd_region ? template_char : applied_osd_region ? applied_osd_char : osd_char,glyph_y);
    // Existing status overlay stays at the upper left; applied I2C values use a disjoint upper-right strip.
    wire osd_background = ENABLE_STATUS_OSD && final_ctrl[2] &&
        ((draw_x < 11'd432 && draw_y < 11'd32) || template_osd_region || (applied_osd_region && draw_x < 11'd864 && draw_y < 11'd16));
    wire osd_glyph = osd_background && (glyph_x < 3'd5) && (glyph_y < 3'd7) && glyph_bits[4-glyph_x];
    wire [23:0] osd_pixel_fg = template_osd_region ? template_fg : applied_osd_region ? applied_osd_fg : osd_fg;
    wire template_border=ENABLE_TEMPLATE_TRACKING && !final_mode[1] && final_ctrl[2] &&
        ((((draw_x==template_cx-32)||(draw_x==template_cx+31)) && draw_y>=template_cy-32 && draw_y<template_cy+32) ||
         (((draw_y==template_cy-32)||(draw_y==template_cy+31)) && draw_x>=template_cx-32 && draw_x<template_cx+32));

    // Row 0: mode and manual preset; row 1: color tracking; row 2: last I2C-confirmed sensor values.
    always @(*) begin
        osd_char = " ";
        osd_fg = 24'hffffff;
        if (osd_row == 0) begin
            osd_fg = 24'h40e0ff;
            case (osd_col)
                0:osd_char="M"; 1:osd_char="O"; 2:osd_char="D"; 3:osd_char="E"; 4:osd_char=":";
                14:osd_char="E"; 15:osd_char="X"; 16:osd_char="P"; 17:osd_char=":"; 18:osd_char=I_auto_exposure ? "A" : bcd_ascii({2'b00,I_exposure_level});
                default: begin
                    case (final_mode)
                        2'd0: case(osd_col)
                            6:osd_char="R";7:osd_char="A";8:osd_char="W";
                            9:osd_char=I_raw_sharpen_enable && ENABLE_RAW_SHARPEN ? "S" : " ";
                            10:osd_char=I_raw_sharpen_enable && ENABLE_RAW_SHARPEN ? "H" : " ";
                            11:osd_char=I_raw_sharpen_enable && ENABLE_RAW_SHARPEN ? "A" : " ";
                            12:osd_char=I_raw_sharpen_enable && ENABLE_RAW_SHARPEN ? "R" : " ";
                            13:osd_char=I_raw_sharpen_enable && ENABLE_RAW_SHARPEN ? "P" : " ";
                            default:osd_char=" ";
                        endcase
                        2'd1: case(osd_col) 6:osd_char="G";7:osd_char="R";8:osd_char="A";9:osd_char="Y";default:osd_char=" ";endcase
                        2'd2: case(osd_col) 6:osd_char="C";7:osd_char="O";8:osd_char="L";9:osd_char="O";10:osd_char="R";default:osd_char=" ";endcase
                        default: case(osd_col) 6:osd_char="C";7:osd_char="A";8:osd_char="N";9:osd_char="N";10:osd_char="Y";default:osd_char=" ";endcase
                    endcase
                end
            endcase
            // TRACK=current measurement; HOLD=last valid C/X/Y, not a new detection.
            if (osd_col >= 22) begin
                osd_fg = !O_target_found ? 24'hff6060 : target_holding ? 24'hffb040 : 24'h60ff60;
                case (osd_col)
                    22:osd_char=!O_target_found ? "L" : target_holding ? "H" : "T";
                    23:osd_char=!O_target_found ? "O" : target_holding ? "O" : "R";
                    24:osd_char=!O_target_found ? "S" : target_holding ? "L" : "A";
                    25:osd_char=!O_target_found ? "T" : target_holding ? "D" : "C";
                    26:osd_char=(!O_target_found || target_holding) ? " " : "K";
                    default:osd_char=" ";
                endcase
            end
        end else if (osd_row == 1) begin
            osd_fg = !O_target_found ? 24'hff6060 : target_holding ? 24'hffb040 : 24'h60ff60;
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
                20:osd_char=bcd_ascii(pixel_count_bcd[23:20]);
                21:osd_char=bcd_ascii(pixel_count_bcd[19:16]);
                22:osd_char=bcd_ascii(pixel_count_bcd[15:12]);
                23:osd_char=bcd_ascii(pixel_count_bcd[11:8]);
                24:osd_char=bcd_ascii(pixel_count_bcd[7:4]);
                25:osd_char=bcd_ascii(pixel_count_bcd[3:0]);
                default:osd_char=" ";
            endcase
        end else if (osd_row == 2) begin
            osd_fg = applied_status_q == 2'd2 ? 24'h60ff60 :
                     applied_status_q == 2'd3 ? 24'hff6060 :
                     applied_status_q == 2'd1 ? 24'hffb040 : 24'hc0c0c0;
            if (!applied_has_value_q) begin
                if (applied_status_q == 2'd0) begin
                    case(osd_col)
                        0:osd_char="A";1:osd_char="P";2:osd_char=":";
                        4:osd_char="W";5:osd_char="A";6:osd_char="I";7:osd_char="T";
                        default:osd_char=" ";
                    endcase
                end else if (applied_status_q == 2'd1) begin
                    case(osd_col)
                        0:osd_char="I";1:osd_char="2";2:osd_char="C";3:osd_char=":";
                        5:osd_char="W";6:osd_char="R";7:osd_char="I";8:osd_char="T";9:osd_char="E";
                        default:osd_char=" ";
                    endcase
                end else begin
                    case(osd_col)
                        0:osd_char="I";1:osd_char="2";2:osd_char="C";3:osd_char=":";
                        5:osd_char="E";6:osd_char="R";7:osd_char="R";
                        9:osd_char="N";10:osd_char="O";12:osd_char="D";13:osd_char="A";14:osd_char="T";15:osd_char="A";
                        default:osd_char=" ";
                    endcase
                end
            end else begin
                case(osd_col)
                    0:osd_char="A";1:osd_char="P";
                    3:osd_char="E";4:osd_char=":";
                    5:osd_char=bcd_ascii(applied_exposure_bcd[19:16]);
                    6:osd_char=bcd_ascii(applied_exposure_bcd[15:12]);
                    7:osd_char=bcd_ascii(applied_exposure_bcd[11:8]);
                    8:osd_char=bcd_ascii(applied_exposure_bcd[7:4]);
                    9:osd_char=bcd_ascii(applied_exposure_bcd[3:0]);
                    11:osd_char="A";12:osd_char=":";
                    13:osd_char=hex_ascii(applied_gain_regs_q[23:20]);
                    14:osd_char=hex_ascii(applied_gain_regs_q[19:16]);
                    16:osd_char="D";17:osd_char=":";
                    18:osd_char=hex_ascii(applied_gain_regs_q[15:12]);
                    19:osd_char=hex_ascii(applied_gain_regs_q[11:8]);
                    20:osd_char="/";
                    21:osd_char=hex_ascii(applied_gain_regs_q[7:4]);
                    22:osd_char=hex_ascii(applied_gain_regs_q[3:0]);
                    24:osd_char=applied_status_q==2'd2 ? "O" : applied_status_q==2'd1 ? "W" : "E";
                    25:osd_char=applied_status_q==2'd2 ? "K" : applied_status_q==2'd1 ? "R" : "R";
                    26:osd_char=applied_status_q==2'd3 ? "R" : " ";
                    default:osd_char=" ";
                endcase
            end
        end
    end

    reg [23:0] base_rgb;
    // Do not feed the Canny/overlay mux into the denoiser's half-cycle path.
    // Other modes bypass filtering downstream; history only needs RAW/GRAY.
    wire [23:0] display_source = I_mode[0] ? {gray,gray,gray} : I_rgb;
    // Display-only, causal 2x2 filter: no line/coordinate displacement.
    // Reject the entire window if any channel differs by more than 24.
    // Thus equal-luma chromatic edges are protected as well as luma edges.
    wire [25:0] display_above;
    reg [25:0] display_left, display_above_left;
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
        hx_eram_line_store #(.DATA_WIDTH(26)) u_display_row (
            .clk(I_clk), .rd_addr(pix_x), .wr_addr(pix_x),
            .wr_en(I_rst_n && I_de && (pix_x < IMAGE_WIDTH)),
            .wr_data({I_mode,display_source}), .rd_data(display_above)
        );
    end else begin : g_no_display_denoise
        assign display_above = 26'd0;
    end endgenerate
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            display_left <= 0; display_above_left <= 0;
            display_sum_q <= 0; display_flat_q <= 0;
        end else begin
            display_flat_q <= ENABLE_DISPLAY_DENOISE && I_de && !I_mode[1] &&
                (pix_x > 0) && (pix_y > 0) &&
                (display_left[25:24] == I_mode) && (display_above[25:24] == I_mode) &&
                (display_above_left[25:24] == I_mode) &&
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
    reg [23:0] overlay_rgb;
    //【HX1P35A-移植适配】00 原图、01 灰度、10 彩色目标掩膜、11 全屏轻量 Canny 边缘。
    always @(*) begin
        case(I_mode)
            2'd1: base_rgb = {gray,gray,gray};
            2'd2: base_rgb = color_overlay_rgb; //【HX1P35A-移植适配】COLOR 不再因未命中目标而整屏全黑。
            2'd3: base_rgb = edge_display_pixel ? 24'hffffff : 24'h000000; //【HX1P35A-移植适配】Canny 输出使用强细节补偿和 2x2 加粗后的边缘。
            default: base_rgb = I_rgb;
        endcase
    end

    always @(*) begin
        overlay_rgb = final_rgb;
        if (osd_glyph) overlay_rgb = osd_pixel_fg;
        else if (osd_background) overlay_rgb = 24'h101018;
        else if (template_border) overlay_rgb = template_fg;
        else if (box_border) overlay_rgb = target_holding ? 24'hffb040 : 24'hffff00;
        if (final_ctrl[2] && logo_active_q && logo_pixel_q[24]) overlay_rgb = logo_pixel_q[23:0];
        // Small top-right strip: gray=unlearned, blue=capturing, green=applied, red=invalid white field.
        if(ENABLE_CAL_STATUS && draw_y<6 && draw_x>=IMAGE_WIDTH-64)
            case(I_cal_status)
                1:overlay_rgb=24'h4080ff;
                2:overlay_rgb=24'h20e060;
                3:overlay_rgb=24'hff3030;
                default:overlay_rgb=24'h808080;
            endcase
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            x <= 0; y <= 0;
            raw_top_d2 <= 0; raw_top_d1 <= 0; raw_mid_d2 <= 0; raw_mid_d1 <= 0; raw_bot_d2 <= 0; raw_bot_d1 <= 0; //【HX1P35A-移植适配】复位 Gaussian 滑动窗口。
            gaussian_gray_q <= 0; gaussian_x_q <= 0; gaussian_y_q <= 0; gaussian_de_q <= 0; //【HX1P35A-移植适配】复位 Gaussian 流水寄存器及坐标。
            gaussian_gray_d <= 0; gaussian_x_d <= 0; gaussian_y_d <= 0; gaussian_de_d <= 0; edge_line_rd_q <= 0; //【资源优化】复位 ERAM 读数据对齐级。
            top_d2 <= 0; top_d1 <= 0; mid_d2 <= 0; mid_d1 <= 0; bot_d2 <= 0; bot_d1 <= 0;
            mag_top_d2 <= 0; mag_top_d1 <= 0; mag_mid_d2 <= 0; mag_mid_d1 <= 0; mag_bot_d2 <= 0; mag_bot_d1 <= 0; //【HX1P35A-移植适配】复位 Sobel 幅值细化窗口。
            dir_mid_d2 <= 0; dir_mid_d1 <= 0; //【HX1P35A-移植适配】复位局部极大值方向窗口。
            weak_hyst_top_d2 <= 0; weak_hyst_top_d1 <= 0; weak_hyst_mid_d2 <= 0; weak_hyst_mid_d1 <= 0; weak_hyst_bot_d2 <= 0; weak_hyst_bot_d1 <= 0;
            strong_hyst_top_d2 <= 0; strong_hyst_top_d1 <= 0; strong_hyst_mid_d2 <= 0; strong_hyst_mid_d1 <= 0; strong_hyst_bot_d2 <= 0; strong_hyst_bot_d1 <= 0; //【HX1P35A-移植适配】复位对称 8 邻域滞后窗口。
            edge_core_q <= 0; edge_core_de_q <= 0; edge_x_q <= 0; edge_y_q <= 0;
            edge_dilate_left <= 0; edge_dilate_above_left <= 0; //【HX1P35A-移植适配】复位边缘加粗邻域状态。
            color_left <= 0; color_above_left <= 0; //【HX1P35A-移植适配】复位颜色邻域一致性状态。
            cur_count <= 0; cur_red_count <= 0; cur_green_count <= 0; cur_blue_count <= 0;
            cur_xmin <= 11'd2047; cur_ymin <= 11'd2047; cur_xmax <= 0; cur_ymax <= 0;
            box_xmin <= 0; box_ymin <= 0; box_xmax <= 0; box_ymax <= 0; box_color <= 0;
            center_x_bcd <= 0; center_y_bcd <= 0; pixel_count_bcd <= 0;
            applied_exposure_bcd <= 0; applied_gain_regs_q <= 0; applied_status_q <= 0;
            applied_has_value_q <= 0; applied_toggle_seen <= 0;
            O_target_found <= 0; O_target_pixels <= 0;
            target_fresh <= 0; target_miss_count <= 0;
            frame_luma_sum <= 0; frame_highlight_count <= 0; frame_shadow_count <= 0; O_frame_luma <= 0; O_frame_highlights <= 0; O_frame_shadows <= 0; O_frame_luma_toggle <= 0; //【HX1P35A-移植适配】复位自动曝光亮度、高光及暗部统计。
            prefetch_vsync <= 0; prefetch_hsync <= 0; prefetch_de <= 0; prefetch_user <= 0; prefetch_last <= 0;
            prefetch_rgb <= 0; prefetch_x <= 0; prefetch_y <= 0;
            prefetch_lift <= 0;
            stage_vsync <= 0; stage_hsync <= 0; stage_de <= 0; stage_user <= 0; stage_last <= 0;
            stage_rgb <= 0; source_x <= 0; source_y <= 0;
            prefetch_mode<=0; stage_mode<=0; prefetch_sharp<=0; stage_sharp<=0;
            O_vsync <= 0; O_hsync <= 0; O_de <= 0; O_user <= 0; O_last <= 0; O_rgb <= 0;
        end else begin
            // All modes, coordinates and five video flags share the ROM's
            // address/lookup/overlay latency; DDR read timing is unchanged.
            prefetch_vsync <= I_vsync; prefetch_hsync <= I_hsync; prefetch_de <= I_de;
            prefetch_user <= I_user; prefetch_last <= I_last;
            prefetch_rgb <= I_de ? base_rgb : 24'h000000;
            prefetch_mode<=I_mode; stage_mode<=prefetch_mode;
            prefetch_sharp<=raw_sharpen_selected; stage_sharp<=prefetch_sharp;
            prefetch_lift <= ENABLE_SHADOW_LIFT && !I_mode[1];
            prefetch_x <= pix_x; prefetch_y <= pix_y;
            stage_vsync <= prefetch_vsync; stage_hsync <= prefetch_hsync; stage_de <= prefetch_de;
            stage_user <= prefetch_user; stage_last <= prefetch_last;
            stage_rgb <= prefetch_lift ? {lift_shadow(display_filtered[23:16]),
                lift_shadow(display_filtered[15:8]),lift_shadow(display_filtered[7:0])} : display_filtered;
            source_x <= prefetch_x; source_y <= prefetch_y;
            {O_vsync,O_hsync,O_de,O_user,O_last} <= final_ctrl;
            O_rgb <= final_ctrl[2] ? overlay_rgb : 24'h000000;

            if (I_applied_update_toggle != applied_toggle_seen) begin
                applied_exposure_bcd <= bin16_to_bcd5(I_applied_exposure);
                applied_gain_regs_q <= I_applied_gain_regs;
                applied_status_q <= I_applied_status;
                applied_has_value_q <= I_applied_has_value;
                applied_toggle_seen <= I_applied_update_toggle;
            end

            gaussian_de_q <= I_de; //【HX1P35A-移植适配】Gaussian 输出有效标志延迟一级以切断长组合路径。
            gaussian_de_d <= gaussian_de_q;
            edge_line_rd_q <= edge_line_rd;
            if (gaussian_de_q) begin
                gaussian_gray_d <= gaussian_gray_q;
                gaussian_x_d <= gaussian_x_q;
                gaussian_y_d <= gaussian_y_q;
            end
            edge_core_de_q <= gaussian_de_d; //【资源优化】边缘融合结果与新增 ERAM 对齐级同步。
            if (gaussian_de_d) begin
                edge_core_q <= edge_core; //【HX1P35A-移植适配】寄存融合边缘，保证 HDMI 像素时序。
                edge_x_q <= gaussian_x_d; //【资源优化】坐标与 ERAM 对齐后的融合边缘保持同拍。
                edge_y_q <= gaussian_y_d;
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
                frame_highlight_count <= (gray >= 8'd245) ? 12'd1 : 12'd0; //【HX1P35A-移植适配】从新帧首像素重新统计真正接近削顶的高光。
                frame_shadow_count <= (gray <= 8'd48) ? 12'd1 : 12'd0; //【HX1P35A-移植适配】从新帧首像素重新统计深暗区域。
            end else if (luma_sample) begin
                frame_luma_sum <= frame_luma_sum + gray; //【HX1P35A-移植适配】全画面稀疏亮度累加。
                if (highlight_sample) frame_highlight_count <= frame_highlight_count + 1'b1; //【HX1P35A-移植适配】累计饱和区域面积。
                if (shadow_sample) frame_shadow_count <= frame_shadow_count + 1'b1; //【HX1P35A-移植适配】累计深暗区域面积。
            end

            if (I_de && (pix_x < IMAGE_WIDTH)) begin
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

            if (gaussian_de_d && (gaussian_x_d < IMAGE_WIDTH)) begin //【资源优化】使用与锁存 ERAM 读数据对齐的坐标推进。
                if (gaussian_x_d == 0) begin
                    top_d2 <= 0; top_d1 <= top_right; //【HX1P35A-移植适配】新行重新装载 Sobel 上行。
                    mid_d2 <= 0; mid_d1 <= mid_right; //【HX1P35A-移植适配】新行重新装载 Sobel 中行。
                    bot_d2 <= 0; bot_d1 <= gaussian_gray_d; //【HX1P35A-移植适配】Sobel 新行装载寄存后的平滑像素。
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
                    bot_d2 <= bot_d1; bot_d1 <= gaussian_gray_d; //【HX1P35A-移植适配】Sobel 当前行窗口输入寄存后的平滑灰度。
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

            if (refined_de && (refined_x < IMAGE_WIDTH)) begin
                edge_dilate_left <= refined_edge;
                edge_dilate_above_left <= (refined_x == 0) ? 1'b0 : edge_dilate_above;
            end

            if (frame_start) begin
                //【HX1P35A-移植适配】锁存上一帧跟踪结果、BCD 信息及主颜色，再初始化本帧统计。
                O_target_pixels <= cur_count;
                pixel_count_bcd <= bin24_to_bcd6(clipped_count); // Never substitute an old area during HOLD/LOST.
                target_fresh <= cur_frame_valid;
                if (cur_frame_valid) begin
                    O_target_found <= 1'b1;
                    target_miss_count <= 0;
                    box_xmin <= next_box_xmin; box_xmax <= next_box_xmax;
                    box_ymin <= next_box_ymin; box_ymax <= next_box_ymax;
                    center_x_bcd <= bin11_to_bcd4(next_center_x);
                    center_y_bcd <= bin11_to_bcd4(next_center_y);
                    if ((cur_red_count >= cur_green_count) && (cur_red_count >= cur_blue_count)) box_color <= 2'd1;
                    else if (cur_green_count >= cur_blue_count) box_color <= 2'd2;
                    else box_color <= 2'd3;
                end else if (O_target_found && (target_miss_count < TARGET_HOLD_FRAMES)) begin
                    // No measurement: retain the last valid colour/box/centre for a bounded interval.
                    // Saturation at the hold budget avoids counter wrap and indefinite stale locks.
                    target_miss_count <= target_miss_count + 1'b1;
                end else begin
                    O_target_found <= 1'b0;
                    target_miss_count <= 0;
                    box_color <= 2'd0;
                    box_xmin <= 0; box_xmax <= 0; box_ymin <= 0; box_ymax <= 0;
                    center_x_bcd <= 0; center_y_bcd <= 0;
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
    input wire [54:0] payload,
    output reg [54:0] delayed,
    output reg signed [8:0] delta
);
    reg [10:0] slot;
    reg [11:0] warm;
    wire de=payload[48];
    wire [10:0] x=payload[45:35], y=payload[34:24];
    wire [15:0] luma_sum=payload[23:16]*8'd77+payload[15:8]*8'd150+payload[7:0]*8'd29;
    wire [7:0] gray=luma_sum[15:8];
    wire [54:0] fifo_read;
    wire [28:0] rows;
    // Two luma rows + two mode-valid rows + previous row's clock-slot tag.
    hx_eram_line_store #(.DATA_WIDTH(29)) u_rows (
        .clk(clk),.rd_addr(x),.wr_addr(x),.wr_en(rst_n && de && x<IMAGE_WIDTH),
        .wr_data({slot,rows[16],payload[54],rows[7:0],gray}),.rd_data(rows)
    );
    hx_eram_line_store #(.DATA_WIDTH(55)) u_video_slots (
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
            delayed<=warm==2048 ? fifo_read : 55'd0;
            delta<=warm==2048 ? $signed(correction_read) : 9'sd0;
            // First stage only captures RAM outputs. Arithmetic starts on a
            // full-cycle registered path, not the half-cycle ERAM read path.
            taps[0]<=top2;taps[1]<=top1;taps[2]<=rows[15:8];
            taps[3]<=mid2;taps[4]<=mid1;taps[5]<=rows[7:0];
            taps[6]<=bot2;taps[7]<=bot1;taps[8]<=gray;
            center0<=mid1;tag[0]<=midtag1;
            valid[0]<=de && x>=2 && y>=2 && x<IMAGE_WIDTH &&
                topv2 && topv1 && rows[17] && midv2 && midv1 && rows[16] &&
                botv2 && botv1 && payload[54];
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
                    topv2<=0;topv1<=rows[17];midv2<=0;midv1<=rows[16];botv2<=0;botv1<=payload[54];
                end else begin
                    top2<=top1;top1<=rows[15:8];mid2<=mid1;mid1<=rows[7:0];bot2<=bot1;bot1<=gray;
                    topv2<=topv1;topv1<=rows[17];midv2<=midv1;midv1<=rows[16];botv2<=botv1;botv1<=payload[54];
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
