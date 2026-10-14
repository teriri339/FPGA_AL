`timescale 1ns / 1ps
//【HX1P35A-移植适配】HDMI 像素域视觉流水线：灰度、3x3 Sobel、三原色目标、平滑跟踪框和信息 OSD。
module hx_vision_pipeline #(
    parameter IMAGE_WIDTH = 1280,
    parameter MIN_TARGET_PIXELS = 24'd800,
    parameter SOBEL_THRESHOLD_DARK = 12'd40, //【HX1P35A-移植适配】暗光下保留床沿、木板缝等弱边缘。
    parameter SOBEL_THRESHOLD_NORMAL = 12'd64, //【HX1P35A-移植适配】普通室内照明的默认边缘门限。
    parameter SOBEL_THRESHOLD_BRIGHT = 12'd96 //【HX1P35A-移植适配】高亮画面提高门限以抑制纹理噪点。
) (
    input wire I_clk, input wire I_rst_n,
    input wire I_vsync, input wire I_hsync, input wire I_de,
    input wire I_user, input wire I_last, input wire [23:0] I_rgb,
    input wire [1:0] I_mode,
    input wire [1:0] I_exposure_level, //【HX1P35A-移植适配】在 HDMI OSD 中显示当前曝光档位。
    input wire I_auto_exposure, //【HX1P35A-移植适配】OSD 显示 AUTO 状态。
    output reg O_vsync, output reg O_hsync, output reg O_de,
    output reg O_user, output reg O_last, output reg [23:0] O_rgb,
    output reg O_target_found, output reg [23:0] O_target_pixels,
    output reg [7:0] O_frame_luma, //【HX1P35A-移植适配】整帧稀疏采样平均亮度，供自动曝光使用。
    output reg [11:0] O_frame_highlights, //【HX1P35A-移植适配】逐帧接近饱和样点数量，供自动曝光保护高光。
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
    wire highlight_sample = luma_sample && (gray >= 8'd235); //【HX1P35A-移植适配】统计接近 8 位饱和的高光样点。
    reg [19:0] frame_luma_sum; //【HX1P35A-移植适配】最大 3600*255，小于 20 位上限。
    reg [11:0] frame_highlight_count; //【HX1P35A-移植适配】3600 个样点的高光计数。

    //【HX1P35A-移植适配】两行缓存构成真正的 3x3 Sobel 窗口；边界两行/两列强制为黑色。
    reg [7:0] gray_line1 [0:IMAGE_WIDTH-1];
    reg [7:0] gray_line2 [0:IMAGE_WIDTH-1];
    reg [7:0] top_d2, top_d1, mid_d2, mid_d1, bot_d2, bot_d1;
    wire [7:0] top_right = (pix_x < IMAGE_WIDTH) ? gray_line2[pix_x] : 8'd0;
    wire [7:0] mid_right = (pix_x < IMAGE_WIDTH) ? gray_line1[pix_x] : 8'd0;
    wire [10:0] gx_pos = {3'd0,top_right} + ({3'd0,mid_right} << 1) + {3'd0,gray};
    wire [10:0] gx_neg = {3'd0,top_d2} + ({3'd0,mid_d2} << 1) + {3'd0,bot_d2};
    wire [10:0] gy_pos = {3'd0,top_d2} + ({3'd0,top_d1} << 1) + {3'd0,top_right};
    wire [10:0] gy_neg = {3'd0,bot_d2} + ({3'd0,bot_d1} << 1) + {3'd0,gray};
    wire [10:0] gx_abs = (gx_pos >= gx_neg) ? (gx_pos - gx_neg) : (gx_neg - gx_pos);
    wire [10:0] gy_abs = (gy_pos >= gy_neg) ? (gy_pos - gy_neg) : (gy_neg - gy_pos);
    wire [11:0] sobel_mag = {1'b0,gx_abs} + {1'b0,gy_abs};
    wire sobel_valid = I_de && (pix_x >= 11'd2) && (pix_y >= 11'd2);
    wire [11:0] sobel_threshold = (O_frame_luma < 8'd72) ? SOBEL_THRESHOLD_DARK :
                                  (O_frame_luma < 8'd145) ? SOBEL_THRESHOLD_NORMAL : SOBEL_THRESHOLD_BRIGHT; //【HX1P35A-移植适配】依据上一帧全局亮度自适应门限。
    wire edge_pixel = sobel_valid && (sobel_mag >= sobel_threshold); //【HX1P35A-移植适配】弱光降低阈值，高亮自动抑噪。

    //【HX1P35A-移植适配】暗光下采用较低亮度门限和 9 位通道差比较，兼顾实拍颜色与抗噪声能力。
    wire red_hit = (I_rgb[23:16] > 8'd80) && ({1'b0,I_rgb[23:16]} > ({1'b0,I_rgb[15:8]} + 9'd24)) && ({1'b0,I_rgb[23:16]} > ({1'b0,I_rgb[7:0]} + 9'd24)); //【HX1P35A-移植适配】放宽红色检测。
    wire green_hit = (I_rgb[15:8] > 8'd80) && ({1'b0,I_rgb[15:8]} > ({1'b0,I_rgb[23:16]} + 9'd24)) && ({1'b0,I_rgb[15:8]} > ({1'b0,I_rgb[7:0]} + 9'd24)); //【HX1P35A-移植适配】放宽绿色检测。
    wire blue_hit = (I_rgb[7:0] > 8'd80) && ({1'b0,I_rgb[7:0]} > ({1'b0,I_rgb[23:16]} + 9'd24)) && ({1'b0,I_rgb[7:0]} > ({1'b0,I_rgb[15:8]} + 9'd24)); //【HX1P35A-移植适配】放宽蓝色检测。
    wire target_hit = I_de && (red_hit || green_hit || blue_hit);
    wire [23:0] target_mask_rgb = red_hit ? 24'hff0000 : green_hit ? 24'h00ff00 : blue_hit ? 24'h0000ff : 24'h000000;
    wire [23:0] dim_rgb = {1'b0,I_rgb[23:17],1'b0,I_rgb[15:9],1'b0,I_rgb[7:1]}; //【HX1P35A-移植适配】保留半亮原图作为 COLOR 背景。
    wire [23:0] color_overlay_rgb = target_hit ? target_mask_rgb : dim_rgb; //【HX1P35A-移植适配】目标高亮，未命中区域仍可观察。

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
    reg [10:0] draw_x, draw_y;

    wire box_border = O_target_found && stage_de &&
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
                    case (I_mode)
                        2'd0: case(osd_col) 6:osd_char="R";7:osd_char="A";8:osd_char="W";default:osd_char=" ";endcase
                        2'd1: case(osd_col) 6:osd_char="G";7:osd_char="R";8:osd_char="A";9:osd_char="Y";default:osd_char=" ";endcase
                        2'd2: case(osd_col) 6:osd_char="C";7:osd_char="O";8:osd_char="L";9:osd_char="O";10:osd_char="R";default:osd_char=" ";endcase
                        default: case(osd_col) 6:osd_char="S";7:osd_char="O";8:osd_char="B";9:osd_char="E";10:osd_char="L";default:osd_char=" ";endcase
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
    reg [23:0] overlay_rgb;
    //【HX1P35A-移植适配】00 原图、01 灰度、10 彩色目标掩膜、11 Sobel 边缘。
    always @(*) begin
        case(I_mode)
            2'd1: base_rgb = {gray,gray,gray};
            2'd2: base_rgb = color_overlay_rgb; //【HX1P35A-移植适配】COLOR 不再因未命中目标而整屏全黑。
            2'd3: base_rgb = edge_pixel ? 24'hffffff : 24'h000000;
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
            top_d2 <= 0; top_d1 <= 0; mid_d2 <= 0; mid_d1 <= 0; bot_d2 <= 0; bot_d1 <= 0;
            cur_count <= 0; cur_red_count <= 0; cur_green_count <= 0; cur_blue_count <= 0;
            cur_xmin <= 11'd2047; cur_ymin <= 11'd2047; cur_xmax <= 0; cur_ymax <= 0;
            box_xmin <= 0; box_ymin <= 0; box_xmax <= 0; box_ymax <= 0; box_color <= 0;
            center_x_bcd <= 0; center_y_bcd <= 0; pixel_count_bcd <= 0;
            O_target_found <= 0; O_target_pixels <= 0;
            frame_luma_sum <= 0; frame_highlight_count <= 0; O_frame_luma <= 0; O_frame_highlights <= 0; O_frame_luma_toggle <= 0; //【HX1P35A-移植适配】复位自动曝光亮度及高光统计。
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

            if (frame_start) begin //【HX1P35A-移植适配】帧首发布上一帧亮度，并从当前首像素重新累计。
                O_frame_luma <= frame_luma_sum[19:12]; //【HX1P35A-移植适配】用移位代替除法器，降低逻辑和时序开销。
                O_frame_highlights <= frame_highlight_count; //【HX1P35A-移植适配】锁存上一帧高光面积用于防过曝。
                O_frame_luma_toggle <= ~O_frame_luma_toggle; //【HX1P35A-移植适配】跨域接收端据此识别新一帧统计值。
                frame_luma_sum <= {12'd0,gray}; //【HX1P35A-移植适配】当前 (0,0) 像素作为新一帧第一个样点。
                frame_highlight_count <= (gray >= 8'd235) ? 12'd1 : 12'd0; //【HX1P35A-移植适配】从新帧首像素重新统计高光。
            end else if (luma_sample) begin
                frame_luma_sum <= frame_luma_sum + gray; //【HX1P35A-移植适配】全画面稀疏亮度累加。
                if (highlight_sample) frame_highlight_count <= frame_highlight_count + 1'b1; //【HX1P35A-移植适配】累计饱和区域面积。
            end

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
