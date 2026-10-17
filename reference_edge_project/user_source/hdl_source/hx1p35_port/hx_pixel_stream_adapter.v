`timescale 1ns / 1ps
// RGB888 adapter: default direct bypass, optional calibrated spatial gain correction.
// 原来的 RGB->YUV->RGB 往返会占用 12 个 DSP，并引入量化误差和五拍无效延迟。
module hx_pixel_stream_adapter #(
    parameter LSC_ENABLE = 0,
    parameter LSC_GAIN_FILE = "",
    parameter LSC_BLACK_LEVEL = 0,
    parameter SELF_CALIBRATION = 0,
    parameter SOFT_PRESET = 0,
    parameter IMAGE_WIDTH = 1280,
    parameter IMAGE_HEIGHT = 720
) (
    input wire I_clk, input wire I_rst_n,
    input wire I_vsync, input wire I_hsync, input wire I_de,
    input wire I_user, input wire I_last, input wire [23:0] I_rgb,
    input wire I_calibrate, I_invalidate_calibration,
    output wire O_cal_busy, O_cal_valid, O_cal_error,
    output wire O_vsync, output wire O_hsync, output wire O_de,
    output wire O_user, output wire O_last, output wire [23:0] O_rgb
);
    wire gain_we;
    wire [7:0] gain_addr;
    wire [35:0] gain_data;
    generate if (SELF_CALIBRATION && LSC_ENABLE) begin : g_calibration
        hx_white_field_calibrator #(
            .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
            .BLACK_LEVEL(LSC_BLACK_LEVEL)
        ) u_calibrator (
            .I_clk(I_clk), .I_rst_n(I_rst_n), .I_de(I_de), .I_user(I_user), .I_rgb(I_rgb),
            .I_request(I_calibrate), .I_invalidate(I_invalidate_calibration),
            .O_busy(O_cal_busy), .O_valid(O_cal_valid), .O_error(O_cal_error),
            .O_gain_we(gain_we), .O_gain_addr(gain_addr), .O_gain_data(gain_data)
        );
    end else begin : g_no_calibration
        assign gain_we=1'b0;
        assign gain_addr=0;
        assign gain_data=0;
        assign O_cal_busy=1'b0;
        assign O_cal_valid=1'b0;
        assign O_cal_error=1'b0;
    end endgenerate
    generate if (LSC_ENABLE) begin : g_lsc
        hx_white_field_lsc #(
            .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
            .GAIN_FILE(LSC_GAIN_FILE), .BLACK_LEVEL(LSC_BLACK_LEVEL),
            .RUNTIME_GAINS(SELF_CALIBRATION),.SOFT_PRESET(SOFT_PRESET)
        ) u_lsc (
            .I_clk(I_clk), .I_rst_n(I_rst_n),
            .I_vsync(I_vsync), .I_hsync(I_hsync), .I_de(I_de),
            .I_user(I_user), .I_last(I_last), .I_rgb(I_rgb),
            .I_gain_we(gain_we), .I_gain_addr(gain_addr), .I_gain_data(gain_data),
            .I_correction_enable(O_cal_valid),
            .O_vsync(O_vsync), .O_hsync(O_hsync), .O_de(O_de),
            .O_user(O_user), .O_last(O_last), .O_rgb(O_rgb)
        );
    end else begin : g_bypass
    assign O_vsync = I_vsync;
    assign O_hsync = I_hsync;
    assign O_de    = I_de;
    assign O_user  = I_user;
    assign O_last  = I_last;
    assign O_rgb   = I_rgb;
    end endgenerate
endmodule

// Display-domain RGB flat-field correction. Same file keeps existing TD source lists valid.
// 16x9 endpoint nodes, row-major 36-bit words: R[35:24], G[23:12], B[11:0].
// Unsigned Q4.8 gains, 0x100 = unity. Six registered stages, including output.
// ROM has four read ports: physical RAM replication/LUT usage is tool-dependent.
module hx_white_field_lsc #(
    parameter IMAGE_WIDTH = 1280, parameter IMAGE_HEIGHT = 720,
    parameter GRID_WIDTH = 16, parameter GRID_HEIGHT = 9,
    parameter GAIN_FILE = "", parameter BLACK_LEVEL = 0,
    parameter RUNTIME_GAINS = 0, SOFT_PRESET = 0
) (
    input wire I_clk, I_rst_n, I_vsync, I_hsync, I_de, I_user, I_last,
    input wire [23:0] I_rgb,
    input wire I_gain_we, I_correction_enable,
    input wire [7:0] I_gain_addr,
    input wire [35:0] I_gain_data,
    output wire O_vsync, O_hsync, O_de, O_user, O_last,
    output wire [23:0] O_rgb
);
    reg [35:0] gains [0:GRID_WIDTH*GRID_HEIGHT-1];
    generate if (RUNTIME_GAINS) begin : g_gain_write
        always @(posedge I_clk)
            if (I_gain_we && I_gain_addr < GRID_WIDTH*GRID_HEIGHT)
                gains[I_gain_addr] <= I_gain_data;
    end endgenerate
    // Constant elaboration-time divisions, not runtime dividers on the pixel path.
    reg [31:0] x_map [0:IMAGE_WIDTH-1];
    reg [31:0] y_map [0:IMAGE_HEIGHT-1];
    integer init_i;
    initial begin
        for (init_i=0; init_i<GRID_WIDTH*GRID_HEIGHT; init_i=init_i+1)
            gains[init_i] = SOFT_PRESET ? soft_preset_gain(init_i) : 36'h100100100;
        if (GAIN_FILE != "") $readmemh(GAIN_FILE, gains);
        for (init_i=0; init_i<IMAGE_WIDTH; init_i=init_i+1)
            x_map[init_i] = (init_i*((GRID_WIDTH-1)*256))/(IMAGE_WIDTH-1);
        for (init_i=0; init_i<IMAGE_HEIGHT; init_i=init_i+1)
            y_map[init_i] = (init_i*((GRID_HEIGHT-1)*256))/(IMAGE_HEIGHT-1);
    end
    reg [15:0] x, y;
    // USER accompanies the first valid pixel. Width counting tolerates DE gaps.
    wire [15:0] px = I_user ? 16'd0 : x;
    wire [15:0] py = I_user ? 16'd0 : y;
    reg [31:0] ux, uy;
    wire [15:0] nx = (ux[31:8] >= GRID_WIDTH-1) ? GRID_WIDTH-2 : ux[23:8];
    wire [15:0] ny = (uy[31:8] >= GRID_HEIGHT-1) ? GRID_HEIGHT-2 : uy[23:8];
    wire [8:0] fx = (ux[31:8] >= GRID_WIDTH-1) ? 9'd256 : {1'b0,ux[7:0]};
    wire [8:0] fy = (uy[31:8] >= GRID_HEIGHT-1) ? 9'd256 : {1'b0,uy[7:0]};
    wire [31:0] addr = ny*GRID_WIDTH + nx;
    reg [35:0] g00, g10, g01, g11;
    reg [8:0] fx0, fy0, fy1;
    reg [23:0] rgb_map, rgb0, rgb1, rgb2;
    reg [4:0] ctrl [0:5];
    reg [3:0] apply_pipe;
    reg [11:0] top_gain [0:2], bottom_gain [0:2], gain2 [0:2];
    reg [19:0] product [0:2];
    reg [23:0] result;
    integer c, s;
    // Residual chroma fitted from the two supplied output white-paper frames.
    // Composed with the LUT already applied to those frames; AWB remains active.
    function [35:0] soft_preset_gain;
        input integer index;
        begin case(index)
            0: soft_preset_gain=36'h0f41080fc;
            1: soft_preset_gain=36'h0f61060ff;
            2: soft_preset_gain=36'h0f91040ff;
            3: soft_preset_gain=36'h0fd101100;
            4: soft_preset_gain=36'h1030fd101;
            5: soft_preset_gain=36'h10a0fa103;
            6: soft_preset_gain=36'h1110f7105;
            7: soft_preset_gain=36'h1150f5106;
            8: soft_preset_gain=36'h1190f3106;
            9: soft_preset_gain=36'h1190f3105;
            10: soft_preset_gain=36'h1180f4104;
            11: soft_preset_gain=36'h1140f6103;
            12: soft_preset_gain=36'h1100f8102;
            13: soft_preset_gain=36'h10c0fa100;
            14: soft_preset_gain=36'h10a0fb100;
            15: soft_preset_gain=36'h10b0fb102;
            16: soft_preset_gain=36'h0e61110f8;
            17: soft_preset_gain=36'h0e810f0fc;
            18: soft_preset_gain=36'h0ec10c0ff;
            19: soft_preset_gain=36'h0f4107101;
            20: soft_preset_gain=36'h0fc102103;
            21: soft_preset_gain=36'h1050fd106;
            22: soft_preset_gain=36'h10d0f8108;
            23: soft_preset_gain=36'h1140f510a;
            24: soft_preset_gain=36'h1170f410a;
            25: soft_preset_gain=36'h1180f3109;
            26: soft_preset_gain=36'h1140f5108;
            27: soft_preset_gain=36'h10f0f7106;
            28: soft_preset_gain=36'h1090fb104;
            29: soft_preset_gain=36'h1040fe101;
            30: soft_preset_gain=36'h0ff1000ff;
            31: soft_preset_gain=36'h0ff1010fd;
            32: soft_preset_gain=36'h0e11140f7;
            33: soft_preset_gain=36'h0e31110fb;
            34: soft_preset_gain=36'h0ea10c0ff;
            35: soft_preset_gain=36'h0f3107102;
            36: soft_preset_gain=36'h0fe101105;
            37: soft_preset_gain=36'h1090fa108;
            38: soft_preset_gain=36'h1140f410b;
            39: soft_preset_gain=36'h11d0f110d;
            40: soft_preset_gain=36'h1210ef10d;
            41: soft_preset_gain=36'h1210ef10c;
            42: soft_preset_gain=36'h11d0f110a;
            43: soft_preset_gain=36'h1160f4107;
            44: soft_preset_gain=36'h10d0f8104;
            45: soft_preset_gain=36'h1040fe101;
            46: soft_preset_gain=36'h0ff1010ff;
            47: soft_preset_gain=36'h0fc1030fb;
            48: soft_preset_gain=36'h0df1160f6;
            49: soft_preset_gain=36'h0e11130fb;
            50: soft_preset_gain=36'h0e910e0fe;
            51: soft_preset_gain=36'h0f2106103;
            52: soft_preset_gain=36'h1000ff106;
            53: soft_preset_gain=36'h10d0f810a;
            54: soft_preset_gain=36'h11a0f210d;
            55: soft_preset_gain=36'h1240ee10e;
            56: soft_preset_gain=36'h12a0eb10e;
            57: soft_preset_gain=36'h12a0eb10c;
            58: soft_preset_gain=36'h1250ee10b;
            59: soft_preset_gain=36'h11c0f2107;
            60: soft_preset_gain=36'h1100f7104;
            61: soft_preset_gain=36'h1060fd101;
            62: soft_preset_gain=36'h0fd1020fe;
            63: soft_preset_gain=36'h0f91050fa;
            64: soft_preset_gain=36'h0dc1190f4;
            65: soft_preset_gain=36'h0df1150fa;
            66: soft_preset_gain=36'h0e710f0fe;
            67: soft_preset_gain=36'h0f1108102;
            68: soft_preset_gain=36'h0fe0ff107;
            69: soft_preset_gain=36'h10c0f810b;
            70: soft_preset_gain=36'h11a0f210e;
            71: soft_preset_gain=36'h1250ed10f;
            72: soft_preset_gain=36'h12c0eb10e;
            73: soft_preset_gain=36'h12c0eb10d;
            74: soft_preset_gain=36'h1260ee10a;
            75: soft_preset_gain=36'h11c0f2107;
            76: soft_preset_gain=36'h1100f8103;
            77: soft_preset_gain=36'h1040fe101;
            78: soft_preset_gain=36'h0fb1030fd;
            79: soft_preset_gain=36'h0f61060f9;
            80: soft_preset_gain=36'h0db1190f3;
            81: soft_preset_gain=36'h0dd1170f9;
            82: soft_preset_gain=36'h0e41110ff;
            83: soft_preset_gain=36'h0ef109103;
            84: soft_preset_gain=36'h0fb101107;
            85: soft_preset_gain=36'h1090f910b;
            86: soft_preset_gain=36'h1160f310e;
            87: soft_preset_gain=36'h1200ef10f;
            88: soft_preset_gain=36'h1260ec10f;
            89: soft_preset_gain=36'h1270ed10d;
            90: soft_preset_gain=36'h1210ef10a;
            91: soft_preset_gain=36'h1180f3107;
            92: soft_preset_gain=36'h10d0f9104;
            93: soft_preset_gain=36'h1020ff100;
            94: soft_preset_gain=36'h0f91040fd;
            95: soft_preset_gain=36'h0f51080f9;
            96: soft_preset_gain=36'h0db11a0f4;
            97: soft_preset_gain=36'h0dd1160f9;
            98: soft_preset_gain=36'h0e31110fe;
            99: soft_preset_gain=36'h0ec10b103;
            100: soft_preset_gain=36'h0f7104108;
            101: soft_preset_gain=36'h1020fc10c;
            102: soft_preset_gain=36'h10d0f710f;
            103: soft_preset_gain=36'h1160f310f;
            104: soft_preset_gain=36'h11c0f110f;
            105: soft_preset_gain=36'h11d0f110e;
            106: soft_preset_gain=36'h1180f310b;
            107: soft_preset_gain=36'h1100f6108;
            108: soft_preset_gain=36'h1060fb105;
            109: soft_preset_gain=36'h0fd101102;
            110: soft_preset_gain=36'h0f71050fe;
            111: soft_preset_gain=36'h0f41070f8;
            112: soft_preset_gain=36'h0da11a0f6;
            113: soft_preset_gain=36'h0dd1170fa;
            114: soft_preset_gain=36'h0e21130fd;
            115: soft_preset_gain=36'h0e810d102;
            116: soft_preset_gain=36'h0f1107106;
            117: soft_preset_gain=36'h0fb10110a;
            118: soft_preset_gain=36'h1030fc10d;
            119: soft_preset_gain=36'h10a0f910e;
            120: soft_preset_gain=36'h10f0f710e;
            121: soft_preset_gain=36'h10f0f710d;
            122: soft_preset_gain=36'h10c0f810b;
            123: soft_preset_gain=36'h1060fc108;
            124: soft_preset_gain=36'h1000ff105;
            125: soft_preset_gain=36'h0fa103101;
            126: soft_preset_gain=36'h0f71050fd;
            127: soft_preset_gain=36'h0f81060f5;
            128: soft_preset_gain=36'h0d91190fb;
            129: soft_preset_gain=36'h0dd1160fb;
            130: soft_preset_gain=36'h0e21130fb;
            131: soft_preset_gain=36'h0e710e0fe;
            132: soft_preset_gain=36'h0ee10a101;
            133: soft_preset_gain=36'h0f6105105;
            134: soft_preset_gain=36'h0fc101107;
            135: soft_preset_gain=36'h1010fe109;
            136: soft_preset_gain=36'h1040fc10a;
            137: soft_preset_gain=36'h1040fc108;
            138: soft_preset_gain=36'h1020fe107;
            139: soft_preset_gain=36'h1000fe105;
            140: soft_preset_gain=36'h0fd101101;
            141: soft_preset_gain=36'h0fb1030fc;
            142: soft_preset_gain=36'h0fc1040f6;
            143: soft_preset_gain=36'h1031040eb;
            default:soft_preset_gain=36'h100100100;
        endcase end
    endfunction
    function [11:0] lerp;
        input [11:0] a,b;
        input [8:0] weight;
        reg signed [12:0] delta;
        reg signed [22:0] mixed;
        begin
            delta = $signed({1'b0,b}) - $signed({1'b0,a});
            mixed = $signed({1'b0,a,8'b0}) + delta*$signed({1'b0,weight}) + 23'sd128;
            lerp = mixed >>> 8;
        end
    endfunction
    function [7:0] subtract_black;
        input [7:0] value;
        begin subtract_black = (value > BLACK_LEVEL) ? value-BLACK_LEVEL : 0; end
    endfunction
    function [7:0] saturate;
        input [19:0] value;
        reg [20:0] rounded;
        begin
            rounded = {1'b0,value}+21'd128;
            saturate = (rounded > 21'd65407) ? 8'd255 : rounded[15:8];
        end
    endfunction
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            x<=0; y<=0; g00<=0; g10<=0; g01<=0; g11<=0;
            ux<=0; uy<=0; rgb_map<=0;
            apply_pipe<=0;
            fx0<=0; fy0<=0; fy1<=0; rgb0<=0; rgb1<=0; rgb2<=0; result<=0;
            for (s=0;s<6;s=s+1) ctrl[s]<=0;
            for (c=0;c<3;c=c+1) begin
                top_gain[c]<=0; bottom_gain[c]<=0; gain2[c]<=0; product[c]<=0;
            end
        end else begin
            if (I_user) begin x<=0; y<=0; end
            if (I_de) begin
                if (px == IMAGE_WIDTH-1) begin
                    x<=0; y <= (py == IMAGE_HEIGHT-1) ? 0 : py+1'b1;
                end else begin x<=px+1'b1; y<=py; end
            end
            ctrl[0] <= {I_vsync,I_hsync,I_de,I_user,I_last};
            apply_pipe <= {apply_pipe[2:0],I_correction_enable};
            for (s=1;s<6;s=s+1) ctrl[s]<=ctrl[s-1];
            ux<=x_map[px]; uy<=y_map[py]; rgb_map<=I_rgb;
            g00<=gains[addr]; g10<=gains[addr+1];
            g01<=gains[addr+GRID_WIDTH]; g11<=gains[addr+GRID_WIDTH+1];
            fx0<=fx; fy0<=fy; fy1<=fy0;
            rgb0<=rgb_map; rgb1<=rgb0; rgb2<=rgb1;
            for (c=0;c<3;c=c+1) begin
                top_gain[c]<=lerp(g00[c*12+:12],g10[c*12+:12],fx0);
                bottom_gain[c]<=lerp(g01[c*12+:12],g11[c*12+:12],fx0);
                gain2[c]<=lerp(top_gain[c],bottom_gain[c],fy1);
                product[c]<=(RUNTIME_GAINS && !apply_pipe[3]) ?
                    {4'd0,rgb2[c*8+:8],8'd0} : subtract_black(rgb2[c*8+:8])*gain2[c];
                result[c*8+:8]<=ctrl[4][2] ? saturate(product[c]) : 8'd0;
            end
        end
    end
    assign {O_vsync,O_hsync,O_de,O_user,O_last}=ctrl[5];
    assign O_rgb=result;
endmodule

// On-board white-board calibration. Explicit request only: never learn a normal scene.
// Average an 8x8 patch at every endpoint node for 16 complete frames (1024 samples/node).
// Shared bit-serial divider runs only after capture. No live pixel division.
module hx_white_field_calibrator #(
    parameter IMAGE_WIDTH=1280, IMAGE_HEIGHT=720,
    parameter GRID_WIDTH=16, GRID_HEIGHT=9,
    parameter PATCH_SIZE=8, CAPTURE_FRAMES=16, SETTLE_FRAMES=8,
    parameter BLACK_LEVEL=0, TARGET=160
) (
    input wire I_clk,I_rst_n,I_de,I_user,I_request,I_invalidate,
    input wire [23:0] I_rgb,
    output reg O_busy,O_valid,O_error,O_gain_we,
    output reg [7:0] O_gain_addr,
    output reg [35:0] O_gain_data
);
    localparam NODES=GRID_WIDTH*GRID_HEIGHT;
    localparam SAMPLE_SHIFT=$clog2(CAPTURE_FRAMES*PATCH_SIZE*PATCH_SIZE);
    localparam SUM_BITS=8+SAMPLE_SHIFT;
    localparam CLIP_LIMIT=(NODES*CAPTURE_FRAMES*PATCH_SIZE*PATCH_SIZE)/1000;
    localparam IDLE=0,CLEAR=1,SETTLE=2,CAPTURE=3,READ_MEANS=4,
               DIV_START=5,DIV_RUN=6,DIV_STORE=7,WRITE_GAIN=8,COMMIT=9,MEAN_READ=10;
    reg [3:0] state;
    reg [15:0] x,y;
    wire [15:0] px=I_user ? 16'd0 : x;
    wire [15:0] py=I_user ? 16'd0 : y;
    wire frame_start=I_de && I_user;
    wire frame_end=I_de && px==IMAGE_WIDTH-1 && py==IMAGE_HEIGHT-1;
    reg [8:0] x_node[0:IMAGE_WIDTH-1];
    reg [7:0] y_node[0:IMAGE_HEIGHT-1];
    integer init_n,init_k,patch_start;
    initial begin
        for(init_n=0;init_n<IMAGE_WIDTH;init_n=init_n+1)x_node[init_n]=8'hff;
        for(init_n=0;init_n<IMAGE_HEIGHT;init_n=init_n+1)y_node[init_n]=8'hff;
        for(init_n=0;init_n<GRID_WIDTH;init_n=init_n+1) begin
            patch_start=(init_n*(IMAGE_WIDTH-1)+(GRID_WIDTH-1)/2)/(GRID_WIDTH-1)-PATCH_SIZE/2;
            if(patch_start<0)patch_start=0;
            if(patch_start>IMAGE_WIDTH-PATCH_SIZE)patch_start=IMAGE_WIDTH-PATCH_SIZE;
            for(init_k=0;init_k<PATCH_SIZE;init_k=init_k+1)begin
                x_node[patch_start+init_k]=init_n;
                if(init_k==PATCH_SIZE-1)x_node[patch_start+init_k][8]=1'b1;
            end
        end
        for(init_n=0;init_n<GRID_HEIGHT;init_n=init_n+1) begin
            patch_start=(init_n*(IMAGE_HEIGHT-1)+(GRID_HEIGHT-1)/2)/(GRID_HEIGHT-1)-PATCH_SIZE/2;
            if(patch_start<0)patch_start=0;
            if(patch_start>IMAGE_HEIGHT-PATCH_SIZE)patch_start=IMAGE_HEIGHT-PATCH_SIZE;
            for(init_k=0;init_k<PATCH_SIZE;init_k=init_k+1)y_node[patch_start+init_k]=init_n;
        end
    end
    wire [8:0] x_sample=x_node[px];
    wire [7:0] sample_col=x_sample[7:0],sample_row=y_node[py];
    wire sample_last=x_sample[8];
    wire sample_hit=I_de && sample_col!=8'hff && sample_row!=8'hff;
    wire [7:0] sample_addr=sample_row*GRID_WIDTH+sample_col;
    reg [SUM_BITS*3-1:0] sums[0:NODES-1];
    reg [7:0] node_index,settled_frames,captured_frames;
    // Sum each horizontal patch in registers. Synchronous RAM is touched only
    // once per patch row; neighboring accesses are many clocks apart.
    localparam ROW_BITS=8+$clog2(PATCH_SIZE);
    reg [ROW_BITS-1:0] row_r,row_g,row_b;
    reg pending_valid;
    reg [7:0] pending_addr;
    reg [SUM_BITS-1:0] pending_r,pending_g,pending_b;
    reg [SUM_BITS*3-1:0] sum_rd;
    wire [7:0] sum_rd_addr=(state==CAPTURE && sample_hit && sample_last)?sample_addr:node_index;
    wire [SUM_BITS-1:0] updated_r=sum_rd[2*SUM_BITS+:SUM_BITS]+pending_r;
    wire [SUM_BITS-1:0] updated_g=sum_rd[SUM_BITS+:SUM_BITS]+pending_g;
    wire [SUM_BITS-1:0] updated_b=sum_rd[0+:SUM_BITS]+pending_b;
    always @(posedge I_clk)begin
        sum_rd<=sums[sum_rd_addr];
        if(state==CLEAR)sums[node_index]<=0;
        else if(pending_valid)sums[pending_addr]<={updated_r,updated_g,updated_b};
    end
    reg [19:0] clipped_samples;
    wire [7:0] mean_r=(sum_rd[2*SUM_BITS+:SUM_BITS]+(1 << (SAMPLE_SHIFT-1))) >> SAMPLE_SHIFT;
    wire [7:0] mean_g=(sum_rd[SUM_BITS+:SUM_BITS]+(1 << (SAMPLE_SHIFT-1))) >> SAMPLE_SHIFT;
    wire [7:0] mean_b=(sum_rd[0+:SUM_BITS]+(1 << (SAMPLE_SHIFT-1))) >> SAMPLE_SHIFT;
    reg [7:0] denominator[0:2];
    reg [1:0] channel;
    reg [15:0] numerator,quotient;
    reg [8:0] remainder;
    reg [4:0] div_bits;
    wire [8:0] trial={remainder[7:0],numerator[15]};
    wire div_one=trial >= {1'b0,denominator[channel]};
    reg [11:0] r_gain,g_gain,b_gain;
    function [7:0] signal_value;
        input [7:0] value;
        begin signal_value=(value>BLACK_LEVEL) ? value-BLACK_LEVEL : 0;end
    endfunction
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)begin
            x<=0;y<=0;state<=IDLE;O_busy<=0;O_valid<=0;O_error<=0;
            O_gain_we<=0;O_gain_addr<=0;O_gain_data<=0;
            node_index<=0;settled_frames<=0;captured_frames<=0;clipped_samples<=0;
            channel<=0;denominator[0]<=0;denominator[1]<=0;denominator[2]<=0;
            numerator<=0;quotient<=0;remainder<=0;div_bits<=0;
            r_gain<=0;g_gain<=0;b_gain<=0;
            row_r<=0;row_g<=0;row_b<=0;pending_valid<=0;pending_addr<=0;
            pending_r<=0;pending_g<=0;pending_b<=0;
        end else begin
            O_gain_we<=0;
            pending_valid<=0;
            if(I_user)begin x<=0;y<=0;end
            if(I_de)begin
                if(px==IMAGE_WIDTH-1)begin x<=0;y<=(py==IMAGE_HEIGHT-1)?0:py+1'b1;end
                else begin x<=px+1'b1;y<=py;end
            end
            if(I_invalidate)begin
                state<=IDLE;O_busy<=0;O_valid<=0;O_error<=0;
            end else if(I_request && !O_busy)begin
                state<=CLEAR;node_index<=0;settled_frames<=0;captured_frames<=0;
                O_busy<=1;O_valid<=0;O_error<=0;clipped_samples<=0;
                row_r<=0;row_g<=0;row_b<=0;
            end else case(state)
                IDLE: begin end
                CLEAR: begin
                    if(node_index==NODES-1)begin node_index<=0;state<=SETTLE;end
                    else node_index<=node_index+1'b1;
                end
                SETTLE: begin
                    if(frame_start && settled_frames<SETTLE_FRAMES)settled_frames<=settled_frames+1'b1;
                    if(frame_end && settled_frames>=SETTLE_FRAMES)state<=CAPTURE;
                end
                CAPTURE: begin
                    if(sample_hit)begin
                        if(sample_last)begin
                            pending_valid<=1;pending_addr<=sample_addr;
                            pending_r<=row_r+signal_value(I_rgb[23:16]);
                            pending_g<=row_g+signal_value(I_rgb[15:8]);
                            pending_b<=row_b+signal_value(I_rgb[7:0]);
                            row_r<=0;row_g<=0;row_b<=0;
                        end else begin
                            row_r<=row_r+signal_value(I_rgb[23:16]);
                            row_g<=row_g+signal_value(I_rgb[15:8]);
                            row_b<=row_b+signal_value(I_rgb[7:0]);
                        end
                        if(I_rgb[23:16]>=250 || I_rgb[15:8]>=250 || I_rgb[7:0]>=250)
                            clipped_samples<=clipped_samples+1'b1;
                    end
                    if(frame_end)begin
                        if(captured_frames==CAPTURE_FRAMES-1)begin node_index<=0;state<=MEAN_READ;end
                        else captured_frames<=captured_frames+1'b1;
                    end
                end
                MEAN_READ:state<=READ_MEANS;
                READ_MEANS: begin
                    // Reject unusable captures; never silently install extreme/invalid gains.
                    if(mean_r<40 || mean_g<40 || mean_b<40 ||
                       mean_r>235 || mean_g>235 || mean_b>235 || clipped_samples>CLIP_LIMIT)begin
                        O_error<=1;O_valid<=0;O_busy<=0;state<=IDLE;
                    end else begin
                        denominator[0]<=mean_r;denominator[1]<=mean_g;denominator[2]<=mean_b;
                        channel<=0;state<=DIV_START;
                    end
                end
                DIV_START: begin
                    numerator<=TARGET*256+({8'd0,denominator[channel]} >> 1);
                    quotient<=0;remainder<=0;div_bits<=16;state<=DIV_RUN;
                end
                DIV_RUN: begin
                    numerator<={numerator[14:0],1'b0};
                    quotient<={quotient[14:0],div_one};
                    remainder<=div_one ? trial-{1'b0,denominator[channel]} : trial;
                    if(div_bits==1)state<=DIV_STORE;
                    else div_bits<=div_bits-1'b1;
                end
                DIV_STORE: begin
                    case(channel)0:r_gain<=quotient[11:0];1:g_gain<=quotient[11:0];2:b_gain<=quotient[11:0];endcase
                    if(channel==2)state<=WRITE_GAIN;
                    else begin channel<=channel+1'b1;state<=DIV_START;end
                end
                WRITE_GAIN: begin
                    O_gain_we<=1;O_gain_addr<=node_index;O_gain_data<={r_gain,g_gain,b_gain};
                    if(node_index==NODES-1)state<=COMMIT;
                    else begin node_index<=node_index+1'b1;state<=MEAN_READ;end
                end
                COMMIT: if(frame_end)begin O_valid<=1;O_busy<=0;state<=IDLE;end
                default:state<=IDLE;
            endcase
        end
    end
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
