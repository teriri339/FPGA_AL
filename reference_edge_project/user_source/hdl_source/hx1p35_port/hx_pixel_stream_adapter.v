`timescale 1ns / 1ps
//【资源压缩版】参考工程和后级视觉流水线均使用 RGB888，因此直接传递像素与同步标志。
// 原来的 RGB->YUV->RGB 往返会占用 12 个 DSP，并引入量化误差和五拍无效延迟。
module hx_pixel_stream_adapter (
    input wire I_clk, input wire I_rst_n,
    input wire I_vsync, input wire I_hsync, input wire I_de,
    input wire I_user, input wire I_last, input wire [23:0] I_rgb,
    output wire O_vsync, output wire O_hsync, output wire O_de,
    output wire O_user, output wire O_last, output wire [23:0] O_rgb
);
    assign O_vsync = I_vsync;
    assign O_hsync = I_hsync;
    assign O_de    = I_de;
    assign O_user  = I_user;
    assign O_last  = I_last;
    assign O_rgb   = I_rgb;
endmodule

//【HX1P35A-移植适配】以下为从旧工程 rgb2yuv.v 剥离的器件无关运算公式；仅模块名增加 _port。
module rgb2yuv_port(
    input RST_I, input CLK_I, input [7:0] R_I, input [7:0] G_I, input [7:0] B_I,
    output [7:0] Y_O, output [7:0] U_O, output [7:0] V_O
);
    reg [15:0] y_temp1,u_temp1,v_temp1,y_temp2,u_temp2,v_temp2,y_temp3,u_temp3,v_temp3;
    reg [15:0] y_o,u_o,v_o;
    wire [16:0] offset = 17'd32768;
    always @(posedge CLK_I) begin
        if(RST_I) begin y_temp1<=0; y_temp2<=0; y_temp3<=0; u_temp1<=0; u_temp2<=0; u_temp3<=0; v_temp1<=0; v_temp2<=0; v_temp3<=0; end
        else begin y_temp1<=77*R_I; y_temp2<=150*G_I; y_temp3<=29*B_I; u_temp1<=43*R_I; u_temp2<=85*G_I; u_temp3<=128*B_I; v_temp1<=128*R_I; v_temp2<=107*G_I; v_temp3<=21*B_I; end
    end
    always @(posedge CLK_I) begin
        if(RST_I) begin y_o<=0; u_o<=0; v_o<=0; end
        else begin y_o<=y_temp1+y_temp2+y_temp3; u_o<=offset-u_temp1-u_temp2+u_temp3; v_o<=offset+v_temp1-v_temp2-v_temp3; end
    end
    assign Y_O=y_o/256; assign U_O=u_o/256; assign V_O=v_o/256;
endmodule

//【HX1P35A-移植适配】以下为从旧工程 yuv2rgb.v 剥离的器件无关运算公式；仅模块名增加 _port。
module yuv2rgb_port(
    input CLK_I, input RST_I, input [7:0] Y_I, input [7:0] U_I, input [7:0] V_I,
    output reg [7:0] R_O, output reg [7:0] G_O, output reg [7:0] B_O
);
    reg [19:0] R_temp,G_temp,B_temp,t_596Y,t_817Cr,t_200Cb,t_416Cr,t_1033Cb;
    reg r_jud,g_jud,b_jud;
    always @(posedge CLK_I) begin
        if(RST_I) begin t_596Y<=0; t_817Cr<=0; t_200Cb<=0; t_416Cr<=0; t_1033Cb<=0; end
        else begin t_596Y<=255*Y_I; t_817Cr<=359*V_I; t_200Cb<=88*U_I; t_416Cr<=183*V_I; t_1033Cb<=454*U_I; end
    end
    always @(*) begin r_jud=((t_596Y+t_817Cr)>=45952); g_jud=((t_596Y+34688)>=(t_200Cb+t_416Cr)); b_jud=((t_596Y+t_1033Cb)>=58112); end
    always @(posedge CLK_I) begin
        if(RST_I) begin R_temp<=0; G_temp<=0; B_temp<=0; end
        else begin R_temp<=r_jud ? t_596Y+t_817Cr-45952 : 0; G_temp<=g_jud ? t_596Y+34688-t_200Cb-t_416Cr : 0; B_temp<=b_jud ? t_596Y+t_1033Cb-58112 : 0; end
    end
    always @(posedge CLK_I) begin
        if(RST_I) begin R_O<=0; G_O<=0; B_O<=0; end
        else begin R_O<=R_temp[19:17] ? 8'd255 : R_temp[16:8]; G_O<=G_temp[19:17] ? 8'd255 : G_temp[16:8]; B_O<=B_temp[19:17] ? 8'd255 : B_temp[16:8]; end
    end
endmodule
