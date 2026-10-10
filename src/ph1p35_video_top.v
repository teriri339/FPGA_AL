`timescale 1ns / 1ps
// Platform-neutral processing top.  MIPI/ISP and HDMI PHY stay in board adapters.
module ph1p35_video_top #(
    parameter IMAGE_WIDTH = 1280
) (
    input  wire        I_pix_clk,
    input  wire        I_rst_n,
    input  wire        I_pix_vsync,
    input  wire        I_pix_hsync,
    input  wire        I_pix_de,
    input  wire [23:0] I_pix_rgb,
    // 0: source RGB, 1: grayscale, 2: Sobel edge
    input  wire [1:0]  I_mode,
    output wire        O_target_found,
    output wire [23:0] O_target_pixels,
    output wire        O_pix_vsync,
    output wire        O_pix_hsync,
    output wire        O_pix_de,
    output wire [23:0] O_pix_rgb
);
    wire [23:0] processed_rgb;
    wire [10:0] pixel_x;
    wire [10:0] pixel_y;

    video_processor #(.IMAGE_WIDTH(IMAGE_WIDTH)) u_video_processor (
        .I_clk(I_pix_clk), .I_rst_n(I_rst_n), .I_vsync(I_pix_vsync),
        .I_hsync(I_pix_hsync), .I_de(I_pix_de), .I_rgb(I_pix_rgb),
        .I_mode(I_mode), .O_vsync(O_pix_vsync), .O_hsync(O_pix_hsync),
        .O_de(O_pix_de), .O_rgb(processed_rgb), .O_x(pixel_x), .O_y(pixel_y)
    );

    color_target_detect u_target_detect (
        .I_clk(I_pix_clk), .I_rst_n(I_rst_n), .I_vsync(O_pix_vsync),
        .I_de(O_pix_de), .I_rgb(processed_rgb), .O_found(O_target_found),
        .O_pixel_count(O_target_pixels)
    );

    osd_overlay u_osd_overlay (
        .I_clk(I_pix_clk), .I_rst_n(I_rst_n), .I_vsync(O_pix_vsync),
        .I_hsync(O_pix_hsync), .I_de(O_pix_de), .I_rgb(processed_rgb),
        .I_x(pixel_x), .I_y(pixel_y), .I_mode(I_mode),
        .I_target_found(O_target_found), .O_rgb(O_pix_rgb)
    );
endmodule
