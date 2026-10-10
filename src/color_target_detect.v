`timescale 1ns / 1ps
// Simple red-object classifier; threshold values are intended to be tuned on board.
module color_target_detect #(
    parameter MIN_PIXELS = 24'd800
) (
    input wire I_clk, input wire I_rst_n, input wire I_vsync, input wire I_de,
    input wire [23:0] I_rgb, output reg O_found, output reg [23:0] O_pixel_count
);
    reg vsync_d;
    reg [23:0] count;
    wire red_pixel = I_de && (I_rgb[23:16] > 8'd150) &&
                     ({1'b0,I_rgb[23:16]} > ({1'b0,I_rgb[15:8]} + 9'd45)) &&
                     ({1'b0,I_rgb[23:16]} > ({1'b0,I_rgb[7:0]} + 9'd45));
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin vsync_d<=0; count<=0; O_found<=0; O_pixel_count<=0; end
        else begin
            vsync_d <= I_vsync;
            if (I_vsync && !vsync_d) begin
                O_pixel_count <= count;
                O_found <= (count >= MIN_PIXELS);
                count <= 0;
            end else if (red_pixel && count != 24'hffffff) count <= count + 1'b1;
        end
    end
endmodule
