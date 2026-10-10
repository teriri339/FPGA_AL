`timescale 1ns / 1ps
//【HX1P35A-移植适配】面向 HDMI 像素流的轻量视觉功能：显示模式、三原色目标、面积/包围框和 OSD。
module hx_vision_pipeline #(
    parameter IMAGE_WIDTH = 1280,
    parameter MIN_TARGET_PIXELS = 24'd800
) (
    input wire I_clk, input wire I_rst_n,
    input wire I_vsync, input wire I_hsync, input wire I_de,
    input wire I_user, input wire I_last, input wire [23:0] I_rgb,
    input wire [1:0] I_mode,
    output reg O_vsync, output reg O_hsync, output reg O_de,
    output reg O_user, output reg O_last, output reg [23:0] O_rgb,
    output reg O_target_found, output reg [23:0] O_target_pixels
);
    reg [10:0] x, y;
    reg [10:0] cur_xmin, cur_xmax, cur_ymin, cur_ymax;
    reg [10:0] box_xmin, box_xmax, box_ymin, box_ymax;
    reg [23:0] cur_count;
    reg [7:0] prev_gray;
    wire [15:0] gray_sum = I_rgb[23:16] * 8'd77 + I_rgb[15:8] * 8'd150 + I_rgb[7:0] * 8'd29;
    wire [7:0] gray = gray_sum[15:8];
    wire [8:0] gray_diff = (gray >= prev_gray) ? (gray - prev_gray) : (prev_gray - gray);
    wire edge_pixel = (gray_diff > 9'd32);
    wire red_hit = (I_rgb[23:16] > 8'd150) && ({1'b0,I_rgb[23:16]} > ({1'b0,I_rgb[15:8]} + 9'd45)) && ({1'b0,I_rgb[23:16]} > ({1'b0,I_rgb[7:0]} + 9'd45));
    wire green_hit = (I_rgb[15:8] > 8'd150) && ({1'b0,I_rgb[15:8]} > ({1'b0,I_rgb[23:16]} + 9'd45)) && ({1'b0,I_rgb[15:8]} > ({1'b0,I_rgb[7:0]} + 9'd45));
    wire blue_hit = (I_rgb[7:0] > 8'd150) && ({1'b0,I_rgb[7:0]} > ({1'b0,I_rgb[23:16]} + 9'd45)) && ({1'b0,I_rgb[7:0]} > ({1'b0,I_rgb[15:8]} + 9'd45));
    wire target_hit = I_de && (red_hit || green_hit || blue_hit);
    wire frame_start = I_user && I_de;
    wire box_border = O_target_found && I_de &&
        ((((x == box_xmin) || (x == box_xmax)) && (y >= box_ymin) && (y <= box_ymax)) ||
         (((y == box_ymin) || (y == box_ymax)) && (x >= box_xmin) && (x <= box_xmax)));
    wire status_bar = I_de && (x < 11'd192) && (y < 11'd20);
    reg [23:0] display_rgb;

    always @(*) begin
        case(I_mode)
            2'd1: display_rgb = {gray,gray,gray};
            2'd2: display_rgb = target_hit ? 24'hffffff : 24'h000000;
            2'd3: display_rgb = edge_pixel ? 24'hffffff : 24'h000000;
            default: display_rgb = I_rgb;
        endcase
        if (box_border) display_rgb = 24'hffff00;
        else if (status_bar) display_rgb = O_target_found ? 24'h00ff00 : 24'hff2020;
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            x <= 0; y <= 0; prev_gray <= 0; cur_count <= 0;
            cur_xmin <= 11'd2047; cur_ymin <= 11'd2047; cur_xmax <= 0; cur_ymax <= 0;
            box_xmin <= 0; box_ymin <= 0; box_xmax <= 0; box_ymax <= 0;
            O_target_found <= 0; O_target_pixels <= 0;
            O_vsync <= 0; O_hsync <= 0; O_de <= 0; O_user <= 0; O_last <= 0; O_rgb <= 0;
        end else begin
            O_vsync <= I_vsync; O_hsync <= I_hsync; O_de <= I_de; O_user <= I_user; O_last <= I_last;
            O_rgb <= I_de ? display_rgb : 24'h000000;
            if (I_de) prev_gray <= gray;
            if (frame_start) begin
                O_target_found <= (cur_count >= MIN_TARGET_PIXELS);
                O_target_pixels <= cur_count;
                box_xmin <= cur_xmin; box_xmax <= cur_xmax; box_ymin <= cur_ymin; box_ymax <= cur_ymax;
                cur_count <= 0; cur_xmin <= 11'd2047; cur_ymin <= 11'd2047; cur_xmax <= 0; cur_ymax <= 0;
                x <= 0; y <= 0;
            end else if (I_de) begin
                if (I_last) begin x <= 0; y <= y + 1'b1; end else x <= x + 1'b1;
                if (target_hit) begin
                    if (cur_count != 24'hffffff) cur_count <= cur_count + 1'b1;
                    if (x < cur_xmin) cur_xmin <= x;
                    if (x > cur_xmax) cur_xmax <= x;
                    if (y < cur_ymin) cur_ymin <= y;
                    if (y > cur_ymax) cur_ymax <= y;
                end
            end
        end
    end
endmodule
