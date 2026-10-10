`timescale 1ns / 1ps
//【HX1P35A-移植适配】将参考工程的 RGB888 + 同步标志转换为旧算法使用的时钟像素流，
//【HX1P35A-移植适配】并将旧算法的固定四拍流水延时反馈为同步标志延时。
module hx_pixel_stream_adapter (
    input wire I_clk, input wire I_rst_n,
    input wire I_vsync, input wire I_hsync, input wire I_de,
    input wire I_user, input wire I_last, input wire [23:0] I_rgb,
    output wire O_vsync, output wire O_hsync, output wire O_de,
    output wire O_user, output wire O_last, output wire [23:0] O_rgb
);
    wire [7:0] y, u, v;
    wire [7:0] r, g, b;
    //【HX1P35A-移植适配】旧 rgb2yuv/yuv2rgb 从采样输入至 RGB 输出相隔四个时钟沿；
    //【HX1P35A-移植适配】采用五级移位寄存器并取第 4 级，使同步标志与该输出数据同拍。
    reg [4:0] vs_d, hs_d, de_d, user_d, last_d;

    rgb2yuv_port u_rgb2yuv ( //【HX1P35A-移植适配】旧纯算法实例
        .RST_I(~I_rst_n), .CLK_I(I_clk), .R_I(I_rgb[23:16]), .G_I(I_rgb[15:8]), .B_I(I_rgb[7:0]),
        .Y_O(y), .U_O(u), .V_O(v)
    );
    yuv2rgb_port u_yuv2rgb ( //【HX1P35A-移植适配】旧纯算法实例
        .CLK_I(I_clk), .RST_I(~I_rst_n), .Y_I(y), .U_I(u), .V_I(v), .R_O(r), .G_O(g), .B_O(b)
    );

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            vs_d <= 0; hs_d <= 0; de_d <= 0; user_d <= 0; last_d <= 0;
        end else begin
            vs_d <= {vs_d[3:0], I_vsync}; hs_d <= {hs_d[3:0], I_hsync};
            de_d <= {de_d[3:0], I_de}; user_d <= {user_d[3:0], I_user};
            last_d <= {last_d[3:0], I_last};
        end
    end
    assign O_vsync = vs_d[4]; assign O_hsync = hs_d[4]; assign O_de = de_d[4];
    assign O_user = user_d[4]; assign O_last = last_d[4]; assign O_rgb = {r,g,b};
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
