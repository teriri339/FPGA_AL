`timescale 1ns / 1ps
// RGB888 streaming processor.  Sobel output is valid after two image lines.
module video_processor #(
    parameter IMAGE_WIDTH = 1280
) (
    input wire I_clk, input wire I_rst_n, input wire I_vsync, input wire I_hsync,
    input wire I_de, input wire [23:0] I_rgb, input wire [1:0] I_mode,
    output reg O_vsync, output reg O_hsync, output reg O_de, output reg [23:0] O_rgb,
    output reg [10:0] O_x, output reg [10:0] O_y
);
    reg [7:0] line1 [0:IMAGE_WIDTH-1];
    reg [7:0] line2 [0:IMAGE_WIDTH-1];
    reg [7:0] p00,p01,p02,p10,p11,p12,p20,p21,p22;
    reg [7:0] gray;
    reg [10:0] x;
    reg [10:0] y;
    integer gx, gy, ax, ay, mag;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            x <= 0; y <= 0; O_x <= 0; O_y <= 0;
            O_vsync <= 0; O_hsync <= 0; O_de <= 0; O_rgb <= 0;
            p00<=0; p01<=0; p02<=0; p10<=0; p11<=0; p12<=0; p20<=0; p21<=0; p22<=0;
        end else begin
            // Pipeline timing is kept with the generated pixel stream.
            O_vsync <= I_vsync; O_hsync <= I_hsync; O_de <= I_de;
            if (I_vsync) begin x <= 0; y <= 0; end
            else if (I_de) begin
                if (x == IMAGE_WIDTH-1) begin x <= 0; y <= y + 1'b1; end
                else x <= x + 1'b1;
            end
            O_x <= x; O_y <= y;
            if (I_de) begin
                // BT.601 approximation: (77R + 150G + 29B) >> 8
                gray = ((I_rgb[23:16] * 8'd77) + (I_rgb[15:8] * 8'd150) +
                        (I_rgb[7:0] * 8'd29)) >> 8;
                line2[x] <= line1[x];
                line1[x] <= gray;
                p00<=p01; p01<=p02; p02<=line2[x];
                p10<=p11; p11<=p12; p12<=line1[x];
                p20<=p21; p21<=p22; p22<=gray;
                gx = -p00 + p02 - (p10 <<< 1) + (p12 <<< 1) - p20 + p22;
                gy =  p00 + (p01 <<< 1) + p02 - p20 - (p21 <<< 1) - p22;
                ax = (gx < 0) ? -gx : gx;
                ay = (gy < 0) ? -gy : gy;
                mag = ax + ay;
                if (mag > 255) mag = 255;
                case (I_mode)
                    2'd1: O_rgb <= {gray,gray,gray};
                    2'd2: O_rgb <= {mag[7:0],mag[7:0],mag[7:0]};
                    default: O_rgb <= I_rgb;
                endcase
            end else O_rgb <= 24'h000000;
        end
    end
endmodule
