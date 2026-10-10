`timescale 1ns / 1ps
// Hardware OSD: mode/status strip and a fixed frame when target detection is asserted.
module osd_overlay (
    input wire I_clk, input wire I_rst_n, input wire I_vsync, input wire I_hsync,
    input wire I_de, input wire [23:0] I_rgb, input wire [10:0] I_x, input wire [10:0] I_y,
    input wire [1:0] I_mode, input wire I_target_found, output reg [23:0] O_rgb
);
    wire status_bar = I_de && (I_x < 11'd192) && (I_y < 11'd24);
    wire target_box = I_target_found && I_de &&
        (((I_x >= 11'd400) && (I_x < 11'd880) && ((I_y == 11'd220) || (I_y == 11'd500))) ||
         ((I_y >= 11'd220) && (I_y < 11'd501) && ((I_x == 11'd400) || (I_x == 11'd879))));
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) O_rgb <= 24'h0;
        else if(!I_de) O_rgb <= 24'h0;
        else if(target_box) O_rgb <= 24'hff0000;
        else if(status_bar && I_target_found) O_rgb <= 24'h00ff00;
        else if(status_bar && I_mode == 2'd2) O_rgb <= 24'hffff00;
        else if(status_bar) O_rgb <= 24'h00aaff;
        else O_rgb <= I_rgb;
    end
endmodule
