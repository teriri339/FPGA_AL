`timescale 1ns / 1ps
//【HX1P35A-移植适配】HDMI 像素域视觉流水线：灰度、3x3 Sobel、三原色目标、面积/包围框和 OSD。
module hx_vision_pipeline #(
    parameter IMAGE_WIDTH = 1280,
    parameter MIN_TARGET_PIXELS = 24'd800,
    parameter SOBEL_THRESHOLD = 12'd160
) (
    input wire I_clk, input wire I_rst_n,
    input wire I_vsync, input wire I_hsync, input wire I_de,
    input wire I_user, input wire I_last, input wire [23:0] I_rgb,
    input wire [1:0] I_mode,
    output reg O_vsync, output reg O_hsync, output reg O_de,
    output reg O_user, output reg O_last, output reg [23:0] O_rgb,
    output reg O_target_found, output reg [23:0] O_target_pixels
);
    //【HX1P35A-移植适配】坐标使用 VTC 的 user/last 标志；frame_start 当前像素固定为 (0,0)。
    reg [10:0] x, y;
    wire frame_start = I_user && I_de;
    wire [10:0] pix_x = frame_start ? 11'd0 : x;
    wire [10:0] pix_y = frame_start ? 11'd0 : y;

    //【HX1P35A-移植适配】BT.601 灰度近似，最大值 65280，不发生 16 位溢出。
    wire [15:0] gray_sum = I_rgb[23:16] * 8'd77 + I_rgb[15:8] * 8'd150 + I_rgb[7:0] * 8'd29;
    wire [7:0] gray = gray_sum[15:8];

    //【HX1P35A-移植适配】两行缓存构成真正的 3x3 Sobel 窗口；边界两行/两列强制为黑色。
    reg [7:0] gray_line1 [0:IMAGE_WIDTH-1];
    reg [7:0] gray_line2 [0:IMAGE_WIDTH-1];
    reg [7:0] top_d2, top_d1, mid_d2, mid_d1, bot_d2, bot_d1;
    wire [7:0] top_right = (pix_x < IMAGE_WIDTH) ? gray_line2[pix_x] : 8'd0;
    wire [7:0] mid_right = (pix_x < IMAGE_WIDTH) ? gray_line1[pix_x] : 8'd0;
    wire [10:0] gx_pos = {3'd0,top_right} + ({3'd0,mid_right} << 1) + {3'd0,gray};
    wire [10:0] gx_neg = {3'd0,top_d2}   + ({3'd0,mid_d2}   << 1) + {3'd0,bot_d2};
    wire [10:0] gy_pos = {3'd0,top_d2}   + ({3'd0,top_d1}   << 1) + {3'd0,top_right};
    wire [10:0] gy_neg = {3'd0,bot_d2}   + ({3'd0,bot_d1}   << 1) + {3'd0,gray};
    wire [10:0] gx_abs = (gx_pos >= gx_neg) ? (gx_pos - gx_neg) : (gx_neg - gx_pos);
    wire [10:0] gy_abs = (gy_pos >= gy_neg) ? (gy_pos - gy_neg) : (gy_neg - gy_pos);
    wire [11:0] sobel_mag = {1'b0,gx_abs} + {1'b0,gy_abs};
    wire sobel_valid = I_de && (pix_x >= 11'd2) && (pix_y >= 11'd2);
    wire edge_pixel = sobel_valid && (sobel_mag >= SOBEL_THRESHOLD);

    //【HX1P35A-移植适配】使用 9 位比较防止“颜色分量 + 裕量”发生 8 位溢出。
    wire red_hit = (I_rgb[23:16] > 8'd150) && ({1'b0,I_rgb[23:16]} > ({1'b0,I_rgb[15:8]} + 9'd45)) && ({1'b0,I_rgb[23:16]} > ({1'b0,I_rgb[7:0]} + 9'd45));
    wire green_hit = (I_rgb[15:8] > 8'd150) && ({1'b0,I_rgb[15:8]} > ({1'b0,I_rgb[23:16]} + 9'd45)) && ({1'b0,I_rgb[15:8]} > ({1'b0,I_rgb[7:0]} + 9'd45));
    wire blue_hit = (I_rgb[7:0] > 8'd150) && ({1'b0,I_rgb[7:0]} > ({1'b0,I_rgb[23:16]} + 9'd45)) && ({1'b0,I_rgb[7:0]} > ({1'b0,I_rgb[15:8]} + 9'd45));
    wire target_hit = I_de && (red_hit || green_hit || blue_hit);
    wire [23:0] target_mask_rgb = red_hit ? 24'hff0000 : green_hit ? 24'h00ff00 : blue_hit ? 24'h0000ff : 24'h000000;

    //【HX1P35A-移植适配】当前帧统计，下一帧显示稳定的检测结果和包围框。
    reg [10:0] cur_xmin, cur_xmax, cur_ymin, cur_ymax;
    reg [10:0] box_xmin, box_xmax, box_ymin, box_ymax;
    reg [23:0] cur_count;
    wire box_border = O_target_found && I_de &&
        ((((pix_x == box_xmin) || (pix_x == box_xmax)) && (pix_y >= box_ymin) && (pix_y <= box_ymax)) ||
         (((pix_y == box_ymin) || (pix_y == box_ymax)) && (pix_x >= box_xmin) && (pix_x <= box_xmax)));
    wire status_bar = I_de && (pix_x < 11'd192) && (pix_y < 11'd20);
    reg [23:0] display_rgb;

    //【HX1P35A-移植适配】00 原图、01 灰度、10 彩色目标掩膜、11 Sobel 边缘。
    always @(*) begin
        case(I_mode)
            2'd1: display_rgb = {gray,gray,gray};
            2'd2: display_rgb = target_mask_rgb;
            2'd3: display_rgb = edge_pixel ? 24'hffffff : 24'h000000;
            default: display_rgb = I_rgb;
        endcase
        if (box_border) display_rgb = 24'hffff00;
        else if (status_bar) display_rgb = O_target_found ? 24'h00ff00 : 24'hff2020;
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            x <= 0; y <= 0;
            top_d2 <= 0; top_d1 <= 0; mid_d2 <= 0; mid_d1 <= 0; bot_d2 <= 0; bot_d1 <= 0;
            cur_count <= 0; cur_xmin <= 11'd2047; cur_ymin <= 11'd2047; cur_xmax <= 0; cur_ymax <= 0;
            box_xmin <= 0; box_ymin <= 0; box_xmax <= 0; box_ymax <= 0;
            O_target_found <= 0; O_target_pixels <= 0;
            O_vsync <= 0; O_hsync <= 0; O_de <= 0; O_user <= 0; O_last <= 0; O_rgb <= 0;
        end else begin
            //【HX1P35A-移植适配】视觉组合逻辑由此寄存一次，数据与全部视频标志保持同拍。
            O_vsync <= I_vsync; O_hsync <= I_hsync; O_de <= I_de; O_user <= I_user; O_last <= I_last;
            O_rgb <= I_de ? display_rgb : 24'h000000;

            if (I_de && (pix_x < IMAGE_WIDTH)) begin
                gray_line2[pix_x] <= gray_line1[pix_x];
                gray_line1[pix_x] <= gray;
                if (pix_x == 0) begin
                    top_d2 <= 0; top_d1 <= top_right;
                    mid_d2 <= 0; mid_d1 <= mid_right;
                    bot_d2 <= 0; bot_d1 <= gray;
                end else begin
                    top_d2 <= top_d1; top_d1 <= top_right;
                    mid_d2 <= mid_d1; mid_d1 <= mid_right;
                    bot_d2 <= bot_d1; bot_d1 <= gray;
                end
            end

            if (frame_start) begin
                //【HX1P35A-移植适配】先锁存上一帧，再把本帧第一个像素纳入统计，避免漏计和坐标重复。
                O_target_found <= (cur_count >= MIN_TARGET_PIXELS);
                O_target_pixels <= cur_count;
                box_xmin <= cur_xmin; box_xmax <= cur_xmax; box_ymin <= cur_ymin; box_ymax <= cur_ymax;
                cur_count <= target_hit ? 24'd1 : 24'd0;
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
                    if (pix_x < cur_xmin) cur_xmin <= pix_x;
                    if (pix_x > cur_xmax) cur_xmax <= pix_x;
                    if (pix_y < cur_ymin) cur_ymin <= pix_y;
                    if (pix_y > cur_ymax) cur_ymax <= pix_y;
                end
            end
        end
    end
endmodule
