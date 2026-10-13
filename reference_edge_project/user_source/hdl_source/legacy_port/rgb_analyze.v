`timescale 1ns / 1ps

`define CDC_MULTI_BIT_SIGNAL_OUTGEN(aclk,adata_in,bclk,bdata_out,DATA_WIDTH)                            generate begin xpm_cdc_array_single #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(0),.SIM_ASSERT_CHK(0),.SRC_INPUT_REG(1),.WIDTH(DATA_WIDTH)) cdc_u(.src_clk(aclk),.src_in(adata_in),.dest_clk(bclk),.dest_out(bdata_out));    end  endgenerate  
`define CDC_SINGLE_BIT_PULSE_OUTGEN(aclk,arst,apulse_in,bclk,brst,bpulse_out,SIM)                       generate if(SIM==0)begin  xpm_cdc_pulse #(.DEST_SYNC_FF(4), .INIT_SYNC_FF(0),.REG_OUTPUT(0),.RST_USED(1),.SIM_ASSERT_CHK (0)) cdc_u (.src_clk(aclk),.src_rst(arst),.src_pulse(apulse_in),.dest_clk(bclk),.dest_rst(brst),.dest_pulse(bpulse_out));   end else begin   reg [5:0] name1 = 0;wire name2;always@(posedge aclk)if(arst)name1[0] <=0;else name1[0] <= apulse_in;assign name2 = apulse_in & ~name1[0]; always@(posedge aclk)if(arst)name1[1] <= 0;else name1[1] <= name2 ? ~name1[1]:name1[1];always@(posedge bclk)if(brst)name1[5:2]<=0;else begin name1[2]<=name1[1];name1[3]<=name1[2];name1[4]<=name1[3];name1[5]<=name1[4];end  assign bpulse_out=name1[4]^name1[5];  end  endgenerate
`define POS_MONITOR_OUTGEN(clk,rst,in,out)                                                              generate  begin  reg buf_name1 = 0; always@(posedge clk)begin if(rst)buf_name1 <= 0; else  buf_name1 <= in; end assign out = (~buf_name1)&(in);  end  endgenerate
`define NEG_MONITOR_OUTGEN(clk,rst,in,out)                                                              generate  begin  reg buf_name1 = 0; always@(posedge clk)begin if(rst)buf_name1 <= 0; else  buf_name1 <= in; end assign out = (buf_name1)&(~in);  end  endgenerate
`define DELAY_OUTGEN(clk,rst,data_in,data_out,DATA_WIDTH,DLY)                                           generate if(DLY==0)begin  assign data_out = data_in; end  else if(DLY==1)begin  reg [DATA_WIDTH-1:0] a_temp = 0; always@(posedge clk) a_temp <= data_in; assign data_out = a_temp ; end  else begin  reg [DATA_WIDTH-1:0] a_temp [DLY-1:0] ;always@(posedge clk) begin  if(rst)a_temp[DLY-1] <= 0; else   a_temp[DLY-1] <= data_in; end  for(i=0;i<=DLY-2;i=i+1)begin  always@(posedge clk)begin  if(rst)begin  a_temp[i] <= 0; end  else begin  a_temp[i] <= a_temp[i+1]; end  end  end  assign data_out = a_temp[0]; end  endgenerate

//注意：信号输入解析时不打拍，如果需要优化时序，请在模块外部打拍
//基础参数写入ram 和 crc写入fifo 互相独立，不会有干扰

/*
rgb_analyze #( 
    .MAX_PORT_NUM       (4 ),
    .MAX_BPC            (8 ),//6 8 10 12 
    .RAM_UPDATE_REG_NUM (32),
    .C_CRC_BLOCK_EN       (1),
    .INPUT_REG_NUM      (0)
    )
    rgb_analyze_u(      
    .CLK_I      (),
    .RST_I      (),   
    .TIMER_I    (), //check pos inside
    .PORT_NUM_I (), //1 2 4 8 , other will transfer to  4        
    .BPC_I      (),
    .RH_I       (),
    .RL_I       (),
    .GH_I       (),
    .GL_I       (),
    .BH_I       (),
    .BL_I       (),
    .DE_I       (),
    .HS_I       (),
    .VS_I       (), //risk :when 1st VS , timing para is not ready
    .R_I        (),
    .G_I        (),
    .B_I        (),  
    .RAM_DATA_O (),
    .RAM_ADDR_O (),//addr = 0 , 1, 2 , ...
    .RAM_WR_O   (),
    .FIFO_CRC_O (),
    .FIFO_CRC_WR_O  () ,
    
    .EXCLUDE_PT_NUM_I ()
    
    );

*/

//MAX_BPC==8 , MAX_PORT_NUM==4 , CRC take about 200LUT , FPS_SERIES R G B .. take 200LUT 100FF
//resource(with CRC en)  : MAX_BPC==6 , MAX_PORT_NUM==4 -> LUT:502  FF:447 
//resource(with CRC en)  : MAX_BPC==8 , MAX_PORT_NUM==4 -> LUT:640  FF:489  -> add FPS_SERIES LUT:801 FF:639
//resource(with CRC en)  : MAX_BPC==10, MAX_PORT_NUM==4 -> LUT:819  FF:531 
//resource(with CRC en)  : MAX_BPC==12, MAX_PORT_NUM==4 -> LUT:970  FF:569 

//对于标准tpg输入，支持解析连续或者不连续的DE输入(已仿真)
//
//不标准TPG
//VS _|————————————————|____________________________|————————————————|
//HS ___________________________|—|______|—|_________________________
//DE _____________________|————|___|————|___|————|___________________

//在以上模式下，除了vactive(可能需要加1)和hactive外，所有时序参数都没有参考价值

//纯色画面检测的 CNT模式 在功能上 涵盖了 FLAG模式
//CNT模式下又分为 所排除的比例模式(只支持2的幂次方分之1) 和 所排除的点数模式(精确)
//                意思是多大比例以下非纯时，仍然认为其为纯色 
//                      多大数量的点数为非纯时，仍然认为其为纯色

//目前按比例模式，感觉有点麻烦，暂时未进行
//注意：直接上来的第一个vs，检测结果不准，因为此时各flag值都没有任何变化； 需要第二个vs后的结果才是准的
//注意：FPS每个timer来后，其计数变量都会清零，然后重新依据vs开始累加
//      例如·，如果两次timer之间，连一个vs都没有，那么统计结果就是全0


module rgb_analyze #( 
    parameter MAX_PORT_NUM           = 4  ,//1 2 4 8
    parameter MAX_BPC                = 8  ,//6 8 10 12; if give wrong parameter, the result is not predictable
    parameter [0:0] C_CRC_BLOCK_EN     = 0  ,  
     parameter [0:0] C_HEIGHT_BLOCK_EN         = 0  ,  
    parameter [0:0] C_ERR_COUNT_BLOCK_EN     = 0  ,  
    
    
    parameter RAM_UPDATE_REG_NUM     = 20 , //must >= 1
    parameter INPUT_REG_NUM          = 0  ,   //>= 0
    parameter [1:0] PURE_CHECK_MODE  = 0  ,   //0: FLAG模式 1:CNT point num 模式  
    
	parameter [15:0] ADDR_LOCKED     = 16'h0000 ,
	parameter [15:0] ADDR_HSYNC      = 16'h0004 ,
	parameter [15:0] ADDR_HBP        = 16'h0008 ,
	parameter [15:0] ADDR_HACTIVE    = 16'h000c ,
	parameter [15:0] ADDR_HFP        = 16'h0010 ,
	parameter [15:0] ADDR_VSYNC      = 16'h0014 ,
	parameter [15:0] ADDR_VBP        = 16'h0018 ,
	parameter [15:0] ADDR_VACTIVE    = 16'h001c ,
	parameter [15:0] ADDR_VFP        = 16'h0020 ,
	parameter [15:0] ADDR_FPS_C1     = 16'h0024 ,
	parameter [15:0] ADDR_FPS_C1_M1  = 16'h0028 ,
	parameter [15:0] ADDR_FPS_C1_M2  = 16'h002C ,
	parameter [15:0] ADDR_FPS_C1_M3  = 16'h0030 ,
	parameter [15:0] ADDR_FPS_C1_M4  = 16'h0034 ,
	parameter [15:0] ADDR_FPS_C1_M5  = 16'h0038 ,
	parameter [15:0] ADDR_FPS_C1_M6  = 16'h003c ,
	parameter [15:0] ADDR_FPS_C1_M7  = 16'h0040 ,
	parameter [15:0] ADDR_FPS_C1_M8  = 16'h0044 ,
	parameter [15:0] ADDR_FPS_C1_M9  = 16'h0048 ,
	parameter [15:0] ADDR_FPS_C1_M10 = 16'h004c ,
	parameter [15:0] ADDR_FPS_C2     = 16'h0050 ,
	parameter [15:0] ADDR_FPS_C2_M1  = 16'h0054 ,
	parameter [15:0] ADDR_FPS_C2_M2  = 16'h0058 ,
	parameter [15:0] ADDR_FPS_C2_M3  = 16'h005c ,
	parameter [15:0] ADDR_FPS_C2_M4  = 16'h0060 ,
	parameter [15:0] ADDR_FPS_C2_M5  = 16'h0064 ,
	parameter [15:0] ADDR_FPS_C2_M6  = 16'h0068 ,
	parameter [15:0] ADDR_FPS_C2_M7  = 16'h006c ,
	parameter [15:0] ADDR_FPS_C2_M8  = 16'h0070 ,
	parameter [15:0] ADDR_FPS_C2_M9  = 16'h0074 ,
	parameter [15:0] ADDR_FPS_C2_M10 = 16'h0078 ,
    
    
    parameter C_CAITIAO_SLOT  =  360  ,//512 
    parameter C_PORT_TYPE     =  "EDP1"  ,
    
    parameter  [0:0] C_ILA_ERR_COUNT_PCLK = 1 ,
    
    
    localparam  SLOT_EDP1_NUM  =  512 ,  //不考虑port的像素点数
    localparam  SLOT_LVDS0_NUM =  171 ,  // 
    localparam  SLOT_LVDS1_NUM =  103 

    
)(      
input                             CLK_I      ,
input                             RST_I      ,   
input                             TIMER_I    , //check pos inside

input  [3:0]                      PORT_NUM_I , //1 2 4 8 , other will be changed to  4 ; 配置不同的port_num, 在计算crc时加法的次数不同 
input  [3:0]                      BPC_I , //配置不同的bpc,像素中截取r g b的位宽不同; 会忽略输入端超出的位宽(强制赋0) 


input  [MAX_BPC-1:0]              RH_I,
input  [MAX_BPC-1:0]              RL_I,
input  [MAX_BPC-1:0]              GH_I,
input  [MAX_BPC-1:0]              GL_I,
input  [MAX_BPC-1:0]              BH_I,
input  [MAX_BPC-1:0]              BL_I,


input                             DE_I ,
input                             HS_I ,
input                             VS_I , 
input  [MAX_PORT_NUM*MAX_BPC-1:0] R_I  ,
input  [MAX_PORT_NUM*MAX_BPC-1:0] G_I  ,
input  [MAX_PORT_NUM*MAX_BPC-1:0] B_I  ,  
input  [31:0] TARGET_CRC_DATA_I  ,   
input  [31:0] TARGET_ERR_COUNT_I , 
output  reg  [31:0]  RAM_DATA_O = 0 ,//if no valid signal, RAM_DATA_O will be 0;  H para will multiply PORT_NUM_I
output  reg  [15:0]  RAM_ADDR_O = 0 ,//addr = 0 , 1, 2 , ...
output  reg          RAM_WR_O   = 0 ,//RAM_WR_O will certainly be 1 , if timer comes
                                    //note: the same BPC_I but different MAX_BPC will result in different CRC restult

//写crc参数和写 时序参数是 独立的
output  [31:0]       FIFO_CRC_O  ,  //always be 0 when C_CRC_BLOCK_EN==0 ; CRC calc will always use crc_module of MAX_BPC*3                     
output               FIFO_CRC_WR_O   ,   //always be 0 when C_CRC_BLOCK_EN==0


output  [31:0]       FIFO_HEIGHT_O        ,
output               FIFO_HEIGHT_WR_O     ,

output  [31:0]       FIFO_ERR_COUNT_O     ,
output               FIFO_ERR_COUNT_WR_O  ,

//auxilary signal 
output  reg          PARA_VALID_O   = 0 ,  //~ timer ; at the same time, is writted into ram

//已经根据纯色过滤模式，进行

output  SIGNAL_RED_O   ,  //  signal_red_cntmode   
output  SIGNAL_GREEN_O ,  //  signal_green_cntmode 
output  SIGNAL_BLUE_O  ,  //  signal_blue_cntmode  
output  SIGNAL_WHITE_O ,  //  signal_white_cntmode 
output  SIGNAL_BLACK_O ,  //  signal_black_cntmode 
output  reg CRC_ERR_FLAG_O   = 0 ,
output  reg ERR_COUNT_FLAG_O = 0 ,
output  reg HEIGHT_ERR_FLAG_O = 0 ,

input   [23:0]       EXCLUDE_PT_NUM_I ,


input [15:0] CRC_EXCLUVE_X  ,
input [15:0] CRC_EXCLUVE_Y  ,
input [15:0] CRC_EXCLUVE_H  ,
input [15:0] CRC_EXCLUVE_V  ,

input [31:0] TARGET_HEIGHT_H_I     ,
input [31:0] TARGET_HEIGHT_L_I   




);



wire  [31:0] RAM_ADDR_AXI;
assign RAM_ADDR_AXI = RAM_ADDR_O * 4;

genvar i,j,k;


reg  signal_red_cntmode    = 0;
reg  signal_green_cntmode  = 0;
reg  signal_blue_cntmode   = 0;
reg  signal_white_cntmode  = 0;
reg  signal_black_cntmode  = 0;


reg          SIGNAL_RED_flagmode   = 0 ;
reg          SIGNAL_GREEN_flagmode = 0 ;
reg          SIGNAL_BLUE_flagmode  = 0 ;
reg          SIGNAL_WHITE_flagmode = 0 ;
reg          SIGNAL_BLACK_flagmode = 0 ;



reg ram_updata = 0;
wire VS_I_d_pos_s2;
wire TIMER_I_pos;
wire VS_I_d_pos;
wire VS_I_d_neg;
wire HS_I_d_pos;
wire HS_I_d_neg;
wire DE_I_d_pos; 
wire DE_I_d_neg;
wire [MAX_BPC*3-1:0] pixel_data_s0 [MAX_PORT_NUM-1:0] ;
reg [15:0] HSYNC_count = 0;
reg [15:0] R_HSYNC = 0;//hsync is continuous
reg HBP_valid = 0;
reg [15:0] HBP_count = 0;
reg [15:0] R_HBP = 0;
wire HBP_valid_neg;
reg DE_has = 0;
reg [15:0] HACTIVE_count = 0;
reg [15:0] R_HACTIVE = 0;
reg HFP_valid = 0;
reg [15:0] HFP_count = 0;
reg [15:0] R_HFP = 0;
wire HFP_valid_neg;
wire VSYNC_valid;
reg [15:0] VSYNC_count = 0;
reg [15:0] R_VSYNC = 0;
wire VBP_valid_adv_neg;
reg VBP_valid_adv;
wire VBP_valid;
reg [15:0] VBP_count = 0;
wire [15:0] R_VBP;
reg [15:0] VBP_b = 0;
reg [15:0] R_VACTIVE = 0;
reg [15:0] VACTIVE_count = 0;
wire VACTIVE_valid;
reg VACTIVE_valid_adv = 0;
wire [15:0] R_VFP;
reg [15:0] VTOTAL = 0;
reg [15:0] VTOTAL_count = 0;
reg   [7:0]  R_FPS = 0; 
reg   [7:0]  FPS_count = 0; 
reg   [7:0]  R_FPS_SERIES = 0; //当前timer来临时刻的 连续帧数, 注意不是秒内的最大连续帧
reg   [7:0]  FPS_SERIES_count = 0;
reg [MAX_BPC*3-1:0] crc_last = 0;//根据实际port数不同，累加不同数量的 crc_per_pixel
reg [31:0] crc_reg_l = 0;
reg [31:0] crc_reg_h = 0;
reg [31:0] crc_reg_f = 0;
wire [35:0] crc_per_pixel [MAX_PORT_NUM-1:0]; //note:始终按12位色深定义宽度: 12*3=36
reg [3:0] h_mult;
reg [7:0] R_FPS_RED   = 0;
reg [7:0] R_FPS_GREEN = 0;
reg [7:0] R_FPS_BLUE  = 0;
reg [7:0] R_FPS_WHITE = 0;
reg [7:0] R_FPS_BLACK = 0;
reg [7:0] R_FPS_RED_count     = 0;//每timer来后，清零，然后依据vs重新开始计数
reg [7:0] R_FPS_GREEN_count   = 0;
reg [7:0] R_FPS_BLUE_count    = 0;
reg [7:0] R_FPS_WHITE_count   = 0;
reg [7:0] R_FPS_BLACK_count   = 0;

reg [7:0] R_FPS_RED_cntmode   = 0;
reg [7:0] R_FPS_GREEN_cntmode = 0;
reg [7:0] R_FPS_BLUE_cntmode  = 0;
reg [7:0] R_FPS_WHITE_cntmode = 0;
reg [7:0] R_FPS_BLACK_cntmode = 0;
reg [7:0] R_FPS_RED_count_cntmode     = 0; //每timer来后，清零，然后依据vs重新开始计数
reg [7:0] R_FPS_GREEN_count_cntmode   = 0;
reg [7:0] R_FPS_BLUE_count_cntmode    = 0;
reg [7:0] R_FPS_WHITE_count_cntmode   = 0;
reg [7:0] R_FPS_BLACK_count_cntmode   = 0;



wire [MAX_BPC*3-1:0] crc_3bpc_temp [MAX_PORT_NUM-1:0] ;
reg  [MAX_BPC*3-1:0] pixel_data_af_mask_s0 [MAX_PORT_NUM-1:0];
reg [MAX_PORT_NUM-1:0] r_h_flag_dym = {MAX_PORT_NUM{1'b1}};//calc per CLK_I , 值根据每时钟的输入值变化
reg [MAX_PORT_NUM-1:0] r_l_flag_dym = {MAX_PORT_NUM{1'b1}};
reg [MAX_PORT_NUM-1:0] g_h_flag_dym = {MAX_PORT_NUM{1'b1}};
reg [MAX_PORT_NUM-1:0] g_l_flag_dym = {MAX_PORT_NUM{1'b1}};
reg [MAX_PORT_NUM-1:0] b_h_flag_dym = {MAX_PORT_NUM{1'b1}};
reg [MAX_PORT_NUM-1:0] b_l_flag_dym = {MAX_PORT_NUM{1'b1}};
reg [MAX_PORT_NUM-1:0] r_h_flag_mask_dym;
reg [MAX_PORT_NUM-1:0] r_l_flag_mask_dym;
reg [MAX_PORT_NUM-1:0] g_h_flag_mask_dym;
reg [MAX_PORT_NUM-1:0] g_l_flag_mask_dym;
reg [MAX_PORT_NUM-1:0] b_h_flag_mask_dym;
reg [MAX_PORT_NUM-1:0] b_l_flag_mask_dym;
(*keep="true"*)reg r_h_flag = 1;
(*keep="true"*)reg r_l_flag = 1;
(*keep="true"*)reg g_h_flag = 1;
(*keep="true"*)reg g_l_flag = 1;
(*keep="true"*)reg b_h_flag = 1;
(*keep="true"*)reg b_l_flag = 1;

wire DE_I_d_s1;
reg [31:0]  fps_c1_reg [9:0];
reg [31:0]  fps_c2_reg [9:0];  


initial begin
    fps_c1_reg[0] = 0; 
    fps_c1_reg[1] = 0; 
    fps_c1_reg[2] = 0; 
    fps_c1_reg[3] = 0; 
    fps_c1_reg[4] = 0; 
    fps_c1_reg[5] = 0; 
    fps_c1_reg[6] = 0; 
    fps_c1_reg[7] = 0; 
    fps_c1_reg[8] = 0; 
    fps_c1_reg[9] = 0; 
    
    fps_c2_reg[0] = 0;
    fps_c2_reg[1] = 0;
    fps_c2_reg[2] = 0;
    fps_c2_reg[3] = 0;
    fps_c2_reg[4] = 0;
    fps_c2_reg[5] = 0;
    fps_c2_reg[6] = 0;
    fps_c2_reg[7] = 0;
    fps_c2_reg[8] = 0;
    fps_c2_reg[9] = 0;

end



wire ram_updata_neg;
reg [31:0] crc_reg_f_last = 0;//buffer 
                  
wire                             DE_I_d ;
wire                             HS_I_d ;
wire                             VS_I_d ; 
wire  [4*MAX_BPC-1:0] R_I_d  ;
wire  [4*MAX_BPC-1:0] G_I_d  ;
wire  [4*MAX_BPC-1:0] B_I_d  ;  

//2^24 覆盖4K 点数  
reg [23:0] cnt_red_dym_s1   [MAX_PORT_NUM-1:0] ;//
reg [23:0] cnt_green_dym_s1 [MAX_PORT_NUM-1:0] ;
reg [23:0] cnt_blue_dym_s1  [MAX_PORT_NUM-1:0] ;
reg [23:0] cnt_white_dym_s1 [MAX_PORT_NUM-1:0] ;
reg [23:0] cnt_black_dym_s1 [MAX_PORT_NUM-1:0] ;
reg [23:0] cnt_total_dym_s1   ;


wire [23:0] cnt_red_dym_mask_s1   [MAX_PORT_NUM-1:0] ;// 考虑了 port_num 后的结果，例如如果 port_num= 2 ,那么 高两个cnt被钳制到0
wire [23:0] cnt_green_dym_mask_s1 [MAX_PORT_NUM-1:0] ;
wire [23:0] cnt_blue_dym_mask_s1  [MAX_PORT_NUM-1:0] ;
wire [23:0] cnt_white_dym_mask_s1 [MAX_PORT_NUM-1:0] ;
wire [23:0] cnt_black_dym_mask_s1 [MAX_PORT_NUM-1:0] ;


reg [23:0] cnt_red_total_dym_s2  = 0  ;
reg [23:0] cnt_green_total_dym_s2 = 0  ;
reg [23:0] cnt_blue_total_dym_s2  = 0  ;
reg [23:0] cnt_white_total_dym_s2 = 0  ;
reg [23:0] cnt_black_total_dym_s2 = 0  ;
reg [23:0] cnt_total_total_dym_s2 = 0  ;



wire [23:0] cnt_red_total_dym_tmp_s1 [MAX_PORT_NUM-1:0];
wire [23:0] cnt_green_total_dym_tmp_s1 [MAX_PORT_NUM-1:0];
wire [23:0] cnt_blue_total_dym_tmp_s1 [MAX_PORT_NUM-1:0];
wire [23:0] cnt_white_total_dym_tmp_s1 [MAX_PORT_NUM-1:0];
wire [23:0] cnt_black_total_dym_tmp_s1 [MAX_PORT_NUM-1:0];
wire [23:0] cnt_total_total_dym_tmp_s1 [MAX_PORT_NUM-1:0];


wire [23:0] cnt_red_total_dym_comp_s2    ; //总点数 减去 red点数 
wire [23:0] cnt_green_total_dym_comp_s2  ;
wire [23:0] cnt_blue_total_dym_comp_s2   ;
wire [23:0] cnt_white_total_dym_comp_s2  ;
wire [23:0] cnt_black_total_dym_comp_s2  ;


reg [31:0]  red_height ;
reg [31:0]  green_height ;
reg [31:0]  blue_height ;

reg [31:0]  red_height_ff ;
reg [31:0]  green_height_ff ;
reg [31:0]  blue_height_ff ;




reg [31:0]  err_count ;

reg [31:0] total_frame_num ;
reg [31:0] err_fram_num ;

/////////////////////////////////////////////////////////////////////////////////////////////////////




assign  SIGNAL_RED_O    = PURE_CHECK_MODE==0 ?  SIGNAL_RED_flagmode   : signal_red_cntmode    ;
assign  SIGNAL_GREEN_O  = PURE_CHECK_MODE==0 ?  SIGNAL_GREEN_flagmode : signal_green_cntmode  ;
assign  SIGNAL_BLUE_O   = PURE_CHECK_MODE==0 ?  SIGNAL_BLUE_flagmode  : signal_blue_cntmode   ;
assign  SIGNAL_WHITE_O  = PURE_CHECK_MODE==0 ?  SIGNAL_WHITE_flagmode : signal_white_cntmode  ;
assign  SIGNAL_BLACK_O  = PURE_CHECK_MODE==0 ?  SIGNAL_BLACK_flagmode : signal_black_cntmode  ;



`DELAY_OUTGEN(CLK_I,0,DE_I,DE_I_d ,1,INPUT_REG_NUM) 
`DELAY_OUTGEN(CLK_I,0,HS_I,HS_I_d ,1,INPUT_REG_NUM) 
`DELAY_OUTGEN(CLK_I,0,VS_I,VS_I_d ,1,INPUT_REG_NUM) 
`DELAY_OUTGEN(CLK_I,0,R_I ,R_I_d  ,(MAX_PORT_NUM*MAX_BPC),INPUT_REG_NUM) 
`DELAY_OUTGEN(CLK_I,0,G_I ,G_I_d  ,(MAX_PORT_NUM*MAX_BPC),INPUT_REG_NUM) 
`DELAY_OUTGEN(CLK_I,0,B_I ,B_I_d  ,(MAX_PORT_NUM*MAX_BPC),INPUT_REG_NUM) 


/////////////////////////////////////////////////////////////////////////////////////////////////////
always@(*)begin
    case(PORT_NUM_I)
        1:h_mult = 1;
        2:h_mult = 2;
        4:h_mult = 4;
        8:h_mult = 8;
        default:h_mult = 4;
    endcase
end
/////////////////////////////////////////////////////////////////////////////////////////////////////
                                                         
generate for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
    assign pixel_data_s0[i] = {B_I_d[i*MAX_BPC+:MAX_BPC],G_I_d[i*MAX_BPC+:MAX_BPC],R_I_d[i*MAX_BPC+:MAX_BPC]};
end
endgenerate


/////////////////////////////////////////////////////////////////////////////////////////////////////
// height 
always@(posedge  CLK_I)begin
    if(RST_I )begin
        red_height <= 0;
        green_height <= 0;
        blue_height <= 0 ;
        red_height_ff    <= 0;
        green_height_ff  <= 0;
        blue_height_ff   <= 0;

    end
    else if(VS_I_d_pos)begin
        red_height_ff   <= red_height ;    red_height <= 0; 
        green_height_ff <= green_height ;    green_height <= 0; 
        blue_height_ff  <= blue_height ;    blue_height <= 0; 
    end
    else if(DE_I_d)begin
        red_height    <= red_height   + R_I_d[7:0] + R_I_d[15:8] + R_I_d[23:16]  + R_I_d[31:24];
        green_height  <= green_height + G_I_d[7:0] + G_I_d[15:8] + G_I_d[23:16]  + G_I_d[31:24];
        blue_height   <= blue_height + B_I_d[7:0] + B_I_d[15:8] + B_I_d[23:16]  + B_I_d[31:24];
            
    end
end


wire [31:0] height_ff;
assign height_ff = red_height_ff + green_height_ff + blue_height_ff ;








///////////////////////////////////////////////////////////////////////////////////////////////////// 
//write to RAM //////////////////////////////////////////////////////////////////////////////////////

`NEG_MONITOR_OUTGEN(CLK_I,0,ram_updata,ram_updata_neg)

always @ (posedge CLK_I)begin
	if(RST_I)begin
		PARA_VALID_O <= 0;
	end
	else if(ram_updata_neg)begin
		PARA_VALID_O <= 1;
	end
end


always @ (posedge CLK_I) begin
    if(RST_I) begin
        RAM_DATA_O <= 0;
        RAM_ADDR_O <= 0;
        RAM_WR_O   <= 1;
        ram_updata <= 0;

    end 
    else if(TIMER_I_pos) begin
        RAM_WR_O    <= 1 ; 
        RAM_ADDR_O  <= 0;//reset addr
        RAM_DATA_O  <={16'h0000,16'hFFFF} ; // addr == 0
        ram_updata  <= 1 ;
    end 
    else if(ram_updata)  begin //can only be handelled this way
        RAM_WR_O      <= (RAM_ADDR_O==RAM_UPDATE_REG_NUM-1) ? 0  : 1 ; 
        RAM_ADDR_O    <= (RAM_ADDR_O==RAM_UPDATE_REG_NUM-1) ? RAM_UPDATE_REG_NUM-1 : RAM_ADDR_O + 1 ; 
        ram_updata    <= (RAM_ADDR_O==RAM_UPDATE_REG_NUM-1) ? 0  : 1;     
        case(RAM_ADDR_O)
            /* addr == 1 */  ADDR_HSYNC       / 4 - 1  :  RAM_DATA_O <=  {0,R_HSYNC   * h_mult }; //addr == 1 
            /* addr == 2 */  ADDR_HBP         / 4 - 1  :  RAM_DATA_O <=  {0,R_HBP     * h_mult };
            /* addr == 3 */  ADDR_HACTIVE     / 4 - 1  :  RAM_DATA_O <=  {0,R_HACTIVE * h_mult };
            /* addr == 4 */  ADDR_HFP         / 4 - 1  :  RAM_DATA_O <=  {0,R_HFP     * h_mult };
            /* addr == 5 */  ADDR_VSYNC       / 4 - 1  :  RAM_DATA_O <=  {0,R_VSYNC      };
            /* addr == 6 */  ADDR_VBP         / 4 - 1  :  RAM_DATA_O <=  {0,R_VBP        };
            /* addr == 7 */  ADDR_VACTIVE     / 4 - 1  :  RAM_DATA_O <=  {0,R_VACTIVE    };
            /* addr == 8 */  ADDR_VFP         / 4 - 1  :  RAM_DATA_O <=  {0,R_VFP        };
                                                                         //          FPS    红    绿    蓝 
            /* addr == 9 */  ADDR_FPS_C1      / 4 - 1  :  RAM_DATA_O <=  {0,R_FPS,PURE_CHECK_MODE==0 ? R_FPS_RED : R_FPS_RED_cntmode,PURE_CHECK_MODE==0 ? R_FPS_GREEN : R_FPS_GREEN_cntmode,PURE_CHECK_MODE==0 ? R_FPS_BLUE  : R_FPS_BLUE_cntmode } ; //if only vs come, fps plus one
			/* addr == a */  ADDR_FPS_C1_M1   / 4 - 1  :  RAM_DATA_O <=  fps_c1_reg[0] ; //如果
			/* */  ADDR_FPS_C1_M2   / 4 - 1  :  RAM_DATA_O <=  fps_c1_reg[1] ;
			/* */  ADDR_FPS_C1_M3   / 4 - 1  :  RAM_DATA_O <=  fps_c1_reg[2] ;
			/* */  ADDR_FPS_C1_M4   / 4 - 1  :  RAM_DATA_O <=  fps_c1_reg[3] ;
			/* */  ADDR_FPS_C1_M5   / 4 - 1  :  RAM_DATA_O <=  fps_c1_reg[4] ;
			/* */  ADDR_FPS_C1_M6   / 4 - 1  :  RAM_DATA_O <=  fps_c1_reg[5] ;
			/* */  ADDR_FPS_C1_M7   / 4 - 1  :  RAM_DATA_O <=  fps_c1_reg[6] ;
			/* */  ADDR_FPS_C1_M8   / 4 - 1  :  RAM_DATA_O <=  fps_c1_reg[7] ;
			/* */  ADDR_FPS_C1_M9   / 4 - 1  :  RAM_DATA_O <=  fps_c1_reg[8] ;
			/* */  ADDR_FPS_C1_M10  / 4 - 1  :  RAM_DATA_O <=  fps_c1_reg[9] ;
			/* */  ADDR_FPS_C2      / 4 - 1  :  RAM_DATA_O <=  {0,R_FPS_SERIES,PURE_CHECK_MODE==0 ? R_FPS_WHITE :R_FPS_WHITE_cntmode ,PURE_CHECK_MODE==0 ?  R_FPS_BLACK:R_FPS_BLACK_cntmode,8'd255} ; //if only vs come, fps plus one
			/* */  ADDR_FPS_C2_M1   / 4 - 1  :  RAM_DATA_O <=  fps_c2_reg[0] ;
			/* */  ADDR_FPS_C2_M2   / 4 - 1  :  RAM_DATA_O <=  fps_c2_reg[1] ;
			/* */  ADDR_FPS_C2_M3   / 4 - 1  :  RAM_DATA_O <=  fps_c2_reg[2] ;
			/* */  ADDR_FPS_C2_M4   / 4 - 1  :  RAM_DATA_O <=  fps_c2_reg[3] ;
			/* */  ADDR_FPS_C2_M5   / 4 - 1  :  RAM_DATA_O <=  fps_c2_reg[4] ;
			/* */  ADDR_FPS_C2_M6   / 4 - 1  :  RAM_DATA_O <=  fps_c2_reg[5] ;
			/* */  ADDR_FPS_C2_M7   / 4 - 1  :  RAM_DATA_O <=  fps_c2_reg[6] ;
			/* */  ADDR_FPS_C2_M8   / 4 - 1  :  RAM_DATA_O <=  fps_c2_reg[7] ;
			/* */  ADDR_FPS_C2_M9   / 4 - 1  :  RAM_DATA_O <=  fps_c2_reg[8] ;
			/* */  ADDR_FPS_C2_M10  / 4 - 1  :  RAM_DATA_O <=  fps_c2_reg[9] ;
			 
			//ADDR_PARA_VALID   / 4 - 1  : RAM_DATA_O <=  {0,PARA_VALID_O };
			//ADDR_RED_VALID    / 4 - 1  : RAM_DATA_O <=  {0,PURE_CHECK_MODE==0 ? SIGNAL_RED_flagmode   :  signal_red_cntmode     };
			//ADDR_GREEN_VALID  / 4 - 1  : RAM_DATA_O <=  {0,PURE_CHECK_MODE==0 ? SIGNAL_GREEN_flagmode :  signal_green_cntmode   };
			//ADDR_BLUE_VALID   / 4 - 1  : RAM_DATA_O <=  {0,PURE_CHECK_MODE==0 ? SIGNAL_BLUE_flagmode  :  signal_blue_cntmode    };
			//ADDR_WHITE_VALID  / 4 - 1  : RAM_DATA_O <=  {0,PURE_CHECK_MODE==0 ? SIGNAL_WHITE_flagmode :  signal_white_cntmode   };
			//ADDR_BLACK_VALID  / 4 - 1  : RAM_DATA_O <=  {0,PURE_CHECK_MODE==0 ? SIGNAL_BLACK_flagmode :  signal_black_cntmode   };
			 //ADDR_CRC_ERR      / 4 - 1  : RAM_DATA_O <=  CRC_ERR_FLAG_O;

             default :  RAM_DATA_O <=  0 ;
        endcase
    end  
    else  begin
        RAM_WR_O   <=  0 ;
    end
end


always@(posedge CLK_I)begin
	if(RST_I)begin
		fps_c1_reg[0] <= 0;
		fps_c1_reg[1] <= 0;
		fps_c1_reg[2] <= 0;
		fps_c1_reg[3] <= 0;
		fps_c1_reg[4] <= 0;
		fps_c1_reg[5] <= 0;
		fps_c1_reg[6] <= 0;
		fps_c1_reg[7] <= 0;
		fps_c1_reg[8] <= 0;
		fps_c1_reg[9] <= 0;
	end
	else if(TIMER_I_pos)begin//注意：[0]可以认为是当前值, 因为实际写入ram是timer后几个周期
		fps_c1_reg[0] <= {0,R_FPS,PURE_CHECK_MODE==0 ? R_FPS_RED : R_FPS_RED_cntmode,PURE_CHECK_MODE==0 ? R_FPS_GREEN : R_FPS_GREEN_cntmode,PURE_CHECK_MODE==0 ? R_FPS_BLUE  : R_FPS_BLUE_cntmode } ;//此时R_还没更新, 所以这里的R_ 是上1秒的值
		fps_c1_reg[1] <= fps_c1_reg[0] ;
		fps_c1_reg[2] <= fps_c1_reg[1] ;
		fps_c1_reg[3] <= fps_c1_reg[2] ;
		fps_c1_reg[4] <= fps_c1_reg[3] ;
		fps_c1_reg[5] <= fps_c1_reg[4] ;
		fps_c1_reg[6] <= fps_c1_reg[5] ;
		fps_c1_reg[7] <= fps_c1_reg[6] ;
		fps_c1_reg[8] <= fps_c1_reg[7] ;
		fps_c1_reg[9] <= fps_c1_reg[8] ;
	end
end


always@(posedge CLK_I)begin
	if(RST_I)begin
		fps_c2_reg[0] <= 0;
		fps_c2_reg[1] <= 0;
		fps_c2_reg[2] <= 0;
		fps_c2_reg[3] <= 0;
		fps_c2_reg[4] <= 0;
		fps_c2_reg[5] <= 0;
		fps_c2_reg[6] <= 0;
		fps_c2_reg[7] <= 0;
		fps_c2_reg[8] <= 0;
		fps_c2_reg[9] <= 0;
	end
	else if(TIMER_I_pos)begin//TIMER_I_pos 后才会更新 R_ 
		fps_c2_reg[0] <= {0,R_FPS_SERIES,PURE_CHECK_MODE==0 ? R_FPS_WHITE :R_FPS_WHITE_cntmode ,PURE_CHECK_MODE==0 ?  R_FPS_BLACK:R_FPS_BLACK_cntmode, 8'd255} ;
		fps_c2_reg[1] <= fps_c2_reg[0] ;
		fps_c2_reg[2] <= fps_c2_reg[1] ;
		fps_c2_reg[3] <= fps_c2_reg[2] ;
		fps_c2_reg[4] <= fps_c2_reg[3] ;
		fps_c2_reg[5] <= fps_c2_reg[4] ;
		fps_c2_reg[6] <= fps_c2_reg[5] ;
		fps_c2_reg[7] <= fps_c2_reg[6] ;
		fps_c2_reg[8] <= fps_c2_reg[7] ;
		fps_c2_reg[9] <= fps_c2_reg[8] ;
	end
end




//////////////////////////////////////////////////////////////////////////////////////////////////////
//上下边沿////////////////////////////////////////////////////////////////////////////////////////////

`POS_MONITOR_OUTGEN(CLK_I,0,TIMER_I,TIMER_I_pos)
`POS_MONITOR_OUTGEN(CLK_I,0,VS_I_d,VS_I_d_pos) // VS_I_d 注意外部 VS_I 已经打了一拍
`NEG_MONITOR_OUTGEN(CLK_I,0,VS_I_d,VS_I_d_neg)
`POS_MONITOR_OUTGEN(CLK_I,0,HS_I_d,HS_I_d_pos)
`NEG_MONITOR_OUTGEN(CLK_I,0,HS_I_d,HS_I_d_neg)
`POS_MONITOR_OUTGEN(CLK_I,0,DE_I_d,DE_I_d_pos)
`NEG_MONITOR_OUTGEN(CLK_I,0,DE_I_d,DE_I_d_neg)

`DELAY_OUTGEN(CLK_I,0,DE_I_d,DE_I_d_s1,1,1) 


///////////////////////////////R_HSYNC//////////////////////////////////
//OK

always@(posedge CLK_I)begin
    if(RST_I)begin
        HSYNC_count <= 0;
        R_HSYNC       <= 0;
    end
    else if(HS_I_d)begin
        HSYNC_count <= HSYNC_count + 1 ;
    end
    else if(HS_I_d_neg)begin
        R_HSYNC <= HSYNC_count ;
        HSYNC_count <= 0;
    end
end


////////////////////////////////R_HBP//////////////////////////////////
//OK

always@(posedge CLK_I)begin
    if(RST_I)begin
        HBP_valid <= 0;
    end
    else begin
        HBP_valid <= HS_I_d_neg ? 1 : DE_I_d_pos ? 0 : HBP_valid;
    end
end

`NEG_MONITOR_OUTGEN(CLK_I,0,HBP_valid,HBP_valid_neg)
always@(posedge CLK_I)begin
    if(RST_I)begin
        HBP_count <= 0;
    end
    else if(HBP_valid)begin
        HBP_count <= HBP_count + 1 ;
    end
    else if(HBP_valid_neg)begin
        R_HBP <= HBP_count ;
        HBP_count <= 0;
    end
end


///////////////////////////////R_HACTIVE/////////////////////////////////
//OK
//support uncontinuous DE

always@(posedge CLK_I)begin
    if(RST_I)begin
        DE_has <= 0;
    end
    else begin
        DE_has <= DE_I_d_pos ? 1 : HS_I_d_neg ? 0 : DE_has;   
    end
end
always@(posedge CLK_I)begin
    if(RST_I)begin
        HACTIVE_count <= 0;
        R_HACTIVE <= 0;
    end
    else if(DE_I_d)begin
        HACTIVE_count <= HACTIVE_count + 1 ; 
    end
    else if(HS_I_d_pos & DE_has)begin
        HACTIVE_count <= 0;
        R_HACTIVE <= HACTIVE_count;
    end
end

////////////////////////////////R_HFP/////////////////////////////////
//OK
//note: 当DE不连续时，R_HFP解析值无参考意义
//更进一步，DE不连续的原因是拉数据时钟比生成数据块
//所以此时只有vactive和hactive有参考价值
always@(posedge CLK_I)begin
    if(RST_I)begin
        HFP_valid <= 0;
    end
    else begin
        HFP_valid <= DE_I_d_neg ? 1 : HS_I_d_pos ? 0 : HFP_valid;
    end
end

`NEG_MONITOR_OUTGEN(CLK_I,0,HFP_valid,HFP_valid_neg)
always@(posedge CLK_I)begin
    if(RST_I)begin
        HFP_count <= 0;
        R_HFP <= 0;
    end
    else if(HFP_valid)begin
        HFP_count <= HFP_count + 1 ;
    end
    else if(HFP_valid_neg)begin
        R_HFP <= HFP_count ;
        HFP_count <= 0;
    end
end


/////////////////////////////////R_VSYNC/////////////////////////////////
//OK

assign VSYNC_valid = VS_I_d & HS_I_d_neg ;

always@(posedge CLK_I)begin
    if(RST_I)begin
        VSYNC_count <= 0;
        R_VSYNC <= 0;
    end
    else if(VSYNC_valid)begin
        VSYNC_count <= VSYNC_count + 1 ;
    end
    else if(VS_I_d_neg)begin
        R_VSYNC <= VSYNC_count;
        VSYNC_count <= 0;
    end
end

/////////////////////////////////R_VBP//////////////////////////////////
//note: 利用vs下沿，hs下沿

always@(posedge CLK_I)begin
    if(RST_I)begin
        VBP_valid_adv <= 0;
    end
    else begin
        VBP_valid_adv <= VS_I_d_neg ? 1 : DE_I_d_pos ? 0 : VBP_valid_adv ;
    end
end
assign VBP_valid = VBP_valid_adv & HS_I_d_neg ;
`NEG_MONITOR_OUTGEN(CLK_I,0,VBP_valid_adv,VBP_valid_adv_neg)
always@(posedge CLK_I)begin
    if(RST_I)begin
        VBP_count <= 0;
        VBP_b <= 0;
    end
    else if(VBP_valid)begin
        VBP_count <= VBP_count + 1 ;
    end
    else if(VBP_valid_adv_neg)begin
        VBP_b <= VBP_count ;
        VBP_count <= 0;
    end
end
assign R_VBP = VBP_b - 1;


///////////////////////////////R_VACTIVE////////////////////////////////
//OK

always@(posedge CLK_I)begin
    if(RST_I)begin
        VACTIVE_valid_adv <= 0 ;
    end
    else begin
        VACTIVE_valid_adv <= DE_I_d_pos ? 1 : (HS_I_d_pos | VS_I_d_pos) ? 0 : VACTIVE_valid_adv ;
    end
end
`NEG_MONITOR_OUTGEN(CLK_I,0,VACTIVE_valid_adv,VACTIVE_valid)
always@(posedge CLK_I)begin
    if(RST_I)begin
        R_VACTIVE <= 0;
        VACTIVE_count <= 0;
    end
    else if(VACTIVE_valid)begin
        VACTIVE_count <= VACTIVE_count + 1 ;
    end
    else if(VS_I_d_pos)begin
        VACTIVE_count <= 0;
        R_VACTIVE <= VACTIVE_count;
    end
end


///////////////////////////////VTOTAL////////////////////////////////
//OK

always@(posedge CLK_I)begin
    if(RST_I)begin
        VTOTAL <= 0;
        VTOTAL_count <= 0;
    end
    else if(HS_I_d_neg)begin 
        VTOTAL_count <= VTOTAL_count + 1;
    end
    else if(VS_I_d_pos)begin
        VTOTAL_count <= 0;
        VTOTAL <= VTOTAL_count;  
    end
end
assign R_VFP = VTOTAL - R_VBP - R_VACTIVE - R_VSYNC ;



//R_FPS/////////////////////////////////////////////////////////////////////////////////////////////
always @ (posedge CLK_I)begin
    if(RST_I) begin
       R_FPS       <= 0; 
       FPS_count   <= 0; 
    end 
    else if(TIMER_I_pos) begin  
       R_FPS       <= FPS_count ; 
       FPS_count   <= 0;  
    end 
    else if(VS_I_d_pos)begin
       FPS_count   <= FPS_count + 1;
    end
end



//R_FPS_SERIES//////////////////////////////////////////////////////////////////////////////////////
always @ (posedge CLK_I)begin
    if(RST_I) begin
       R_FPS_SERIES       <= 0; 
       FPS_SERIES_count   <= 0; 
    end 
    else if(TIMER_I_pos) begin  
       R_FPS_SERIES       <= FPS_SERIES_count ; 
       FPS_SERIES_count   <= 0;  
    end 
    else if(VS_I_d_pos_s2)begin
       FPS_SERIES_count   <= crc_reg_f == crc_reg_f_last ? FPS_SERIES_count + 1 : 1;
    end
end



//R_FPS_RED//////////////////////////////////////////////////////////////////////////////////////
always@(posedge CLK_I)begin
    if(RST_I)begin
		SIGNAL_RED_flagmode <= 0;
        R_FPS_RED <= 0;
        R_FPS_RED_count<= 0;
    end
    else if(TIMER_I_pos)begin
        R_FPS_RED <= R_FPS_RED_count;
        R_FPS_RED_count <= 0;
    end
    else if(VS_I_d_pos)begin//注意：直接上来的第一个vs，检测结果不准，因为此时各flag值都没有任何变化
        if({b_l_flag,g_l_flag,r_h_flag}==3'b111)begin
			SIGNAL_RED_flagmode    <= 1;
            R_FPS_RED_count <= R_FPS_RED_count + 1;
        end
		else begin
			SIGNAL_RED_flagmode    <= 0;
			R_FPS_RED_count <= R_FPS_RED_count;
		end
    end
end


//R_FPS_GREEN//////////////////////////////////////////////////////////////////////////////////////
always@(posedge CLK_I)begin
    if(RST_I)begin
        R_FPS_GREEN <= 0;
        R_FPS_GREEN_count<= 0;
    end
    else if(TIMER_I_pos)begin
        R_FPS_GREEN <= R_FPS_GREEN_count;
        R_FPS_GREEN_count <= 0;
    end
    else if(VS_I_d_pos)begin
        if({b_l_flag,g_h_flag,r_l_flag}==3'b111)begin
			SIGNAL_GREEN_flagmode    <= 1;
            R_FPS_GREEN_count <= R_FPS_GREEN_count + 1;
        end
		else begin
			SIGNAL_GREEN_flagmode    <= 0;
			R_FPS_GREEN_count <= R_FPS_GREEN_count ;
		end
    end
end



//R_FPS_BLUE//////////////////////////////////////////////////////////////////////////////////////
always@(posedge CLK_I)begin
    if(RST_I)begin
        R_FPS_BLUE <= 0;
        R_FPS_BLUE_count<= 0;
    end
    else if(TIMER_I_pos)begin
        R_FPS_BLUE <= R_FPS_BLUE_count;
        R_FPS_BLUE_count <= 0;
    end
    else if(VS_I_d_pos)begin
        if({b_h_flag,g_l_flag,r_l_flag}==3'b111)begin
			SIGNAL_BLUE_flagmode    <= 1;
            R_FPS_BLUE_count <= R_FPS_BLUE_count + 1;
        end
		else begin
			SIGNAL_BLUE_flagmode    <= 0;
            R_FPS_BLUE_count <= R_FPS_BLUE_count;
		end
    end
end



//R_FPS_WHITE//////////////////////////////////////////////////////////////////////////////////////
always@(posedge CLK_I)begin
    if(RST_I)begin
        R_FPS_WHITE <= 0;
        R_FPS_WHITE_count<= 0;
    end
    else if(TIMER_I_pos)begin
        R_FPS_WHITE <= R_FPS_WHITE_count;
        R_FPS_WHITE_count <= 0;
    end
    else if(VS_I_d_pos)begin
        if({b_h_flag,g_h_flag,r_h_flag}==3'b111)begin
			SIGNAL_WHITE_flagmode    <= 1;
            R_FPS_WHITE_count <= R_FPS_WHITE_count + 1;
        end
		else begin
			SIGNAL_WHITE_flagmode    <= 0;
            R_FPS_WHITE_count <= R_FPS_WHITE_count ;
		end
    end
end



//R_FPS_BLACK//////////////////////////////////////////////////////////////////////////////////////
always@(posedge CLK_I)begin
    if(RST_I)begin
        R_FPS_BLACK <= 0;
        R_FPS_BLACK_count<= 0;
    end
    else if(TIMER_I_pos)begin
        R_FPS_BLACK <= R_FPS_BLACK_count;
        R_FPS_BLACK_count <= 0;
    end
    else if(VS_I_d_pos)begin
        if({b_l_flag,g_l_flag,r_l_flag}==3'b111)begin
			SIGNAL_BLACK_flagmode    <= 1;
            R_FPS_BLACK_count <= R_FPS_BLACK_count + 1;
        end
		else begin
			SIGNAL_BLACK_flagmode    <= 0;
			R_FPS_BLACK_count <= R_FPS_BLACK_count ;
		end
    end
end


//////////////////////////////////////////////////////////////////////////////////////////////////////
//CRC valid area count
wire de_crc_not_valid; //筛选后的有效的计算crc的DE标志
wire de_crc_valid;
//HACTIVE_count
//VACTIVE_count

//input [15:0] CRC_EXCLUVE_X  ,
//input [15:0] CRC_EXCLUVE_Y  ,
//input [15:0] CRC_EXCLUVE_H  ,
//input [15:0] CRC_EXCLUVE_V 

//assign de_crc_not_valid =    HACTIVE_count > (CRC_EXCLUVE_X/h_mult) &&  HACTIVE_count <= (( CRC_EXCLUVE_X + CRC_EXCLUVE_H) /h_mult)
 //                        &&  VACTIVE_count > CRC_EXCLUVE_Y        &&  VACTIVE_count <= (( CRC_EXCLUVE_Y + CRC_EXCLUVE_V ) );

wire  vactive_valid;

//忽略第一行，最后一行
assign de_crc_not_valid  =  C_PORT_TYPE=="EDP1"  ?    VACTIVE_count ==0 || VACTIVE_count==1799 : 0 ;         
assign vactive_valid = VACTIVE_count!=0  &&  VACTIVE_count!= 1799 ;



//忽略第一行
//assign de_crc_not_valid  =  C_PORT_TYPE=="EDP1"  ?    VACTIVE_count ==0   : 0 ;         
//assign vactive_valid = VACTIVE_count!=0   ;





assign de_crc_valid = ~de_crc_not_valid;


//////////////////////////////////////////////////////////////////////////////////////////////////////
//CRC

always@(posedge CLK_I)begin
    if(RST_I | C_CRC_BLOCK_EN==0 )begin
        crc_last <= 0; //crc_last位宽为像素位宽两倍，所以求和运算的溢出位会被【保留】到高像素区域
    end
    else begin
        case(PORT_NUM_I)
            1:begin
                crc_last <= MAX_PORT_NUM>=1 ? crc_per_pixel[0] : crc_last ;
            end
            2:begin
                crc_last <= MAX_PORT_NUM>=2 ? crc_per_pixel[0] + crc_per_pixel[1] : crc_last ;
            end
            4:begin
                crc_last <= MAX_PORT_NUM>=4 ? crc_per_pixel[0] + crc_per_pixel[1] + crc_per_pixel[2] + crc_per_pixel[3] : crc_last ;
            end
            8:begin
                crc_last <= MAX_PORT_NUM>=8 ? crc_per_pixel[0] + crc_per_pixel[1] + crc_per_pixel[2] + crc_per_pixel[3] + crc_per_pixel[4] + crc_per_pixel[5] + crc_per_pixel[6] + crc_per_pixel[7] : crc_last ;
            end
            default: begin //4
                crc_last <= MAX_PORT_NUM>=4 ? crc_per_pixel[0] + crc_per_pixel[1] + crc_per_pixel[2] + crc_per_pixel[3] : crc_last ;
            end
        endcase
    end
end
reg VS_I_d_pos_dly;
reg [31:0]CRC_DATA_use;
always@(posedge CLK_I)begin
   CRC_DATA_use <=TARGET_CRC_DATA_I;
   VS_I_d_pos_dly<=VS_I_d_pos;
    if(RST_I )begin
        CRC_ERR_FLAG_O <= 0 ;
    end
    else if(VS_I_d_pos_dly)begin
        CRC_ERR_FLAG_O <= (crc_reg_f==CRC_DATA_use) ? 0:1;
    end
end


always@(posedge CLK_I)begin
    if(RST_I | C_CRC_BLOCK_EN==0 )begin
        {crc_reg_h,crc_reg_l} <= 0 ;
    end
    else if(VS_I_d_pos)begin
        {crc_reg_h,crc_reg_l} <= {0,crc_last} ;
    end
end


always@(posedge CLK_I)begin
    if(RST_I | C_CRC_BLOCK_EN==0 )begin
        crc_reg_f <= 0;
    end
    else begin
        crc_reg_f <= crc_reg_h + crc_reg_l ;
    end
end


`DELAY_OUTGEN(CLK_I,0,VS_I_d_pos,VS_I_d_pos_s2,1,2)



always@(posedge CLK_I)begin
    if(RST_I)begin
        crc_reg_f_last <= 0;
    end
    else if(FIFO_CRC_WR_O)begin
        crc_reg_f_last <= FIFO_CRC_O;   
    end
end



wire [31:0] cnt_err_total_s2_ff;

assign  FIFO_CRC_O = C_CRC_BLOCK_EN==1 ? crc_reg_f : 0 ;
assign  FIFO_CRC_WR_O  = C_CRC_BLOCK_EN==1 & VS_I_d_pos_s2  ;


assign  FIFO_HEIGHT_O = C_HEIGHT_BLOCK_EN==1 ? height_ff : 0 ;
assign  FIFO_HEIGHT_WR_O  = C_HEIGHT_BLOCK_EN==1 & VS_I_d_pos_s2  ;



assign  FIFO_ERR_COUNT_O = C_ERR_COUNT_BLOCK_EN==1 ? cnt_err_total_s2_ff : 0 ;
assign  FIFO_ERR_COUNT_WR_O  = C_ERR_COUNT_BLOCK_EN==1 & VS_I_d_pos_s2  ;




assign cnt_err_total_s2_ff = cnt_err_0_total_s2_ff +
 cnt_err_1_total_s2_ff + cnt_err_2_total_s2_ff + 
 cnt_err_3_total_s2_ff + cnt_err_4_total_s2_ff + 
 cnt_err_5_total_s2_ff + cnt_err_6_total_s2_ff  + cnt_err_7_total_s2_ff;
        

reg [31:0] TARGET_ERR_COUNT_I_reg;



always@(posedge CLK_I)begin
    TARGET_ERR_COUNT_I_reg <= TARGET_ERR_COUNT_I;
    if(RST_I )begin
        ERR_COUNT_FLAG_O <= 0 ;
    end
    else if(VS_I_d_pos)begin
        total_frame_num <= total_frame_num + 1 ;
        err_fram_num    <=  cnt_err_total_s2_ff>0 ? err_fram_num + 1 : err_fram_num ;
        ERR_COUNT_FLAG_O <= (cnt_err_total_s2_ff>TARGET_ERR_COUNT_I_reg) ? 1:0;
    end
end




reg [31:0] TARGET_HEIGHT_H_I_reg;
reg [31:0] TARGET_HEIGHT_L_I_reg;
always@(posedge CLK_I)begin
    TARGET_HEIGHT_H_I_reg <= TARGET_HEIGHT_H_I;
    TARGET_HEIGHT_L_I_reg <= TARGET_HEIGHT_L_I;
    if(RST_I )begin
        HEIGHT_ERR_FLAG_O <= 0 ;
    end
    else if(VS_I_d_pos)begin
        HEIGHT_ERR_FLAG_O <= (  (height_ff < TARGET_HEIGHT_L_I_reg) ||  (height_ff > TARGET_HEIGHT_H_I_reg)  ) ? 1:0;
    end
end









always@(*)begin
    case(PORT_NUM_I)
        1:begin
            r_h_flag_mask_dym = MAX_PORT_NUM>=1 ? {{MAX_PORT_NUM{1'b1}},r_h_flag_dym[0]} : r_h_flag_dym; 
            r_l_flag_mask_dym = MAX_PORT_NUM>=1 ? {{MAX_PORT_NUM{1'b1}},r_l_flag_dym[0]} : r_l_flag_dym;
            g_h_flag_mask_dym = MAX_PORT_NUM>=1 ? {{MAX_PORT_NUM{1'b1}},g_h_flag_dym[0]} : g_h_flag_dym;
            g_l_flag_mask_dym = MAX_PORT_NUM>=1 ? {{MAX_PORT_NUM{1'b1}},g_l_flag_dym[0]} : g_l_flag_dym;
            b_h_flag_mask_dym = MAX_PORT_NUM>=1 ? {{MAX_PORT_NUM{1'b1}},b_h_flag_dym[0]} : b_h_flag_dym;
            b_l_flag_mask_dym = MAX_PORT_NUM>=1 ? {{MAX_PORT_NUM{1'b1}},b_l_flag_dym[0]} : b_l_flag_dym;
            
        end
        2:begin
            r_h_flag_mask_dym = MAX_PORT_NUM>=2 ? {{MAX_PORT_NUM{1'b1}},r_h_flag_dym[1:0]} : r_h_flag_dym; 
            r_l_flag_mask_dym = MAX_PORT_NUM>=2 ? {{MAX_PORT_NUM{1'b1}},r_l_flag_dym[1:0]} : r_l_flag_dym;
            g_h_flag_mask_dym = MAX_PORT_NUM>=2 ? {{MAX_PORT_NUM{1'b1}},g_h_flag_dym[1:0]} : g_h_flag_dym;
            g_l_flag_mask_dym = MAX_PORT_NUM>=2 ? {{MAX_PORT_NUM{1'b1}},g_l_flag_dym[1:0]} : g_l_flag_dym;
            b_h_flag_mask_dym = MAX_PORT_NUM>=2 ? {{MAX_PORT_NUM{1'b1}},b_h_flag_dym[1:0]} : b_h_flag_dym;
            b_l_flag_mask_dym = MAX_PORT_NUM>=2 ? {{MAX_PORT_NUM{1'b1}},b_l_flag_dym[1:0]} : b_l_flag_dym;
        end
        4:begin
            r_h_flag_mask_dym = MAX_PORT_NUM>=4 ? {{MAX_PORT_NUM{1'b1}},r_h_flag_dym[3:0]} : r_h_flag_dym; 
            r_l_flag_mask_dym = MAX_PORT_NUM>=4 ? {{MAX_PORT_NUM{1'b1}},r_l_flag_dym[3:0]} : r_l_flag_dym;
            g_h_flag_mask_dym = MAX_PORT_NUM>=4 ? {{MAX_PORT_NUM{1'b1}},g_h_flag_dym[3:0]} : g_h_flag_dym;
            g_l_flag_mask_dym = MAX_PORT_NUM>=4 ? {{MAX_PORT_NUM{1'b1}},g_l_flag_dym[3:0]} : g_l_flag_dym;
            b_h_flag_mask_dym = MAX_PORT_NUM>=4 ? {{MAX_PORT_NUM{1'b1}},b_h_flag_dym[3:0]} : b_h_flag_dym;
            b_l_flag_mask_dym = MAX_PORT_NUM>=4 ? {{MAX_PORT_NUM{1'b1}},b_l_flag_dym[3:0]} : b_l_flag_dym;  
        end
        8:begin
            r_h_flag_mask_dym = MAX_PORT_NUM>=8 ? {{MAX_PORT_NUM{1'b1}},r_h_flag_dym[7:0]} : r_h_flag_dym; 
            r_l_flag_mask_dym = MAX_PORT_NUM>=8 ? {{MAX_PORT_NUM{1'b1}},r_l_flag_dym[7:0]} : r_l_flag_dym;
            g_h_flag_mask_dym = MAX_PORT_NUM>=8 ? {{MAX_PORT_NUM{1'b1}},g_h_flag_dym[7:0]} : g_h_flag_dym;
            g_l_flag_mask_dym = MAX_PORT_NUM>=8 ? {{MAX_PORT_NUM{1'b1}},g_l_flag_dym[7:0]} : g_l_flag_dym;
            b_h_flag_mask_dym = MAX_PORT_NUM>=8 ? {{MAX_PORT_NUM{1'b1}},b_h_flag_dym[7:0]} : b_h_flag_dym;
            b_l_flag_mask_dym = MAX_PORT_NUM>=8 ? {{MAX_PORT_NUM{1'b1}},b_l_flag_dym[7:0]} : b_l_flag_dym;
        end
        default:begin
            r_h_flag_mask_dym = r_h_flag_dym; 
            r_l_flag_mask_dym = r_l_flag_dym;
            g_h_flag_mask_dym = g_h_flag_dym;
            g_l_flag_mask_dym = g_l_flag_dym;
            b_h_flag_mask_dym = b_h_flag_dym;
            b_l_flag_mask_dym = b_l_flag_dym;
        end
    endcase
end


//////////////////////////////////// CNT 模式 /////////////////////////////////////////

always@(posedge CLK_I)begin
    if(RST_I | VS_I_d)begin
        cnt_total_dym_s1 <= 0; 
    end  
    else if(DE_I_d)begin//_d ~ s0  
        cnt_total_dym_s1 <= cnt_total_dym_s1 + PORT_NUM_I;
    end
end



generate for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
    always@(posedge CLK_I)begin
        if(RST_I | VS_I_d)begin
            cnt_red_dym_s1[i] <= 0;
        end            
        else if(DE_I_d)begin//_d ~ s0  
            cnt_red_dym_s1[i] <=  (pixel_data_af_mask_s0[i][MAX_BPC*0+:MAX_BPC] >= RH_I &
                            pixel_data_af_mask_s0[i][MAX_BPC*1+:MAX_BPC] <= GL_I &  
                            pixel_data_af_mask_s0[i][MAX_BPC*2+:MAX_BPC] <= BL_I   ) ? cnt_red_dym_s1[i] + 1 : cnt_red_dym_s1[i] ;
        end
    end
    
    assign cnt_red_dym_mask_s1[i] = (i+1) > PORT_NUM_I ? 0 : cnt_red_dym_s1[i];
    
end
endgenerate


generate for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
    always@(posedge CLK_I)begin
        if(RST_I | VS_I_d)begin
            cnt_green_dym_s1[i] <= 0; 
        end    
        else if(DE_I_d)begin//_d ~ s0  
         cnt_green_dym_s1[i] <=  (pixel_data_af_mask_s0[i][MAX_BPC*0+:MAX_BPC] <= RL_I &
                            pixel_data_af_mask_s0[i][MAX_BPC*1+:MAX_BPC] >= GH_I &  
                            pixel_data_af_mask_s0[i][MAX_BPC*2+:MAX_BPC] <= BL_I   ) ? cnt_green_dym_s1[i] + 1 : cnt_green_dym_s1[i] ;
                      
        end
    end
    
    assign cnt_green_dym_mask_s1[i] = (i+1) > PORT_NUM_I ? 0 : cnt_green_dym_s1[i];
        
end
endgenerate


generate for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
    always@(posedge CLK_I)begin
        if(RST_I | VS_I_d)begin
            cnt_blue_dym_s1[i] <= 0; 
        end    
        else if(DE_I_d)begin//_d ~ s0  
            cnt_blue_dym_s1[i] <=  (pixel_data_af_mask_s0[i][MAX_BPC*0+:MAX_BPC] <= RL_I &
                                pixel_data_af_mask_s0[i][MAX_BPC*1+:MAX_BPC] <= GL_I  &  
                                pixel_data_af_mask_s0[i][MAX_BPC*2+:MAX_BPC] >= BH_I   ) ? cnt_blue_dym_s1[i] + 1 : cnt_blue_dym_s1[i] ;
                      
        end
    end
    
    assign cnt_blue_dym_mask_s1[i] = (i+1) > PORT_NUM_I ? 0 : cnt_blue_dym_s1[i];
            
end
endgenerate


generate for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
    always@(posedge CLK_I)begin
        if(RST_I | VS_I_d)begin
            cnt_black_dym_s1[i] <= 0; 
        end    
        else if(DE_I_d)begin//_d ~ s0  
            cnt_black_dym_s1[i] <=  (pixel_data_af_mask_s0[i][MAX_BPC*0+:MAX_BPC] <= RL_I &
                            pixel_data_af_mask_s0[i][MAX_BPC*1+:MAX_BPC] <= GL_I  &  
                            pixel_data_af_mask_s0[i][MAX_BPC*2+:MAX_BPC] <= BL_I   ) ? cnt_black_dym_s1[i] + 1 : cnt_black_dym_s1[i] ;
                      
        end
    end
    
    assign cnt_black_dym_mask_s1[i] = (i+1) > PORT_NUM_I ? 0 : cnt_black_dym_s1[i];
        
end
endgenerate


generate for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
    always@(posedge CLK_I)begin
        if(RST_I | VS_I_d)begin
            cnt_white_dym_s1[i] <= 0; 
        end    
        else if(DE_I_d)begin//_d ~ s0  
            cnt_white_dym_s1[i] <=  (pixel_data_af_mask_s0[i][MAX_BPC*0+:MAX_BPC] >= RH_I &
                            pixel_data_af_mask_s0[i][MAX_BPC*1+:MAX_BPC] >= GH_I  &  
                            pixel_data_af_mask_s0[i][MAX_BPC*2+:MAX_BPC] >= BH_I   ) ? cnt_white_dym_s1[i] + 1 : cnt_white_dym_s1[i] ;
                      
        end
    end
    
    assign cnt_white_dym_mask_s1[i] = (i+1) > PORT_NUM_I ? 0 : cnt_white_dym_s1[i];
    
end
endgenerate


assign cnt_red_total_dym_comp_s2   = cnt_total_total_dym_s2 - cnt_red_total_dym_s2;
assign cnt_green_total_dym_comp_s2 = cnt_total_total_dym_s2 - cnt_green_total_dym_s2;
assign cnt_blue_total_dym_comp_s2  = cnt_total_total_dym_s2 - cnt_blue_total_dym_s2;
assign cnt_white_total_dym_comp_s2 = cnt_total_total_dym_s2 - cnt_white_total_dym_s2;
assign cnt_black_total_dym_comp_s2 =  cnt_total_total_dym_s2- cnt_black_total_dym_s2;


//R_FPS_RED cntmode//////////////////////////////////////////////////////////////////////////////////////
always@(posedge CLK_I)begin
    if(RST_I)begin
		signal_red_cntmode <= 0;
        R_FPS_RED_cntmode <= 0;
        R_FPS_RED_count_cntmode<= 0;
    end
    else if(TIMER_I_pos)begin
        R_FPS_RED_cntmode <= R_FPS_RED_count_cntmode;
        R_FPS_RED_count_cntmode <= 0;
    end
    else if(VS_I_d_pos)begin
        if(cnt_total_total_dym_s2>0 && cnt_red_total_dym_comp_s2<=EXCLUDE_PT_NUM_I )begin
			signal_red_cntmode    <= 1;
            R_FPS_RED_count_cntmode <= R_FPS_RED_count_cntmode + 1;
        end
		else begin
			signal_red_cntmode    <= 0;
			R_FPS_RED_count_cntmode <= R_FPS_RED_count_cntmode;
		end
    end
end


//R_FPS_GREEN cntmode//////////////////////////////////////////////////////////////////////////////////////
always@(posedge CLK_I)begin
    if(RST_I)begin
		signal_green_cntmode <= 0;
        R_FPS_GREEN_cntmode <= 0;
        R_FPS_GREEN_count_cntmode<= 0;
    end
    else if(TIMER_I_pos)begin
        R_FPS_GREEN_cntmode <= R_FPS_GREEN_count_cntmode;
        R_FPS_GREEN_count_cntmode <= 0;
    end
    else if(VS_I_d_pos)begin
        if(cnt_total_total_dym_s2>0 && cnt_green_total_dym_comp_s2<=EXCLUDE_PT_NUM_I )begin
			signal_green_cntmode    <= 1;
            R_FPS_GREEN_count_cntmode <= R_FPS_GREEN_count_cntmode + 1;
        end
		else begin
			signal_green_cntmode    <= 0;
			R_FPS_GREEN_count_cntmode <= R_FPS_GREEN_count_cntmode;
		end
    end
end


//R_FPS_BLUE cntmode//////////////////////////////////////////////////////////////////////////////////////
always@(posedge CLK_I)begin
    if(RST_I)begin
		signal_blue_cntmode <= 0;
        R_FPS_BLUE_cntmode <= 0;
        R_FPS_BLUE_count_cntmode<= 0;
    end
    else if(TIMER_I_pos)begin
        R_FPS_BLUE_cntmode <= R_FPS_BLUE_count_cntmode;
        R_FPS_BLUE_count_cntmode <= 0;
    end
    else if(VS_I_d_pos)begin
        if(cnt_total_total_dym_s2>0 && cnt_blue_total_dym_comp_s2<=EXCLUDE_PT_NUM_I )begin
			signal_blue_cntmode    <= 1;
            R_FPS_BLUE_count_cntmode <= R_FPS_BLUE_count_cntmode + 1;
        end
		else begin
			signal_blue_cntmode    <= 0;
			R_FPS_BLUE_count_cntmode <= R_FPS_BLUE_count_cntmode;
		end
    end
end


//R_FPS_BLACK cntmode//////////////////////////////////////////////////////////////////////////////////////
always@(posedge CLK_I)begin
    if(RST_I)begin
		signal_black_cntmode <= 0;
        R_FPS_BLACK_cntmode <= 0;
        R_FPS_BLACK_count_cntmode<= 0;
    end
    else if(TIMER_I_pos)begin
        R_FPS_BLACK_cntmode <= R_FPS_BLACK_count_cntmode;
        R_FPS_BLACK_count_cntmode <= 0;
    end
    else if(VS_I_d_pos)begin
        if(cnt_total_total_dym_s2>0 && cnt_black_total_dym_comp_s2<=EXCLUDE_PT_NUM_I )begin
			signal_black_cntmode    <= 1;
            R_FPS_BLACK_count_cntmode <= R_FPS_BLACK_count_cntmode + 1;
        end
		else begin
			signal_black_cntmode    <= 0;
			R_FPS_BLACK_count_cntmode <= R_FPS_BLACK_count_cntmode;
		end
    end
end



//R_FPS_WHITE cntmode//////////////////////////////////////////////////////////////////////////////////////
always@(posedge CLK_I)begin
    if(RST_I)begin
		signal_white_cntmode <= 0;
        R_FPS_WHITE_cntmode <= 0;
        R_FPS_WHITE_count_cntmode<= 0;
    end
    else if(TIMER_I_pos)begin
        R_FPS_WHITE_cntmode <= R_FPS_WHITE_count_cntmode;
        R_FPS_WHITE_count_cntmode <= 0;
    end
    else if(VS_I_d_pos)begin
        if(cnt_total_total_dym_s2>0 && cnt_white_total_dym_comp_s2<=EXCLUDE_PT_NUM_I )begin
			signal_white_cntmode    <= 1;
            R_FPS_WHITE_count_cntmode <= R_FPS_WHITE_count_cntmode + 1;
        end
		else begin
			signal_white_cntmode    <= 0;
			R_FPS_WHITE_count_cntmode <= R_FPS_WHITE_count_cntmode;
		end
    end
end





assign cnt_red_total_dym_tmp_s1[0] = cnt_red_dym_mask_s1[0] ;
generate for(i=1;i<=MAX_PORT_NUM-1;i=i+1)begin
    assign cnt_red_total_dym_tmp_s1[i] = cnt_red_total_dym_tmp_s1[i-1] + cnt_red_dym_mask_s1[i] ;
end
endgenerate
always@(posedge CLK_I)cnt_red_total_dym_s2 <= cnt_red_total_dym_tmp_s1[MAX_PORT_NUM-1];


assign cnt_green_total_dym_tmp_s1[0] = cnt_green_dym_mask_s1[0] ;
generate for(i=1;i<=MAX_PORT_NUM-1;i=i+1)begin
    assign cnt_green_total_dym_tmp_s1[i] = cnt_green_total_dym_tmp_s1[i-1] + cnt_green_dym_mask_s1[i] ;
end
endgenerate
always@(posedge CLK_I)cnt_green_total_dym_s2 <= cnt_green_total_dym_tmp_s1[MAX_PORT_NUM-1];


assign cnt_blue_total_dym_tmp_s1[0] = cnt_blue_dym_mask_s1[0] ;
generate for(i=1;i<=MAX_PORT_NUM-1;i=i+1)begin
    assign cnt_blue_total_dym_tmp_s1[i] = cnt_blue_total_dym_tmp_s1[i-1] + cnt_blue_dym_mask_s1[i] ;
end
endgenerate
always@(posedge CLK_I)cnt_blue_total_dym_s2 <= cnt_blue_total_dym_tmp_s1[MAX_PORT_NUM-1];


assign cnt_white_total_dym_tmp_s1[0] = cnt_white_dym_mask_s1[0] ;
generate for(i=1;i<=MAX_PORT_NUM-1;i=i+1)begin
    assign cnt_white_total_dym_tmp_s1[i] = cnt_white_total_dym_tmp_s1[i-1] + cnt_white_dym_mask_s1[i] ;
end
endgenerate
always@(posedge CLK_I)cnt_white_total_dym_s2 <= cnt_white_total_dym_tmp_s1[MAX_PORT_NUM-1];


assign cnt_black_total_dym_tmp_s1[0] = cnt_black_dym_mask_s1[0] ;
generate for(i=1;i<=MAX_PORT_NUM-1;i=i+1)begin
    assign cnt_black_total_dym_tmp_s1[i] = cnt_black_total_dym_tmp_s1[i-1] + cnt_black_dym_mask_s1[i] ;
end
endgenerate
always@(posedge CLK_I)cnt_black_total_dym_s2 <= cnt_black_total_dym_tmp_s1[MAX_PORT_NUM-1];



always@(posedge CLK_I)cnt_total_total_dym_s2 <= cnt_total_dym_s1; //打一拍



//////////////////////////////////// FLAG 模式 ////////////////////////////////////////
generate for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
    always@(posedge CLK_I)begin
        if(VS_I_d_pos)begin
            r_h_flag_dym[i] <= 1'b1;
        end
        else if(DE_I_d)begin//_d ~ s0  
            r_h_flag_dym[i] <= pixel_data_af_mask_s0[i][MAX_BPC*0+:MAX_BPC] >= RH_I;
        end
    end
end
endgenerate 


generate for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
    always@(posedge CLK_I)begin
        if(VS_I_d_pos)begin
            r_l_flag_dym[i] <= 1'b1;
        end
        else if(DE_I_d)begin//_d ~ s0  
            r_l_flag_dym[i] <= pixel_data_af_mask_s0[i][MAX_BPC*0+:MAX_BPC] <= RL_I;
        end
    end
end
endgenerate


generate for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
    always@(posedge CLK_I)begin
        if(VS_I_d_pos)begin
            g_h_flag_dym[i] <= 1'b1;
        end
        else if(DE_I_d)begin//_d ~ s0  
            g_h_flag_dym[i] <= pixel_data_af_mask_s0[i][MAX_BPC*1+:MAX_BPC] >= GH_I;
        end
    end
end
endgenerate 


generate for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
    always@(posedge CLK_I)begin
        if(VS_I_d_pos)begin
            g_l_flag_dym[i] <= 1'b1;
        end
        else if(DE_I_d)begin//_d ~ s0  
            g_l_flag_dym[i] <= pixel_data_af_mask_s0[i][MAX_BPC*1+:MAX_BPC] <= GL_I;
        end
    end
end
endgenerate


generate for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
    always@(posedge CLK_I)begin
        if(VS_I_d_pos)begin
            b_h_flag_dym[i] <= 1'b1;
        end
        else if(DE_I_d)begin//_d ~ s0  
            b_h_flag_dym[i] <= pixel_data_af_mask_s0[i][MAX_BPC*2+:MAX_BPC] >= BH_I;
        end
    end
end
endgenerate


generate for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
    always@(posedge CLK_I)begin
        if(VS_I_d_pos)begin
            b_l_flag_dym[i] <= 1'b1;
        end
        else if(DE_I_d)begin//_d ~ s0  
            b_l_flag_dym[i] <= pixel_data_af_mask_s0[i][MAX_BPC*2+:MAX_BPC] <= BL_I;
        end
    end
end
endgenerate


always@(posedge CLK_I)begin
    if(RST_I | VS_I_d_pos)begin
        r_h_flag <= 1;
        r_l_flag <= 1;
        g_h_flag <= 1;
        g_l_flag <= 1;
        b_h_flag <= 1;
        b_l_flag <= 1;
    end
    else if(DE_I_d_s1)begin// _flag_mask_dym 和 DE_I_d_s1 对齐
        r_h_flag <= ~&r_h_flag_mask_dym ? 0 : r_h_flag;
        r_l_flag <= ~&r_l_flag_mask_dym ? 0 : r_l_flag;
        g_h_flag <= ~&g_h_flag_mask_dym ? 0 : g_h_flag;
        g_l_flag <= ~&g_l_flag_mask_dym ? 0 : g_l_flag;
        b_h_flag <= ~&b_h_flag_mask_dym ? 0 : b_h_flag;
        b_l_flag <= ~&b_l_flag_mask_dym ? 0 : b_l_flag;
    end
end



generate if(MAX_BPC==6)begin
	for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
	    always@(*)begin
	        case(BPC_I)
	            6:begin //注意：一个pixel中包含b g r , mask 中根据BPC强制对无效高位赋0
	                pixel_data_af_mask_s0[i] =  pixel_data_s0[i];
	            end
	            default:begin
	                pixel_data_af_mask_s0[i] = pixel_data_s0[i];
	            end
	        endcase
        end
    end
end
else if(MAX_BPC==8)begin
    for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
        always@(*)begin
            case(BPC_I)
                6:begin //注意：要对RGB分别处理
                    pixel_data_af_mask_s0[i] = {{2'b0,pixel_data_s0[i][MAX_BPC*2+:6]},{2'b0,pixel_data_s0[i][MAX_BPC*1+:6]},{2'b0,pixel_data_s0[i][MAX_BPC*0+:6]}} ;
                end
                8:begin
                    pixel_data_af_mask_s0[i] =  pixel_data_s0[i];
                end
                default:begin
                    pixel_data_af_mask_s0[i] = pixel_data_s0[i];
                end
            endcase
        end
    end
end
else if(MAX_BPC==10)begin
    for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
        always@(*)begin
            case(BPC_I)
                6:begin //注意：要对RGB分别处理   ---- 
                    pixel_data_af_mask_s0[i] = {{4'b0,pixel_data_s0[i][MAX_BPC*2+:6]},{4'b0,pixel_data_s0[i][MAX_BPC*1+:6]},{4'b0,pixel_data_s0[i][MAX_BPC*0+:6]}} ;
                end
                8:begin
                    pixel_data_af_mask_s0[i] = {{2'b0,pixel_data_s0[i][MAX_BPC*2+:8]},{2'b0,pixel_data_s0[i][MAX_BPC*1+:8]},{2'b0,pixel_data_s0[i][MAX_BPC*0+:8]}} ;
                end
                10:begin
                    pixel_data_af_mask_s0[i] =  pixel_data_s0[i];
                end
                default:begin
                    pixel_data_af_mask_s0[i] = pixel_data_s0[i];
                end
            endcase
        end
    end
end
else if(MAX_BPC==12)begin
    for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
        always@(*)begin
            case(BPC_I)
                6:begin //注意：要对RGB分别处理
                    pixel_data_af_mask_s0[i] = {{6'b0,pixel_data_s0[i][MAX_BPC*2+:6]},{6'b0,pixel_data_s0[i][MAX_BPC*1+:6]},{6'b0,pixel_data_s0[i][MAX_BPC*0+:6]}} ;
                end
                8:begin
                    pixel_data_af_mask_s0[i] = {{4'b0,pixel_data_s0[i][MAX_BPC*2+:8]},{4'b0,pixel_data_s0[i][MAX_BPC*1+:8]},{4'b0,pixel_data_s0[i][MAX_BPC*0+:8]}} ;
                end
                10:begin
                    pixel_data_af_mask_s0[i] = {{2'b0,pixel_data_s0[i][MAX_BPC*2+:10]},{2'b0,pixel_data_s0[i][MAX_BPC*1+:10]},{2'b0,pixel_data_s0[i][MAX_BPC*0+:10]}} ;
                end
                12:begin
                    pixel_data_af_mask_s0[i] =   pixel_data_s0[i];
                end
                default:begin
                    pixel_data_af_mask_s0[i] = pixel_data_s0[i];
                end
            endcase
        end
    end
end
else begin
    for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin //层层屏蔽
        always@(*)begin
            case(BPC_I)
                6:begin //注意：要对RGB分别处理
                    pixel_data_af_mask_s0[i] = {{2'b0,pixel_data_s0[i][MAX_BPC*2+:6]},{2'b0,pixel_data_s0[i][MAX_BPC*1+:6]},{2'b0,pixel_data_s0[i][MAX_BPC*0+:6]}} ;
                end
                8:begin
                    pixel_data_af_mask_s0[i] =  pixel_data_s0[i];
                end
                default:begin
                    pixel_data_af_mask_s0[i] = pixel_data_s0[i];
                end
            endcase
        end
    end
end

endgenerate



///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
generate if(C_CRC_BLOCK_EN==1 & MAX_BPC==6)begin
//exp: RRRR  GGGG  BBBB


for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
    crc18_rgb crc_u(
        .data_in (pixel_data_af_mask_s0[i]),//note: width is desided by MAX_BPC
        .crc_en  (DE_I_d & de_crc_valid), //2024年7月17日12:06:22
        .crc_out (crc_3bpc_temp[i]),
        .rst     (RST_I | VS_I_d_pos),
        .clk     (CLK_I)
        );
    assign crc_per_pixel[i] = {0,crc_3bpc_temp[i]}; //防止高位出现不确定位
end



end
///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
else if(C_CRC_BLOCK_EN==1 & MAX_BPC==8)begin

for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
    crc24_rgb crc_u(
        .data_in (pixel_data_af_mask_s0[i]),//note: width is desided by MAX_BPC
        .crc_en  (DE_I_d  & de_crc_valid),
        .crc_out (crc_3bpc_temp[i]),
        .rst     (RST_I | VS_I_d_pos),
        .clk     (CLK_I)
        );
    assign crc_per_pixel[i] = {0,crc_3bpc_temp[i]}; //防止高位出现不确定位
end    

end
///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
else if(C_CRC_BLOCK_EN==1 & MAX_BPC==10)begin

for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
    crc30_rgb crc_u(
        .data_in (pixel_data_af_mask_s0[i]),//note: width is desided by MAX_BPC
        .crc_en  (DE_I_d  & de_crc_valid),
        .crc_out (crc_3bpc_temp[i]),
        .rst     (RST_I | VS_I_d_pos),
        .clk     (CLK_I)
        );
    assign crc_per_pixel[i] = {0,crc_3bpc_temp[i]}; //防止高位出现不确定位
end
end
///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
else if(C_CRC_BLOCK_EN==1 & MAX_BPC==12)begin
//for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
//    always@(*)begin
//        case(BPC_I)
//            6:begin //注意：要对RGB分别处理
//                pixel_data_af_mask_s0[i] = {{6'b0,pixel_data_s0[i][MAX_BPC*2+:6]},{6'b0,pixel_data_s0[i][MAX_BPC*1+:6]},{6'b0,pixel_data_s0[i][MAX_BPC*0+:6]}} ;
//            end
//            8:begin
//                pixel_data_af_mask_s0[i] = {{4'b0,pixel_data_s0[i][MAX_BPC*2+:8]},{4'b0,pixel_data_s0[i][MAX_BPC*1+:8]},{4'b0,pixel_data_s0[i][MAX_BPC*0+:8]}} ;
//            end
//            10:begin
//                pixel_data_af_mask_s0[i] = {{2'b0,pixel_data_s0[i][MAX_BPC*2+:10]},{2'b0,pixel_data_s0[i][MAX_BPC*1+:10]},{2'b0,pixel_data_s0[i][MAX_BPC*0+:10]}} ;
//            end
//            12:begin
//                pixel_data_af_mask_s0[i] =   pixel_data_s0[i];
//            end
//            default:begin
//                pixel_data_af_mask_s0[i] = pixel_data_s0[i];
//            end
//        endcase
//    end
//end

for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
    crc36_rgb crc_u(
        .data_in (pixel_data_af_mask_s0[i]),//note: width is desided by MAX_BPC
        .crc_en  (DE_I_d  & de_crc_valid),
        .crc_out (crc_3bpc_temp[i]),
        .rst     (RST_I | VS_I_d_pos),
        .clk     (CLK_I)
        );
    assign crc_per_pixel[i] = {0,crc_3bpc_temp[i]}; //防止高位出现不确定位
end

end
///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
else if(C_CRC_BLOCK_EN==1)begin//default crc use 8bit bpc
//for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
//    always@(*)begin
//        case(BPC_I)
//            default:begin
//                pixel_data_af_mask_s0[i] = pixel_data_s0[i];
//            end
//        endcase
//    end
//end

for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
    crc24_rgb crc_u(
        .data_in (pixel_data_af_mask_s0[i]),//note: width is desided by MAX_BPC
        .crc_en  (DE_I_d  & de_crc_valid ),
        .crc_out (crc_3bpc_temp[i]),
        .rst     (RST_I | VS_I_d_pos),
        .clk     (CLK_I)
        );
    assign crc_per_pixel[i] = {0,crc_3bpc_temp[i]}; //防止高位出现不确定位
end

    

end
endgenerate
    
    




/////////////////////////////////////////////////////////////////特创 判断错误点数///////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


wire de_0; //特创第一段 de  //d
wire de_1;
wire de_2;
wire de_3;
wire de_4;
wire de_5;
wire de_6;
wire de_7;




reg [31:0] cnt_err_0 [ MAX_PORT_NUM-1:0 ] ; //s1
reg [31:0] cnt_err_1 [ MAX_PORT_NUM-1:0 ] ;
reg [31:0] cnt_err_2 [ MAX_PORT_NUM-1:0 ] ;
reg [31:0] cnt_err_3 [ MAX_PORT_NUM-1:0 ] ;
reg [31:0] cnt_err_4 [ MAX_PORT_NUM-1:0 ] ;
reg [31:0] cnt_err_5 [ MAX_PORT_NUM-1:0 ] ;
reg [31:0] cnt_err_6 [ MAX_PORT_NUM-1:0 ] ;
reg [31:0] cnt_err_7 [ MAX_PORT_NUM-1:0 ] ;


//assign  de_0 = DE_I_d && (HACTIVE_count< 512/4)   ;  //d                           
//assign  de_1 = DE_I_d && (HACTIVE_count>= 512/4    )  &&  (HACTIVE_count<(512*2/4) ) ;
//assign  de_2 = DE_I_d && (HACTIVE_count>= (512*2/4))  &&  (HACTIVE_count<(512*3/4) ) ;
//assign  de_3 = DE_I_d && (HACTIVE_count>= (512*3/4))  &&  (HACTIVE_count<(512*4/4) ) ;
//assign  de_4 = DE_I_d && (HACTIVE_count>= (512*4/4))  &&  (HACTIVE_count<(512*5/4) ) ;
//assign  de_5 = DE_I_d && (HACTIVE_count>= (512*5/4))  &&  (HACTIVE_count<2880/4    )  ;



localparam C_SLOT  =  C_PORT_TYPE=="EDP1" ? SLOT_EDP1_NUM/4 : C_PORT_TYPE=="LVDS0" ? SLOT_LVDS0_NUM : C_PORT_TYPE=="LVDS1" ? SLOT_LVDS1_NUM : SLOT_EDP1_NUM/4 ; 







assign  de_0 = C_PORT_TYPE=="EDP1"  ? DE_I_d && (HACTIVE_count<   C_SLOT ) && vactive_valid : 
               C_PORT_TYPE=="LVDS0" ? DE_I_d && (HACTIVE_count<  171     )  : 
                                      DE_I_d && (HACTIVE_count<  103     )                         
              ;  
                     
                     
assign  de_1 = C_PORT_TYPE=="EDP1"  ?  DE_I_d && (HACTIVE_count>=  C_SLOT    )  &&  (HACTIVE_count< (C_SLOT*2) )  && vactive_valid :
              C_PORT_TYPE=="LVDS0" ? DE_I_d && (HACTIVE_count>=  171    )  &&(HACTIVE_count<  171+171     )  : 
                                      DE_I_d && (HACTIVE_count>= 103     )  &&(HACTIVE_count<  103 +102    )                         
              ;  



 
assign  de_2 = C_PORT_TYPE=="EDP1"  ?   DE_I_d && (HACTIVE_count>= (C_SLOT*2))  &&  (HACTIVE_count<(C_SLOT*3) )  && vactive_valid  :
            C_PORT_TYPE=="LVDS0" ? DE_I_d && (HACTIVE_count>= 171+171     )  &&(HACTIVE_count<  171+171+170     )  : 
                                DE_I_d && (HACTIVE_count>=  103+102    )  &&(HACTIVE_count<  103 +102+ 103      )                         
              ;  





assign  de_3 = C_PORT_TYPE=="EDP1"  ?   DE_I_d && (HACTIVE_count>= (C_SLOT*3))  &&  (HACTIVE_count<(C_SLOT*4) )  && vactive_valid   :
                C_PORT_TYPE=="LVDS0" ? DE_I_d && (HACTIVE_count>=  171+171+170    )  &&(HACTIVE_count<   171+171+170    +171     )  : 
                                      DE_I_d &&(HACTIVE_count>= 103 +102+ 103     )  && (HACTIVE_count<  103 +102+ 103+ 102      )                         
              ;  




assign  de_4 = C_PORT_TYPE=="EDP1"  ?    DE_I_d && (HACTIVE_count>= (C_SLOT*4))  &&  (HACTIVE_count<(C_SLOT*5) )  && vactive_valid  :
                C_PORT_TYPE=="LVDS0" ? DE_I_d &&(HACTIVE_count>=   171+171+170  +171    )  && (HACTIVE_count<   171+171+170  +171+171     )  : 
                                      DE_I_d &&(HACTIVE_count>=    103 +102+ 103+ 102  )  && (HACTIVE_count<  103 +102+ 103+ 102+ 102      )                         
              ;  




assign  de_5 = C_PORT_TYPE=="EDP1"  ?    DE_I_d && (HACTIVE_count>= (C_SLOT*5))  &&  (HACTIVE_count<(C_SLOT*6) )  && vactive_valid  :
                C_PORT_TYPE=="LVDS0" ? DE_I_d &&(HACTIVE_count>=  171+171+170  +171+171    )  && (HACTIVE_count<   171+171+170  +171+171 +170     )  : 
                                      DE_I_d && (HACTIVE_count>= 103 +102+ 103+ 102+ 102     )  &&(HACTIVE_count<  103 +102+ 103+ 102+ 102+ 103     )                         
              ;  





assign  de_6 = C_PORT_TYPE=="EDP1"  ?    DE_I_d && (HACTIVE_count>= (C_SLOT*6))  &&  (HACTIVE_count<(C_SLOT*7) ) && vactive_valid  :
                C_PORT_TYPE=="LVDS0" ? DE_I_d &&(HACTIVE_count>= 171+171+170  +171+171 +170     )  && (HACTIVE_count<  171+171+170  +171+171 +170  +171     )  : 
                                      DE_I_d && (HACTIVE_count>= 103 +102+ 103+ 102+ 102+ 103     )  &&(HACTIVE_count<  103 +102+ 103+ 102+ 102+ 103+ 102    )                         
              ;  




assign  de_7 = C_PORT_TYPE=="EDP1"  ?    DE_I_d && (HACTIVE_count>= (C_SLOT*7))  &&  (HACTIVE_count<(C_SLOT*8) )  && vactive_valid  :
                C_PORT_TYPE=="LVDS0" ? DE_I_d && (HACTIVE_count>= 171+171+170  +171+171 +170  +171     )  &&(HACTIVE_count<  171+171+170  +171+171 +170  +171   + 85     )  : 
                                      DE_I_d && (HACTIVE_count>= 103 +102+ 103+ 102+ 102+ 103+ 102     )  &&(HACTIVE_count<  103 +102+ 103+ 102+ 102+ 103+ 102+ 83     )                         
              ;  













//R  G  B
//H  H  H  white 
//H  H  L  yellow
//L  H  H  qian lan
//L  H  L  green
//H  L  H  fenhong
//H  L  L  red
//L  L  H  blue
//L  L  L  black



//H  H  H  white 
generate for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
always@(posedge CLK_I)begin
        if(RST_I | VS_I_d_neg)begin
            cnt_err_0[i] <= 0; 
        end    
        else if(de_0)begin//_d ~ s0  
            cnt_err_0[i] <=    (pixel_data_af_mask_s0[i][MAX_BPC*0+:MAX_BPC] < RH_I |
                                pixel_data_af_mask_s0[i][MAX_BPC*1+:MAX_BPC] < GH_I |  
                                pixel_data_af_mask_s0[i][MAX_BPC*2+:MAX_BPC] < BH_I   ) ? cnt_err_0[i] + 1 : cnt_err_0[i] ;
                      
        end
    end
end
endgenerate
reg [31:0 ]  cnt_err_0_total_s2 = 0;
wire [31:0] cnt_err_0_total [MAX_PORT_NUM-1:0] ;
//d s1 s2
assign cnt_err_0_total[0] = cnt_err_0[0] ;
generate for(i=1;i<=MAX_PORT_NUM-1;i=i+1)begin
    assign cnt_err_0_total[i] = cnt_err_0_total[i-1] + cnt_err_0[i] ;
end
endgenerate
always@(posedge CLK_I)cnt_err_0_total_s2 <= cnt_err_0_total[MAX_PORT_NUM-1];
reg [31:0 ]  cnt_err_0_total_s2_ff= 0;
always@(posedge CLK_I)begin
    if(RST_I)begin
		cnt_err_0_total_s2_ff <= 0;
    end
    else if(VS_I_d_pos)begin
        cnt_err_0_total_s2_ff <= cnt_err_0_total_s2 ;
    end
end




//H  H  L  yellow
generate for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
always@(posedge CLK_I)begin
        if(RST_I | VS_I_d_neg)begin
            cnt_err_1[i] <= 0; 
        end    
        else if(de_1)begin//_d ~ s0  
            cnt_err_1[i] <=    (pixel_data_af_mask_s0[i][MAX_BPC*0+:MAX_BPC] < RH_I |    
                                pixel_data_af_mask_s0[i][MAX_BPC*1+:MAX_BPC] < GH_I |  
                                pixel_data_af_mask_s0[i][MAX_BPC*2+:MAX_BPC] > BL_I   ) ? cnt_err_1[i] + 1 : cnt_err_1[i] ;
                      
        end
    end
end
endgenerate

reg [31:0 ]  cnt_err_1_total_s2 = 0;
wire [31:0] cnt_err_1_total [MAX_PORT_NUM-1:0] ;
//d s1 s2
assign cnt_err_1_total[0] = cnt_err_1[0] ;
generate for(i=1;i<=MAX_PORT_NUM-1;i=i+1)begin
    assign cnt_err_1_total[i] = cnt_err_1_total[i-1] + cnt_err_1[i] ;
end
endgenerate
always@(posedge CLK_I)cnt_err_1_total_s2 <= cnt_err_1_total[MAX_PORT_NUM-1];
reg [31:0 ]  cnt_err_1_total_s2_ff= 0;
always@(posedge CLK_I)begin
    if(RST_I)begin
		cnt_err_1_total_s2_ff <= 0;
    end
    else if(VS_I_d_pos)begin
        cnt_err_1_total_s2_ff <= cnt_err_1_total_s2 ;
    end
end




//L  H  H  qian lan
generate for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
always@(posedge CLK_I)begin
        if(RST_I | VS_I_d_neg)begin
            cnt_err_2[i] <= 0; 
        end    
        else if(de_2)begin//_d ~ s0  
            cnt_err_2[i] <=    (pixel_data_af_mask_s0[i][MAX_BPC*0+:MAX_BPC] > RL_I  |
                                pixel_data_af_mask_s0[i][MAX_BPC*1+:MAX_BPC] < GH_I  | 
                                pixel_data_af_mask_s0[i][MAX_BPC*2+:MAX_BPC] < BH_I   ) ? cnt_err_2[i] + 1 : cnt_err_2[i] ;
                      
        end
    end
end
endgenerate
reg [31:0 ]  cnt_err_2_total_s2 = 0;
wire [31:0] cnt_err_2_total [MAX_PORT_NUM-1:0] ;
//d s1 s2
assign cnt_err_2_total[0] = cnt_err_2[0] ;
generate for(i=1;i<=MAX_PORT_NUM-1;i=i+1)begin
    assign cnt_err_2_total[i] = cnt_err_2_total[i-1] + cnt_err_2[i] ;
end
endgenerate
always@(posedge CLK_I)cnt_err_2_total_s2 <= cnt_err_2_total[MAX_PORT_NUM-1];
reg [31:0 ]  cnt_err_2_total_s2_ff= 0;
always@(posedge CLK_I)begin
    if(RST_I)begin
		cnt_err_2_total_s2_ff <= 0;
    end
    else if(VS_I_d_pos)begin
        cnt_err_2_total_s2_ff <= cnt_err_2_total_s2 ;
    end
end





//L  H  L  green
generate for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
always@(posedge CLK_I)begin
        if(RST_I | VS_I_d_neg)begin
            cnt_err_3[i] <= 0; 
        end    
        else if(de_3)begin//_d ~ s0  
            cnt_err_3[i] <=    (pixel_data_af_mask_s0[i][MAX_BPC*0+:MAX_BPC] > RL_I |
                                pixel_data_af_mask_s0[i][MAX_BPC*1+:MAX_BPC] < GH_I  |  
                                pixel_data_af_mask_s0[i][MAX_BPC*2+:MAX_BPC] > BL_I   ) ? cnt_err_3[i] + 1 : cnt_err_3[i] ;
                      
        end
    end
end
endgenerate
reg [31:0 ]  cnt_err_3_total_s2 = 0;
wire [31:0] cnt_err_3_total [MAX_PORT_NUM-1:0] ;
//d s1 s2
assign cnt_err_3_total[0] = cnt_err_3[0] ;
generate for(i=1;i<=MAX_PORT_NUM-1;i=i+1)begin
    assign cnt_err_3_total[i] = cnt_err_3_total[i-1] + cnt_err_3[i] ;
end
endgenerate
always@(posedge CLK_I)cnt_err_3_total_s2 <= cnt_err_3_total[MAX_PORT_NUM-1];
reg [31:0 ]  cnt_err_3_total_s2_ff= 0;
always@(posedge CLK_I)begin
    if(RST_I)begin
		cnt_err_3_total_s2_ff <= 0;
    end
    else if(VS_I_d_pos)begin
        cnt_err_3_total_s2_ff <= cnt_err_3_total_s2 ;
    end
end







//H  L  H  fenhong
generate for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
always@(posedge CLK_I)begin
        if(RST_I | VS_I_d_neg)begin
            cnt_err_4[i] <= 0; 
        end    
        else if(de_4)begin//_d ~ s0  
            cnt_err_4[i] <=    (pixel_data_af_mask_s0[i][MAX_BPC*0+:MAX_BPC] < RH_I |
                                pixel_data_af_mask_s0[i][MAX_BPC*1+:MAX_BPC] > GL_I |  
                                pixel_data_af_mask_s0[i][MAX_BPC*2+:MAX_BPC] < BH_I   ) ? cnt_err_4[i] + 1 : cnt_err_4[i] ;
                      
        end
    end
end
endgenerate
reg [31:0 ]  cnt_err_4_total_s2 = 0;
wire [31:0] cnt_err_4_total [MAX_PORT_NUM-1:0] ;
//d s1 s2
assign cnt_err_4_total[0] = cnt_err_4[0] ;
generate for(i=1;i<=MAX_PORT_NUM-1;i=i+1)begin
    assign cnt_err_4_total[i] = cnt_err_4_total[i-1] + cnt_err_4[i] ;
end
endgenerate
always@(posedge CLK_I)cnt_err_4_total_s2 <= cnt_err_4_total[MAX_PORT_NUM-1];
reg [31:0 ]  cnt_err_4_total_s2_ff= 0;
always@(posedge CLK_I)begin
    if(RST_I)begin
		cnt_err_4_total_s2_ff <= 0;
    end
    else if(VS_I_d_pos)begin
        cnt_err_4_total_s2_ff <= cnt_err_4_total_s2 ;
    end
end







//H  L  L  red
generate for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
always@(posedge CLK_I)begin
        if(RST_I | VS_I_d_neg)begin   
            cnt_err_5[i] <= 0; 
        end    
        else if(de_5)begin//_d ~ s0  
            cnt_err_5[i] <=    (pixel_data_af_mask_s0[i][MAX_BPC*0+:MAX_BPC] < RH_I |
                                pixel_data_af_mask_s0[i][MAX_BPC*1+:MAX_BPC] > GL_I | 
                                pixel_data_af_mask_s0[i][MAX_BPC*2+:MAX_BPC] > BL_I   ) ? cnt_err_5[i] + 1 : cnt_err_5[i] ;
                      
        end
    end
end
endgenerate
reg [31:0 ]  cnt_err_5_total_s2 = 0;
wire [31:0] cnt_err_5_total [MAX_PORT_NUM-1:0] ;
//d s1 s2
assign cnt_err_5_total[0] = cnt_err_5[0] ;
generate for(i=1;i<=MAX_PORT_NUM-1;i=i+1)begin
    assign cnt_err_5_total[i] = cnt_err_5_total[i-1] + cnt_err_5[i] ;
end
endgenerate
always@(posedge CLK_I)cnt_err_5_total_s2 <= cnt_err_5_total[MAX_PORT_NUM-1];
reg [31:0 ]  cnt_err_5_total_s2_ff= 0;
always@(posedge CLK_I)begin
    if(RST_I)begin
		cnt_err_5_total_s2_ff <= 0;
    end
    else if(VS_I_d_pos)begin
        cnt_err_5_total_s2_ff <= cnt_err_5_total_s2 ;
    end
end







//L  L  H  blue
generate for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
always@(posedge CLK_I)begin
        if(RST_I | VS_I_d_neg)begin   
            cnt_err_6[i] <= 0; 
        end    
        else if(de_6)begin//_d ~ s0  
            cnt_err_6[i] <=    (pixel_data_af_mask_s0[i][MAX_BPC*0+:MAX_BPC] > RL_I |
                                pixel_data_af_mask_s0[i][MAX_BPC*1+:MAX_BPC] > GL_I | 
                                pixel_data_af_mask_s0[i][MAX_BPC*2+:MAX_BPC] < BH_I   ) ? cnt_err_6[i] + 1 : cnt_err_6[i] ;
                      
        end
    end
end
endgenerate
reg [31:0 ]  cnt_err_6_total_s2 = 0;
wire [31:0] cnt_err_6_total [MAX_PORT_NUM-1:0] ;
//d s1 s2
assign cnt_err_6_total[0] = cnt_err_6[0] ;
generate for(i=1;i<=MAX_PORT_NUM-1;i=i+1)begin
    assign cnt_err_6_total[i] = cnt_err_6_total[i-1] + cnt_err_6[i] ;
end
endgenerate
always@(posedge CLK_I)cnt_err_6_total_s2 <= cnt_err_6_total[MAX_PORT_NUM-1];
reg [31:0 ]  cnt_err_6_total_s2_ff= 0;
always@(posedge CLK_I)begin
    if(RST_I)begin
		cnt_err_6_total_s2_ff <= 0;
    end
    else if(VS_I_d_pos)begin
        cnt_err_6_total_s2_ff <= cnt_err_6_total_s2 ;
    end
end








//L  L  L  black
generate for(i=0;i<=MAX_PORT_NUM-1;i=i+1)begin
always@(posedge CLK_I)begin
        if(RST_I | VS_I_d_neg)begin   
            cnt_err_7[i] <= 0; 
        end    
        else if(de_7)begin//_d ~ s0  
            cnt_err_7[i] <=    (pixel_data_af_mask_s0[i][MAX_BPC*0+:MAX_BPC] > RL_I |
                                pixel_data_af_mask_s0[i][MAX_BPC*1+:MAX_BPC] > GL_I | 
                                pixel_data_af_mask_s0[i][MAX_BPC*2+:MAX_BPC] > BL_I   ) ? cnt_err_7[i] + 1 : cnt_err_7[i] ;
                      
        end
    end
end
endgenerate
reg [31:0 ]  cnt_err_7_total_s2 = 0;
wire [31:0] cnt_err_7_total [MAX_PORT_NUM-1:0] ;
//d s1 s2
assign cnt_err_7_total[0] = cnt_err_7[0] ;
generate for(i=1;i<=MAX_PORT_NUM-1;i=i+1)begin
    assign cnt_err_7_total[i] = cnt_err_7_total[i-1] + cnt_err_7[i] ;
end
endgenerate
always@(posedge CLK_I)cnt_err_7_total_s2 <= cnt_err_7_total[MAX_PORT_NUM-1];
reg [31:0 ]  cnt_err_7_total_s2_ff = 0;
always@(posedge CLK_I)begin
    if(RST_I)begin
		cnt_err_7_total_s2_ff <= 0;
    end
    else if(VS_I_d_pos)begin
        cnt_err_7_total_s2_ff <= cnt_err_7_total_s2 ;
    end
end


//generate if(C_ILA_ERR_COUNT_PCLK)begin
//
//ila_err_count ila_err_count_u
//(
//    .clk    (CLK_I ) ,
//    .probe0 ({  DE_I_d ,de_5,de_4 ,de_3,de_2,de_1,de_0}   ) ,
//    .probe1 (  cnt_err_0_total_s2 ) ,
//    .probe2 (  cnt_err_1_total_s2 ) ,
//     .probe3 ( cnt_err_2_total_s2) ,
//     .probe4 (  err_fram_num  ) ,
//     .probe5 (  VS_I_d_pos_s2  ) ,
//     .probe6 (  cnt_err_total_s2_ff ) ,
//     .probe7  ( {ERR_COUNT_FLAG_O , HEIGHT_ERR_FLAG_O , CRC_ERR_FLAG_O   } ),
//    .probe8  ( TARGET_ERR_COUNT_I_reg ),
//    .probe9  ( R_I_d ),
//    .probe10 ( G_I_d ),
//    .probe11 ( B_I_d ),
//    .probe12 (HACTIVE_count ),
//    .probe13 (VACTIVE_count  ) 
//    
//    
//    
//
//
//);
//
//
//
//end
//endgenerate






endmodule






//-----------------------------------------------------------------------------
// Copyright (C) 2009 OutputLogic.com
// This source file may be used and distributed without restriction
// provided that this copyright statement is not removed from the file
// and that any derivative work contains the original copyright notice
// and the associated disclaimer.
// THIS SOURCE FILE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS
// OR IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
// WARRANTIES OF MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.
//-----------------------------------------------------------------------------
// CRC module for
//       data[17:0]
//       crc[17:0]=1+x^2+x^4+x^6+x^9+x^12+x^18;
//
module crc18_rgb(
        input [17:0] data_in,
        input        crc_en,
        output [17:0] crc_out,
        input        rst,
        input        clk);

        reg [17:0] lfsr_q = {18{1'b1}} ,
                   lfsr_c;
        assign crc_out = lfsr_q;
        always @(*) begin
                lfsr_c[0] = lfsr_q[0] ^ lfsr_q[6] ^ lfsr_q[9] ^ lfsr_q[14] ^ lfsr_q[16] ^ data_in[0] ^ data_in[6] ^ data_in[9] ^ data_in[14] ^ data_in[16];
                lfsr_c[1] = lfsr_q[1] ^ lfsr_q[7] ^ lfsr_q[10] ^ lfsr_q[15] ^ lfsr_q[17] ^ data_in[1] ^ data_in[7] ^ data_in[10] ^ data_in[15] ^ data_in[17];
                lfsr_c[2] = lfsr_q[0] ^ lfsr_q[2] ^ lfsr_q[6] ^ lfsr_q[8] ^ lfsr_q[9] ^ lfsr_q[11] ^ lfsr_q[14] ^ data_in[0] ^ data_in[2] ^ data_in[6] ^ data_in[8] ^ data_in[9] ^ data_in[11] ^ data_in[14];
                lfsr_c[3] = lfsr_q[1] ^ lfsr_q[3] ^ lfsr_q[7] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[12] ^ lfsr_q[15] ^ data_in[1] ^ data_in[3] ^ data_in[7] ^ data_in[9] ^ data_in[10] ^ data_in[12] ^ data_in[15];
                lfsr_c[4] = lfsr_q[0] ^ lfsr_q[2] ^ lfsr_q[4] ^ lfsr_q[6] ^ lfsr_q[8] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[13] ^ lfsr_q[14] ^ data_in[0] ^ data_in[2] ^ data_in[4] ^ data_in[6] ^ data_in[8] ^ data_in[9] ^ data_in[10] ^ data_in[11] ^ data_in[13] ^ data_in[14];
                lfsr_c[5] = lfsr_q[1] ^ lfsr_q[3] ^ lfsr_q[5] ^ lfsr_q[7] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[14] ^ lfsr_q[15] ^ data_in[1] ^ data_in[3] ^ data_in[5] ^ data_in[7] ^ data_in[9] ^ data_in[10] ^ data_in[11] ^ data_in[12] ^ data_in[14] ^ data_in[15];
                lfsr_c[6] = lfsr_q[0] ^ lfsr_q[2] ^ lfsr_q[4] ^ lfsr_q[8] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[13] ^ lfsr_q[14] ^ lfsr_q[15] ^ data_in[0] ^ data_in[2] ^ data_in[4] ^ data_in[8] ^ data_in[9] ^ data_in[10] ^ data_in[11] ^ data_in[12] ^ data_in[13] ^ data_in[14] ^ data_in[15];
                lfsr_c[7] = lfsr_q[1] ^ lfsr_q[3] ^ lfsr_q[5] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[13] ^ lfsr_q[14] ^ lfsr_q[15] ^ lfsr_q[16] ^ data_in[1] ^ data_in[3] ^ data_in[5] ^ data_in[9] ^ data_in[10] ^ data_in[11] ^ data_in[12] ^ data_in[13] ^ data_in[14] ^ data_in[15] ^ data_in[16];
                lfsr_c[8] = lfsr_q[2] ^ lfsr_q[4] ^ lfsr_q[6] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[13] ^ lfsr_q[14] ^ lfsr_q[15] ^ lfsr_q[16] ^ lfsr_q[17] ^ data_in[2] ^ data_in[4] ^ data_in[6] ^ data_in[10] ^ data_in[11] ^ data_in[12] ^ data_in[13] ^ data_in[14] ^ data_in[15] ^ data_in[16] ^ data_in[17];
                lfsr_c[9] = lfsr_q[0] ^ lfsr_q[3] ^ lfsr_q[5] ^ lfsr_q[6] ^ lfsr_q[7] ^ lfsr_q[9] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[13] ^ lfsr_q[15] ^ lfsr_q[17] ^ data_in[0] ^ data_in[3] ^ data_in[5] ^ data_in[6] ^ data_in[7] ^ data_in[9] ^ data_in[11] ^ data_in[12] ^ data_in[13] ^ data_in[15] ^ data_in[17];
                lfsr_c[10] = lfsr_q[1] ^ lfsr_q[4] ^ lfsr_q[6] ^ lfsr_q[7] ^ lfsr_q[8] ^ lfsr_q[10] ^ lfsr_q[12] ^ lfsr_q[13] ^ lfsr_q[14] ^ lfsr_q[16] ^ data_in[1] ^ data_in[4] ^ data_in[6] ^ data_in[7] ^ data_in[8] ^ data_in[10] ^ data_in[12] ^ data_in[13] ^ data_in[14] ^ data_in[16];
                lfsr_c[11] = lfsr_q[2] ^ lfsr_q[5] ^ lfsr_q[7] ^ lfsr_q[8] ^ lfsr_q[9] ^ lfsr_q[11] ^ lfsr_q[13] ^ lfsr_q[14] ^ lfsr_q[15] ^ lfsr_q[17] ^ data_in[2] ^ data_in[5] ^ data_in[7] ^ data_in[8] ^ data_in[9] ^ data_in[11] ^ data_in[13] ^ data_in[14] ^ data_in[15] ^ data_in[17];
                lfsr_c[12] = lfsr_q[0] ^ lfsr_q[3] ^ lfsr_q[8] ^ lfsr_q[10] ^ lfsr_q[12] ^ lfsr_q[15] ^ data_in[0] ^ data_in[3] ^ data_in[8] ^ data_in[10] ^ data_in[12] ^ data_in[15];
                lfsr_c[13] = lfsr_q[1] ^ lfsr_q[4] ^ lfsr_q[9] ^ lfsr_q[11] ^ lfsr_q[13] ^ lfsr_q[16] ^ data_in[1] ^ data_in[4] ^ data_in[9] ^ data_in[11] ^ data_in[13] ^ data_in[16];
                lfsr_c[14] = lfsr_q[2] ^ lfsr_q[5] ^ lfsr_q[10] ^ lfsr_q[12] ^ lfsr_q[14] ^ lfsr_q[17] ^ data_in[2] ^ data_in[5] ^ data_in[10] ^ data_in[12] ^ data_in[14] ^ data_in[17];
                lfsr_c[15] = lfsr_q[3] ^ lfsr_q[6] ^ lfsr_q[11] ^ lfsr_q[13] ^ lfsr_q[15] ^ data_in[3] ^ data_in[6] ^ data_in[11] ^ data_in[13] ^ data_in[15];
                lfsr_c[16] = lfsr_q[4] ^ lfsr_q[7] ^ lfsr_q[12] ^ lfsr_q[14] ^ lfsr_q[16] ^ data_in[4] ^ data_in[7] ^ data_in[12] ^ data_in[14] ^ data_in[16];
                lfsr_c[17] = lfsr_q[5] ^ lfsr_q[8] ^ lfsr_q[13] ^ lfsr_q[15] ^ lfsr_q[17] ^ data_in[5] ^ data_in[8] ^ data_in[13] ^ data_in[15] ^ data_in[17];


        end // always

        always @(posedge clk) begin
                if(rst) begin
                        lfsr_q  <= {18{1'b1}};
                end
                else begin
                        lfsr_q  <= crc_en ? lfsr_c : lfsr_q;
                end
        end // always
endmodule // crc



//-----------------------------------------------------------------------------
// Copyright (C) 2009 OutputLogic.com
// This source file may be used and distributed without restriction
// provided that this copyright statement is not removed from the file
// and that any derivative work contains the original copyright notice
// and the associated disclaimer.
// THIS SOURCE FILE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS
// OR IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
// WARRANTIES OF MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.
//-----------------------------------------------------------------------------
// CRC module for
//       data[23:0]
//       crc[23:0]=1+x^1+x^2+x^4+x^5+x^7+x^8+x^10+x^11+x^12+x^16+x^22+x^23+x^24;
//
module crc24_rgb(
        input [23:0] data_in,
        input        crc_en,
        output [23:0] crc_out,
        input        rst,
        input        clk);

        reg [23:0] lfsr_q = {24{1'b1}} ,
                   lfsr_c;
        assign crc_out = lfsr_q;
        always @(*) begin
                lfsr_c[0] = lfsr_q[0] ^ lfsr_q[1] ^ lfsr_q[3] ^ lfsr_q[4] ^ lfsr_q[6] ^ lfsr_q[7] ^ lfsr_q[8] ^ lfsr_q[9] ^ lfsr_q[14] ^ lfsr_q[16] ^ lfsr_q[20] ^ lfsr_q[22] ^ data_in[0] ^ data_in[1] ^ data_in[3] ^ data_in[4] ^ data_in[6] ^ data_in[7] ^ data_in[8] ^ data_in[9] ^ data_in[14] ^ data_in[16] ^ data_in[20] ^ data_in[22];
                lfsr_c[1] = lfsr_q[0] ^ lfsr_q[2] ^ lfsr_q[3] ^ lfsr_q[5] ^ lfsr_q[6] ^ lfsr_q[10] ^ lfsr_q[14] ^ lfsr_q[15] ^ lfsr_q[16] ^ lfsr_q[17] ^ lfsr_q[20] ^ lfsr_q[21] ^ lfsr_q[22] ^ lfsr_q[23] ^ data_in[0] ^ data_in[2] ^ data_in[3] ^ data_in[5] ^ data_in[6] ^ data_in[10] ^ data_in[14] ^ data_in[15] ^ data_in[16] ^ data_in[17] ^ data_in[20] ^ data_in[21] ^ data_in[22] ^ data_in[23];
                lfsr_c[2] = lfsr_q[0] ^ lfsr_q[8] ^ lfsr_q[9] ^ lfsr_q[11] ^ lfsr_q[14] ^ lfsr_q[15] ^ lfsr_q[17] ^ lfsr_q[18] ^ lfsr_q[20] ^ lfsr_q[21] ^ lfsr_q[23] ^ data_in[0] ^ data_in[8] ^ data_in[9] ^ data_in[11] ^ data_in[14] ^ data_in[15] ^ data_in[17] ^ data_in[18] ^ data_in[20] ^ data_in[21] ^ data_in[23];
                lfsr_c[3] = lfsr_q[1] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[12] ^ lfsr_q[15] ^ lfsr_q[16] ^ lfsr_q[18] ^ lfsr_q[19] ^ lfsr_q[21] ^ lfsr_q[22] ^ data_in[1] ^ data_in[9] ^ data_in[10] ^ data_in[12] ^ data_in[15] ^ data_in[16] ^ data_in[18] ^ data_in[19] ^ data_in[21] ^ data_in[22];
                lfsr_c[4] = lfsr_q[0] ^ lfsr_q[1] ^ lfsr_q[2] ^ lfsr_q[3] ^ lfsr_q[4] ^ lfsr_q[6] ^ lfsr_q[7] ^ lfsr_q[8] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[13] ^ lfsr_q[14] ^ lfsr_q[17] ^ lfsr_q[19] ^ lfsr_q[23] ^ data_in[0] ^ data_in[1] ^ data_in[2] ^ data_in[3] ^ data_in[4] ^ data_in[6] ^ data_in[7] ^ data_in[8] ^ data_in[9] ^ data_in[10] ^ data_in[11] ^ data_in[13] ^ data_in[14] ^ data_in[17] ^ data_in[19] ^ data_in[23];
                lfsr_c[5] = lfsr_q[0] ^ lfsr_q[2] ^ lfsr_q[5] ^ lfsr_q[6] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[15] ^ lfsr_q[16] ^ lfsr_q[18] ^ lfsr_q[22] ^ data_in[0] ^ data_in[2] ^ data_in[5] ^ data_in[6] ^ data_in[10] ^ data_in[11] ^ data_in[12] ^ data_in[15] ^ data_in[16] ^ data_in[18] ^ data_in[22];
                lfsr_c[6] = lfsr_q[1] ^ lfsr_q[3] ^ lfsr_q[6] ^ lfsr_q[7] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[13] ^ lfsr_q[16] ^ lfsr_q[17] ^ lfsr_q[19] ^ lfsr_q[23] ^ data_in[1] ^ data_in[3] ^ data_in[6] ^ data_in[7] ^ data_in[11] ^ data_in[12] ^ data_in[13] ^ data_in[16] ^ data_in[17] ^ data_in[19] ^ data_in[23];
                lfsr_c[7] = lfsr_q[0] ^ lfsr_q[1] ^ lfsr_q[2] ^ lfsr_q[3] ^ lfsr_q[6] ^ lfsr_q[9] ^ lfsr_q[12] ^ lfsr_q[13] ^ lfsr_q[16] ^ lfsr_q[17] ^ lfsr_q[18] ^ lfsr_q[22] ^ data_in[0] ^ data_in[1] ^ data_in[2] ^ data_in[3] ^ data_in[6] ^ data_in[9] ^ data_in[12] ^ data_in[13] ^ data_in[16] ^ data_in[17] ^ data_in[18] ^ data_in[22];
                lfsr_c[8] = lfsr_q[0] ^ lfsr_q[2] ^ lfsr_q[6] ^ lfsr_q[8] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[13] ^ lfsr_q[16] ^ lfsr_q[17] ^ lfsr_q[18] ^ lfsr_q[19] ^ lfsr_q[20] ^ lfsr_q[22] ^ lfsr_q[23] ^ data_in[0] ^ data_in[2] ^ data_in[6] ^ data_in[8] ^ data_in[9] ^ data_in[10] ^ data_in[13] ^ data_in[16] ^ data_in[17] ^ data_in[18] ^ data_in[19] ^ data_in[20] ^ data_in[22] ^ data_in[23];
                lfsr_c[9] = lfsr_q[1] ^ lfsr_q[3] ^ lfsr_q[7] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[14] ^ lfsr_q[17] ^ lfsr_q[18] ^ lfsr_q[19] ^ lfsr_q[20] ^ lfsr_q[21] ^ lfsr_q[23] ^ data_in[1] ^ data_in[3] ^ data_in[7] ^ data_in[9] ^ data_in[10] ^ data_in[11] ^ data_in[14] ^ data_in[17] ^ data_in[18] ^ data_in[19] ^ data_in[20] ^ data_in[21] ^ data_in[23];
                lfsr_c[10] = lfsr_q[0] ^ lfsr_q[1] ^ lfsr_q[2] ^ lfsr_q[3] ^ lfsr_q[6] ^ lfsr_q[7] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[14] ^ lfsr_q[15] ^ lfsr_q[16] ^ lfsr_q[18] ^ lfsr_q[19] ^ lfsr_q[21] ^ data_in[0] ^ data_in[1] ^ data_in[2] ^ data_in[3] ^ data_in[6] ^ data_in[7] ^ data_in[9] ^ data_in[10] ^ data_in[11] ^ data_in[12] ^ data_in[14] ^ data_in[15] ^ data_in[16] ^ data_in[18] ^ data_in[19] ^ data_in[21];
                lfsr_c[11] = lfsr_q[0] ^ lfsr_q[2] ^ lfsr_q[6] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[13] ^ lfsr_q[14] ^ lfsr_q[15] ^ lfsr_q[17] ^ lfsr_q[19] ^ data_in[0] ^ data_in[2] ^ data_in[6] ^ data_in[9] ^ data_in[10] ^ data_in[11] ^ data_in[12] ^ data_in[13] ^ data_in[14] ^ data_in[15] ^ data_in[17] ^ data_in[19];
                lfsr_c[12] = lfsr_q[0] ^ lfsr_q[4] ^ lfsr_q[6] ^ lfsr_q[8] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[13] ^ lfsr_q[15] ^ lfsr_q[18] ^ lfsr_q[22] ^ data_in[0] ^ data_in[4] ^ data_in[6] ^ data_in[8] ^ data_in[9] ^ data_in[10] ^ data_in[11] ^ data_in[12] ^ data_in[13] ^ data_in[15] ^ data_in[18] ^ data_in[22];
                lfsr_c[13] = lfsr_q[1] ^ lfsr_q[5] ^ lfsr_q[7] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[13] ^ lfsr_q[14] ^ lfsr_q[16] ^ lfsr_q[19] ^ lfsr_q[23] ^ data_in[1] ^ data_in[5] ^ data_in[7] ^ data_in[9] ^ data_in[10] ^ data_in[11] ^ data_in[12] ^ data_in[13] ^ data_in[14] ^ data_in[16] ^ data_in[19] ^ data_in[23];
                lfsr_c[14] = lfsr_q[2] ^ lfsr_q[6] ^ lfsr_q[8] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[13] ^ lfsr_q[14] ^ lfsr_q[15] ^ lfsr_q[17] ^ lfsr_q[20] ^ data_in[2] ^ data_in[6] ^ data_in[8] ^ data_in[10] ^ data_in[11] ^ data_in[12] ^ data_in[13] ^ data_in[14] ^ data_in[15] ^ data_in[17] ^ data_in[20];
                lfsr_c[15] = lfsr_q[3] ^ lfsr_q[7] ^ lfsr_q[9] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[13] ^ lfsr_q[14] ^ lfsr_q[15] ^ lfsr_q[16] ^ lfsr_q[18] ^ lfsr_q[21] ^ data_in[3] ^ data_in[7] ^ data_in[9] ^ data_in[11] ^ data_in[12] ^ data_in[13] ^ data_in[14] ^ data_in[15] ^ data_in[16] ^ data_in[18] ^ data_in[21];
                lfsr_c[16] = lfsr_q[0] ^ lfsr_q[1] ^ lfsr_q[3] ^ lfsr_q[6] ^ lfsr_q[7] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[12] ^ lfsr_q[13] ^ lfsr_q[15] ^ lfsr_q[17] ^ lfsr_q[19] ^ lfsr_q[20] ^ data_in[0] ^ data_in[1] ^ data_in[3] ^ data_in[6] ^ data_in[7] ^ data_in[9] ^ data_in[10] ^ data_in[12] ^ data_in[13] ^ data_in[15] ^ data_in[17] ^ data_in[19] ^ data_in[20];
                lfsr_c[17] = lfsr_q[1] ^ lfsr_q[2] ^ lfsr_q[4] ^ lfsr_q[7] ^ lfsr_q[8] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[13] ^ lfsr_q[14] ^ lfsr_q[16] ^ lfsr_q[18] ^ lfsr_q[20] ^ lfsr_q[21] ^ data_in[1] ^ data_in[2] ^ data_in[4] ^ data_in[7] ^ data_in[8] ^ data_in[10] ^ data_in[11] ^ data_in[13] ^ data_in[14] ^ data_in[16] ^ data_in[18] ^ data_in[20] ^ data_in[21];
                lfsr_c[18] = lfsr_q[2] ^ lfsr_q[3] ^ lfsr_q[5] ^ lfsr_q[8] ^ lfsr_q[9] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[14] ^ lfsr_q[15] ^ lfsr_q[17] ^ lfsr_q[19] ^ lfsr_q[21] ^ lfsr_q[22] ^ data_in[2] ^ data_in[3] ^ data_in[5] ^ data_in[8] ^ data_in[9] ^ data_in[11] ^ data_in[12] ^ data_in[14] ^ data_in[15] ^ data_in[17] ^ data_in[19] ^ data_in[21] ^ data_in[22];
                lfsr_c[19] = lfsr_q[3] ^ lfsr_q[4] ^ lfsr_q[6] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[12] ^ lfsr_q[13] ^ lfsr_q[15] ^ lfsr_q[16] ^ lfsr_q[18] ^ lfsr_q[20] ^ lfsr_q[22] ^ lfsr_q[23] ^ data_in[3] ^ data_in[4] ^ data_in[6] ^ data_in[9] ^ data_in[10] ^ data_in[12] ^ data_in[13] ^ data_in[15] ^ data_in[16] ^ data_in[18] ^ data_in[20] ^ data_in[22] ^ data_in[23];
                lfsr_c[20] = lfsr_q[4] ^ lfsr_q[5] ^ lfsr_q[7] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[13] ^ lfsr_q[14] ^ lfsr_q[16] ^ lfsr_q[17] ^ lfsr_q[19] ^ lfsr_q[21] ^ lfsr_q[23] ^ data_in[4] ^ data_in[5] ^ data_in[7] ^ data_in[10] ^ data_in[11] ^ data_in[13] ^ data_in[14] ^ data_in[16] ^ data_in[17] ^ data_in[19] ^ data_in[21] ^ data_in[23];
                lfsr_c[21] = lfsr_q[5] ^ lfsr_q[6] ^ lfsr_q[8] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[14] ^ lfsr_q[15] ^ lfsr_q[17] ^ lfsr_q[18] ^ lfsr_q[20] ^ lfsr_q[22] ^ data_in[5] ^ data_in[6] ^ data_in[8] ^ data_in[11] ^ data_in[12] ^ data_in[14] ^ data_in[15] ^ data_in[17] ^ data_in[18] ^ data_in[20] ^ data_in[22];
                lfsr_c[22] = lfsr_q[0] ^ lfsr_q[1] ^ lfsr_q[3] ^ lfsr_q[4] ^ lfsr_q[8] ^ lfsr_q[12] ^ lfsr_q[13] ^ lfsr_q[14] ^ lfsr_q[15] ^ lfsr_q[18] ^ lfsr_q[19] ^ lfsr_q[20] ^ lfsr_q[21] ^ lfsr_q[22] ^ lfsr_q[23] ^ data_in[0] ^ data_in[1] ^ data_in[3] ^ data_in[4] ^ data_in[8] ^ data_in[12] ^ data_in[13] ^ data_in[14] ^ data_in[15] ^ data_in[18] ^ data_in[19] ^ data_in[20] ^ data_in[21] ^ data_in[22] ^ data_in[23];
                lfsr_c[23] = lfsr_q[0] ^ lfsr_q[2] ^ lfsr_q[3] ^ lfsr_q[5] ^ lfsr_q[6] ^ lfsr_q[7] ^ lfsr_q[8] ^ lfsr_q[13] ^ lfsr_q[15] ^ lfsr_q[19] ^ lfsr_q[21] ^ lfsr_q[23] ^ data_in[0] ^ data_in[2] ^ data_in[3] ^ data_in[5] ^ data_in[6] ^ data_in[7] ^ data_in[8] ^ data_in[13] ^ data_in[15] ^ data_in[19] ^ data_in[21] ^ data_in[23];


        end // always

        always @(posedge clk) begin
                if(rst) begin
                        lfsr_q  <= {24{1'b1}};
                end
                else begin
                        lfsr_q  <= crc_en ? lfsr_c : lfsr_q;
                end
        end // always
endmodule // crc

//-----------------------------------------------------------------------------
// Copyright (C) 2009 OutputLogic.com
// This source file may be used and distributed without restriction
// provided that this copyright statement is not removed from the file
// and that any derivative work contains the original copyright notice
// and the associated disclaimer.
// THIS SOURCE FILE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS
// OR IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
// WARRANTIES OF MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.
//-----------------------------------------------------------------------------
// CRC module for
//       data[29:0]
//       crc[29:0]=1+x^1+x^2+x^4+x^5+x^7+x^8+x^10+x^11+x^12+x^16+x^22+x^23+x^26+x^30;
//
module crc30_rgb(
        input [29:0] data_in,
        input        crc_en,
        output [29:0] crc_out,
        input        rst,
        input        clk);

        reg [29:0] lfsr_q = {30{1'b1}} ,
                   lfsr_c;
        assign crc_out = lfsr_q;
        always @(*) begin
                lfsr_c[0] = lfsr_q[0] ^ lfsr_q[4] ^ lfsr_q[7] ^ lfsr_q[12] ^ lfsr_q[15] ^ lfsr_q[16] ^ lfsr_q[19] ^ lfsr_q[20] ^ lfsr_q[21] ^ lfsr_q[22] ^ lfsr_q[23] ^ lfsr_q[24] ^ lfsr_q[25] ^ lfsr_q[27] ^ lfsr_q[29] ^ data_in[0] ^ data_in[4] ^ data_in[7] ^ data_in[12] ^ data_in[15] ^ data_in[16] ^ data_in[19] ^ data_in[20] ^ data_in[21] ^ data_in[22] ^ data_in[23] ^ data_in[24] ^ data_in[25] ^ data_in[27] ^ data_in[29];
                lfsr_c[1] = lfsr_q[0] ^ lfsr_q[1] ^ lfsr_q[4] ^ lfsr_q[5] ^ lfsr_q[7] ^ lfsr_q[8] ^ lfsr_q[12] ^ lfsr_q[13] ^ lfsr_q[15] ^ lfsr_q[17] ^ lfsr_q[19] ^ lfsr_q[26] ^ lfsr_q[27] ^ lfsr_q[28] ^ lfsr_q[29] ^ data_in[0] ^ data_in[1] ^ data_in[4] ^ data_in[5] ^ data_in[7] ^ data_in[8] ^ data_in[12] ^ data_in[13] ^ data_in[15] ^ data_in[17] ^ data_in[19] ^ data_in[26] ^ data_in[27] ^ data_in[28] ^ data_in[29];
                lfsr_c[2] = lfsr_q[0] ^ lfsr_q[1] ^ lfsr_q[2] ^ lfsr_q[4] ^ lfsr_q[5] ^ lfsr_q[6] ^ lfsr_q[7] ^ lfsr_q[8] ^ lfsr_q[9] ^ lfsr_q[12] ^ lfsr_q[13] ^ lfsr_q[14] ^ lfsr_q[15] ^ lfsr_q[18] ^ lfsr_q[19] ^ lfsr_q[21] ^ lfsr_q[22] ^ lfsr_q[23] ^ lfsr_q[24] ^ lfsr_q[25] ^ lfsr_q[28] ^ data_in[0] ^ data_in[1] ^ data_in[2] ^ data_in[4] ^ data_in[5] ^ data_in[6] ^ data_in[7] ^ data_in[8] ^ data_in[9] ^ data_in[12] ^ data_in[13] ^ data_in[14] ^ data_in[15] ^ data_in[18] ^ data_in[19] ^ data_in[21] ^ data_in[22] ^ data_in[23] ^ data_in[24] ^ data_in[25] ^ data_in[28];
                lfsr_c[3] = lfsr_q[1] ^ lfsr_q[2] ^ lfsr_q[3] ^ lfsr_q[5] ^ lfsr_q[6] ^ lfsr_q[7] ^ lfsr_q[8] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[13] ^ lfsr_q[14] ^ lfsr_q[15] ^ lfsr_q[16] ^ lfsr_q[19] ^ lfsr_q[20] ^ lfsr_q[22] ^ lfsr_q[23] ^ lfsr_q[24] ^ lfsr_q[25] ^ lfsr_q[26] ^ lfsr_q[29] ^ data_in[1] ^ data_in[2] ^ data_in[3] ^ data_in[5] ^ data_in[6] ^ data_in[7] ^ data_in[8] ^ data_in[9] ^ data_in[10] ^ data_in[13] ^ data_in[14] ^ data_in[15] ^ data_in[16] ^ data_in[19] ^ data_in[20] ^ data_in[22] ^ data_in[23] ^ data_in[24] ^ data_in[25] ^ data_in[26] ^ data_in[29];
                lfsr_c[4] = lfsr_q[0] ^ lfsr_q[2] ^ lfsr_q[3] ^ lfsr_q[6] ^ lfsr_q[8] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[14] ^ lfsr_q[17] ^ lfsr_q[19] ^ lfsr_q[22] ^ lfsr_q[26] ^ lfsr_q[29] ^ data_in[0] ^ data_in[2] ^ data_in[3] ^ data_in[6] ^ data_in[8] ^ data_in[9] ^ data_in[10] ^ data_in[11] ^ data_in[12] ^ data_in[14] ^ data_in[17] ^ data_in[19] ^ data_in[22] ^ data_in[26] ^ data_in[29];
                lfsr_c[5] = lfsr_q[0] ^ lfsr_q[1] ^ lfsr_q[3] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[13] ^ lfsr_q[16] ^ lfsr_q[18] ^ lfsr_q[19] ^ lfsr_q[21] ^ lfsr_q[22] ^ lfsr_q[24] ^ lfsr_q[25] ^ lfsr_q[29] ^ data_in[0] ^ data_in[1] ^ data_in[3] ^ data_in[9] ^ data_in[10] ^ data_in[11] ^ data_in[13] ^ data_in[16] ^ data_in[18] ^ data_in[19] ^ data_in[21] ^ data_in[22] ^ data_in[24] ^ data_in[25] ^ data_in[29];
                lfsr_c[6] = lfsr_q[1] ^ lfsr_q[2] ^ lfsr_q[4] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[14] ^ lfsr_q[17] ^ lfsr_q[19] ^ lfsr_q[20] ^ lfsr_q[22] ^ lfsr_q[23] ^ lfsr_q[25] ^ lfsr_q[26] ^ data_in[1] ^ data_in[2] ^ data_in[4] ^ data_in[10] ^ data_in[11] ^ data_in[12] ^ data_in[14] ^ data_in[17] ^ data_in[19] ^ data_in[20] ^ data_in[22] ^ data_in[23] ^ data_in[25] ^ data_in[26];
                lfsr_c[7] = lfsr_q[0] ^ lfsr_q[2] ^ lfsr_q[3] ^ lfsr_q[4] ^ lfsr_q[5] ^ lfsr_q[7] ^ lfsr_q[11] ^ lfsr_q[13] ^ lfsr_q[16] ^ lfsr_q[18] ^ lfsr_q[19] ^ lfsr_q[22] ^ lfsr_q[25] ^ lfsr_q[26] ^ lfsr_q[29] ^ data_in[0] ^ data_in[2] ^ data_in[3] ^ data_in[4] ^ data_in[5] ^ data_in[7] ^ data_in[11] ^ data_in[13] ^ data_in[16] ^ data_in[18] ^ data_in[19] ^ data_in[22] ^ data_in[25] ^ data_in[26] ^ data_in[29];
                lfsr_c[8] = lfsr_q[0] ^ lfsr_q[1] ^ lfsr_q[3] ^ lfsr_q[5] ^ lfsr_q[6] ^ lfsr_q[7] ^ lfsr_q[8] ^ lfsr_q[14] ^ lfsr_q[15] ^ lfsr_q[16] ^ lfsr_q[17] ^ lfsr_q[21] ^ lfsr_q[22] ^ lfsr_q[24] ^ lfsr_q[25] ^ lfsr_q[26] ^ lfsr_q[29] ^ data_in[0] ^ data_in[1] ^ data_in[3] ^ data_in[5] ^ data_in[6] ^ data_in[7] ^ data_in[8] ^ data_in[14] ^ data_in[15] ^ data_in[16] ^ data_in[17] ^ data_in[21] ^ data_in[22] ^ data_in[24] ^ data_in[25] ^ data_in[26] ^ data_in[29];
                lfsr_c[9] = lfsr_q[1] ^ lfsr_q[2] ^ lfsr_q[4] ^ lfsr_q[6] ^ lfsr_q[7] ^ lfsr_q[8] ^ lfsr_q[9] ^ lfsr_q[15] ^ lfsr_q[16] ^ lfsr_q[17] ^ lfsr_q[18] ^ lfsr_q[22] ^ lfsr_q[23] ^ lfsr_q[25] ^ lfsr_q[26] ^ lfsr_q[27] ^ data_in[1] ^ data_in[2] ^ data_in[4] ^ data_in[6] ^ data_in[7] ^ data_in[8] ^ data_in[9] ^ data_in[15] ^ data_in[16] ^ data_in[17] ^ data_in[18] ^ data_in[22] ^ data_in[23] ^ data_in[25] ^ data_in[26] ^ data_in[27];
                lfsr_c[10] = lfsr_q[0] ^ lfsr_q[2] ^ lfsr_q[3] ^ lfsr_q[4] ^ lfsr_q[5] ^ lfsr_q[8] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[12] ^ lfsr_q[15] ^ lfsr_q[17] ^ lfsr_q[18] ^ lfsr_q[20] ^ lfsr_q[21] ^ lfsr_q[22] ^ lfsr_q[25] ^ lfsr_q[26] ^ lfsr_q[28] ^ lfsr_q[29] ^ data_in[0] ^ data_in[2] ^ data_in[3] ^ data_in[4] ^ data_in[5] ^ data_in[8] ^ data_in[9] ^ data_in[10] ^ data_in[12] ^ data_in[15] ^ data_in[17] ^ data_in[18] ^ data_in[20] ^ data_in[21] ^ data_in[22] ^ data_in[25] ^ data_in[26] ^ data_in[28] ^ data_in[29];
                lfsr_c[11] = lfsr_q[0] ^ lfsr_q[1] ^ lfsr_q[3] ^ lfsr_q[5] ^ lfsr_q[6] ^ lfsr_q[7] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[13] ^ lfsr_q[15] ^ lfsr_q[18] ^ lfsr_q[20] ^ lfsr_q[24] ^ lfsr_q[25] ^ lfsr_q[26] ^ data_in[0] ^ data_in[1] ^ data_in[3] ^ data_in[5] ^ data_in[6] ^ data_in[7] ^ data_in[9] ^ data_in[10] ^ data_in[11] ^ data_in[12] ^ data_in[13] ^ data_in[15] ^ data_in[18] ^ data_in[20] ^ data_in[24] ^ data_in[25] ^ data_in[26];
                lfsr_c[12] = lfsr_q[0] ^ lfsr_q[1] ^ lfsr_q[2] ^ lfsr_q[6] ^ lfsr_q[8] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[13] ^ lfsr_q[14] ^ lfsr_q[15] ^ lfsr_q[20] ^ lfsr_q[22] ^ lfsr_q[23] ^ lfsr_q[24] ^ lfsr_q[26] ^ lfsr_q[29] ^ data_in[0] ^ data_in[1] ^ data_in[2] ^ data_in[6] ^ data_in[8] ^ data_in[10] ^ data_in[11] ^ data_in[13] ^ data_in[14] ^ data_in[15] ^ data_in[20] ^ data_in[22] ^ data_in[23] ^ data_in[24] ^ data_in[26] ^ data_in[29];
                lfsr_c[13] = lfsr_q[1] ^ lfsr_q[2] ^ lfsr_q[3] ^ lfsr_q[7] ^ lfsr_q[9] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[14] ^ lfsr_q[15] ^ lfsr_q[16] ^ lfsr_q[21] ^ lfsr_q[23] ^ lfsr_q[24] ^ lfsr_q[25] ^ lfsr_q[27] ^ data_in[1] ^ data_in[2] ^ data_in[3] ^ data_in[7] ^ data_in[9] ^ data_in[11] ^ data_in[12] ^ data_in[14] ^ data_in[15] ^ data_in[16] ^ data_in[21] ^ data_in[23] ^ data_in[24] ^ data_in[25] ^ data_in[27];
                lfsr_c[14] = lfsr_q[2] ^ lfsr_q[3] ^ lfsr_q[4] ^ lfsr_q[8] ^ lfsr_q[10] ^ lfsr_q[12] ^ lfsr_q[13] ^ lfsr_q[15] ^ lfsr_q[16] ^ lfsr_q[17] ^ lfsr_q[22] ^ lfsr_q[24] ^ lfsr_q[25] ^ lfsr_q[26] ^ lfsr_q[28] ^ data_in[2] ^ data_in[3] ^ data_in[4] ^ data_in[8] ^ data_in[10] ^ data_in[12] ^ data_in[13] ^ data_in[15] ^ data_in[16] ^ data_in[17] ^ data_in[22] ^ data_in[24] ^ data_in[25] ^ data_in[26] ^ data_in[28];
                lfsr_c[15] = lfsr_q[3] ^ lfsr_q[4] ^ lfsr_q[5] ^ lfsr_q[9] ^ lfsr_q[11] ^ lfsr_q[13] ^ lfsr_q[14] ^ lfsr_q[16] ^ lfsr_q[17] ^ lfsr_q[18] ^ lfsr_q[23] ^ lfsr_q[25] ^ lfsr_q[26] ^ lfsr_q[27] ^ lfsr_q[29] ^ data_in[3] ^ data_in[4] ^ data_in[5] ^ data_in[9] ^ data_in[11] ^ data_in[13] ^ data_in[14] ^ data_in[16] ^ data_in[17] ^ data_in[18] ^ data_in[23] ^ data_in[25] ^ data_in[26] ^ data_in[27] ^ data_in[29];
                lfsr_c[16] = lfsr_q[0] ^ lfsr_q[5] ^ lfsr_q[6] ^ lfsr_q[7] ^ lfsr_q[10] ^ lfsr_q[14] ^ lfsr_q[16] ^ lfsr_q[17] ^ lfsr_q[18] ^ lfsr_q[20] ^ lfsr_q[21] ^ lfsr_q[22] ^ lfsr_q[23] ^ lfsr_q[25] ^ lfsr_q[26] ^ lfsr_q[28] ^ lfsr_q[29] ^ data_in[0] ^ data_in[5] ^ data_in[6] ^ data_in[7] ^ data_in[10] ^ data_in[14] ^ data_in[16] ^ data_in[17] ^ data_in[18] ^ data_in[20] ^ data_in[21] ^ data_in[22] ^ data_in[23] ^ data_in[25] ^ data_in[26] ^ data_in[28] ^ data_in[29];
                lfsr_c[17] = lfsr_q[1] ^ lfsr_q[6] ^ lfsr_q[7] ^ lfsr_q[8] ^ lfsr_q[11] ^ lfsr_q[15] ^ lfsr_q[17] ^ lfsr_q[18] ^ lfsr_q[19] ^ lfsr_q[21] ^ lfsr_q[22] ^ lfsr_q[23] ^ lfsr_q[24] ^ lfsr_q[26] ^ lfsr_q[27] ^ lfsr_q[29] ^ data_in[1] ^ data_in[6] ^ data_in[7] ^ data_in[8] ^ data_in[11] ^ data_in[15] ^ data_in[17] ^ data_in[18] ^ data_in[19] ^ data_in[21] ^ data_in[22] ^ data_in[23] ^ data_in[24] ^ data_in[26] ^ data_in[27] ^ data_in[29];
                lfsr_c[18] = lfsr_q[2] ^ lfsr_q[7] ^ lfsr_q[8] ^ lfsr_q[9] ^ lfsr_q[12] ^ lfsr_q[16] ^ lfsr_q[18] ^ lfsr_q[19] ^ lfsr_q[20] ^ lfsr_q[22] ^ lfsr_q[23] ^ lfsr_q[24] ^ lfsr_q[25] ^ lfsr_q[27] ^ lfsr_q[28] ^ data_in[2] ^ data_in[7] ^ data_in[8] ^ data_in[9] ^ data_in[12] ^ data_in[16] ^ data_in[18] ^ data_in[19] ^ data_in[20] ^ data_in[22] ^ data_in[23] ^ data_in[24] ^ data_in[25] ^ data_in[27] ^ data_in[28];
                lfsr_c[19] = lfsr_q[3] ^ lfsr_q[8] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[13] ^ lfsr_q[17] ^ lfsr_q[19] ^ lfsr_q[20] ^ lfsr_q[21] ^ lfsr_q[23] ^ lfsr_q[24] ^ lfsr_q[25] ^ lfsr_q[26] ^ lfsr_q[28] ^ lfsr_q[29] ^ data_in[3] ^ data_in[8] ^ data_in[9] ^ data_in[10] ^ data_in[13] ^ data_in[17] ^ data_in[19] ^ data_in[20] ^ data_in[21] ^ data_in[23] ^ data_in[24] ^ data_in[25] ^ data_in[26] ^ data_in[28] ^ data_in[29];
                lfsr_c[20] = lfsr_q[4] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[14] ^ lfsr_q[18] ^ lfsr_q[20] ^ lfsr_q[21] ^ lfsr_q[22] ^ lfsr_q[24] ^ lfsr_q[25] ^ lfsr_q[26] ^ lfsr_q[27] ^ lfsr_q[29] ^ data_in[4] ^ data_in[9] ^ data_in[10] ^ data_in[11] ^ data_in[14] ^ data_in[18] ^ data_in[20] ^ data_in[21] ^ data_in[22] ^ data_in[24] ^ data_in[25] ^ data_in[26] ^ data_in[27] ^ data_in[29];
                lfsr_c[21] = lfsr_q[5] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[15] ^ lfsr_q[19] ^ lfsr_q[21] ^ lfsr_q[22] ^ lfsr_q[23] ^ lfsr_q[25] ^ lfsr_q[26] ^ lfsr_q[27] ^ lfsr_q[28] ^ data_in[5] ^ data_in[10] ^ data_in[11] ^ data_in[12] ^ data_in[15] ^ data_in[19] ^ data_in[21] ^ data_in[22] ^ data_in[23] ^ data_in[25] ^ data_in[26] ^ data_in[27] ^ data_in[28];
                lfsr_c[22] = lfsr_q[0] ^ lfsr_q[4] ^ lfsr_q[6] ^ lfsr_q[7] ^ lfsr_q[11] ^ lfsr_q[13] ^ lfsr_q[15] ^ lfsr_q[19] ^ lfsr_q[21] ^ lfsr_q[25] ^ lfsr_q[26] ^ lfsr_q[28] ^ data_in[0] ^ data_in[4] ^ data_in[6] ^ data_in[7] ^ data_in[11] ^ data_in[13] ^ data_in[15] ^ data_in[19] ^ data_in[21] ^ data_in[25] ^ data_in[26] ^ data_in[28];
                lfsr_c[23] = lfsr_q[0] ^ lfsr_q[1] ^ lfsr_q[4] ^ lfsr_q[5] ^ lfsr_q[8] ^ lfsr_q[14] ^ lfsr_q[15] ^ lfsr_q[19] ^ lfsr_q[21] ^ lfsr_q[23] ^ lfsr_q[24] ^ lfsr_q[25] ^ lfsr_q[26] ^ data_in[0] ^ data_in[1] ^ data_in[4] ^ data_in[5] ^ data_in[8] ^ data_in[14] ^ data_in[15] ^ data_in[19] ^ data_in[21] ^ data_in[23] ^ data_in[24] ^ data_in[25] ^ data_in[26];
                lfsr_c[24] = lfsr_q[1] ^ lfsr_q[2] ^ lfsr_q[5] ^ lfsr_q[6] ^ lfsr_q[9] ^ lfsr_q[15] ^ lfsr_q[16] ^ lfsr_q[20] ^ lfsr_q[22] ^ lfsr_q[24] ^ lfsr_q[25] ^ lfsr_q[26] ^ lfsr_q[27] ^ data_in[1] ^ data_in[2] ^ data_in[5] ^ data_in[6] ^ data_in[9] ^ data_in[15] ^ data_in[16] ^ data_in[20] ^ data_in[22] ^ data_in[24] ^ data_in[25] ^ data_in[26] ^ data_in[27];
                lfsr_c[25] = lfsr_q[2] ^ lfsr_q[3] ^ lfsr_q[6] ^ lfsr_q[7] ^ lfsr_q[10] ^ lfsr_q[16] ^ lfsr_q[17] ^ lfsr_q[21] ^ lfsr_q[23] ^ lfsr_q[25] ^ lfsr_q[26] ^ lfsr_q[27] ^ lfsr_q[28] ^ data_in[2] ^ data_in[3] ^ data_in[6] ^ data_in[7] ^ data_in[10] ^ data_in[16] ^ data_in[17] ^ data_in[21] ^ data_in[23] ^ data_in[25] ^ data_in[26] ^ data_in[27] ^ data_in[28];
                lfsr_c[26] = lfsr_q[0] ^ lfsr_q[3] ^ lfsr_q[8] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[15] ^ lfsr_q[16] ^ lfsr_q[17] ^ lfsr_q[18] ^ lfsr_q[19] ^ lfsr_q[20] ^ lfsr_q[21] ^ lfsr_q[23] ^ lfsr_q[25] ^ lfsr_q[26] ^ lfsr_q[28] ^ data_in[0] ^ data_in[3] ^ data_in[8] ^ data_in[11] ^ data_in[12] ^ data_in[15] ^ data_in[16] ^ data_in[17] ^ data_in[18] ^ data_in[19] ^ data_in[20] ^ data_in[21] ^ data_in[23] ^ data_in[25] ^ data_in[26] ^ data_in[28];
                lfsr_c[27] = lfsr_q[1] ^ lfsr_q[4] ^ lfsr_q[9] ^ lfsr_q[12] ^ lfsr_q[13] ^ lfsr_q[16] ^ lfsr_q[17] ^ lfsr_q[18] ^ lfsr_q[19] ^ lfsr_q[20] ^ lfsr_q[21] ^ lfsr_q[22] ^ lfsr_q[24] ^ lfsr_q[26] ^ lfsr_q[27] ^ lfsr_q[29] ^ data_in[1] ^ data_in[4] ^ data_in[9] ^ data_in[12] ^ data_in[13] ^ data_in[16] ^ data_in[17] ^ data_in[18] ^ data_in[19] ^ data_in[20] ^ data_in[21] ^ data_in[22] ^ data_in[24] ^ data_in[26] ^ data_in[27] ^ data_in[29];
                lfsr_c[28] = lfsr_q[2] ^ lfsr_q[5] ^ lfsr_q[10] ^ lfsr_q[13] ^ lfsr_q[14] ^ lfsr_q[17] ^ lfsr_q[18] ^ lfsr_q[19] ^ lfsr_q[20] ^ lfsr_q[21] ^ lfsr_q[22] ^ lfsr_q[23] ^ lfsr_q[25] ^ lfsr_q[27] ^ lfsr_q[28] ^ data_in[2] ^ data_in[5] ^ data_in[10] ^ data_in[13] ^ data_in[14] ^ data_in[17] ^ data_in[18] ^ data_in[19] ^ data_in[20] ^ data_in[21] ^ data_in[22] ^ data_in[23] ^ data_in[25] ^ data_in[27] ^ data_in[28];
                lfsr_c[29] = lfsr_q[3] ^ lfsr_q[6] ^ lfsr_q[11] ^ lfsr_q[14] ^ lfsr_q[15] ^ lfsr_q[18] ^ lfsr_q[19] ^ lfsr_q[20] ^ lfsr_q[21] ^ lfsr_q[22] ^ lfsr_q[23] ^ lfsr_q[24] ^ lfsr_q[26] ^ lfsr_q[28] ^ lfsr_q[29] ^ data_in[3] ^ data_in[6] ^ data_in[11] ^ data_in[14] ^ data_in[15] ^ data_in[18] ^ data_in[19] ^ data_in[20] ^ data_in[21] ^ data_in[22] ^ data_in[23] ^ data_in[24] ^ data_in[26] ^ data_in[28] ^ data_in[29];


        end // always

        always @(posedge clk) begin
                if(rst) begin
                        lfsr_q  <= {30{1'b1}};
                end
                else begin
                        lfsr_q  <= crc_en ? lfsr_c : lfsr_q;
                end
        end // always
endmodule // crc


//-----------------------------------------------------------------------------
// Copyright (C) 2009 OutputLogic.com
// This source file may be used and distributed without restriction
// provided that this copyright statement is not removed from the file
// and that any derivative work contains the original copyright notice
// and the associated disclaimer.
// THIS SOURCE FILE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS
// OR IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
// WARRANTIES OF MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.
//-----------------------------------------------------------------------------
// CRC module for
//       data[35:0]
//       crc[35:0]=1+x^1+x^2+x^4+x^5+x^7+x^8+x^10+x^11+x^12+x^16+x^22+x^23+x^26+x^32+x^36;
//
module crc36_rgb(
        input [35:0] data_in,
        input        crc_en,
        output [35:0] crc_out,
        input        rst,
        input        clk);

        reg [35:0] lfsr_q = {36{1'b1}} ,
                   lfsr_c;
        assign crc_out = lfsr_q;
        always @(*) begin
                lfsr_c[0] = lfsr_q[0] ^ lfsr_q[4] ^ lfsr_q[8] ^ lfsr_q[10] ^ lfsr_q[12] ^ lfsr_q[13] ^ lfsr_q[14] ^ lfsr_q[16] ^ lfsr_q[18] ^ lfsr_q[20] ^ lfsr_q[21] ^ lfsr_q[22] ^ lfsr_q[24] ^ lfsr_q[25] ^ lfsr_q[26] ^ lfsr_q[30] ^ lfsr_q[31] ^ lfsr_q[35] ^ data_in[0] ^ data_in[4] ^ data_in[8] ^ data_in[10] ^ data_in[12] ^ data_in[13] ^ data_in[14] ^ data_in[16] ^ data_in[18] ^ data_in[20] ^ data_in[21] ^ data_in[22] ^ data_in[24] ^ data_in[25] ^ data_in[26] ^ data_in[30] ^ data_in[31] ^ data_in[35];
                lfsr_c[1] = lfsr_q[0] ^ lfsr_q[1] ^ lfsr_q[4] ^ lfsr_q[5] ^ lfsr_q[8] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[15] ^ lfsr_q[16] ^ lfsr_q[17] ^ lfsr_q[18] ^ lfsr_q[19] ^ lfsr_q[20] ^ lfsr_q[23] ^ lfsr_q[24] ^ lfsr_q[27] ^ lfsr_q[30] ^ lfsr_q[32] ^ lfsr_q[35] ^ data_in[0] ^ data_in[1] ^ data_in[4] ^ data_in[5] ^ data_in[8] ^ data_in[9] ^ data_in[10] ^ data_in[11] ^ data_in[12] ^ data_in[15] ^ data_in[16] ^ data_in[17] ^ data_in[18] ^ data_in[19] ^ data_in[20] ^ data_in[23] ^ data_in[24] ^ data_in[27] ^ data_in[30] ^ data_in[32] ^ data_in[35];
                lfsr_c[2] = lfsr_q[0] ^ lfsr_q[1] ^ lfsr_q[2] ^ lfsr_q[4] ^ lfsr_q[5] ^ lfsr_q[6] ^ lfsr_q[8] ^ lfsr_q[9] ^ lfsr_q[11] ^ lfsr_q[14] ^ lfsr_q[17] ^ lfsr_q[19] ^ lfsr_q[22] ^ lfsr_q[26] ^ lfsr_q[28] ^ lfsr_q[30] ^ lfsr_q[33] ^ lfsr_q[35] ^ data_in[0] ^ data_in[1] ^ data_in[2] ^ data_in[4] ^ data_in[5] ^ data_in[6] ^ data_in[8] ^ data_in[9] ^ data_in[11] ^ data_in[14] ^ data_in[17] ^ data_in[19] ^ data_in[22] ^ data_in[26] ^ data_in[28] ^ data_in[30] ^ data_in[33] ^ data_in[35];
                lfsr_c[3] = lfsr_q[1] ^ lfsr_q[2] ^ lfsr_q[3] ^ lfsr_q[5] ^ lfsr_q[6] ^ lfsr_q[7] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[12] ^ lfsr_q[15] ^ lfsr_q[18] ^ lfsr_q[20] ^ lfsr_q[23] ^ lfsr_q[27] ^ lfsr_q[29] ^ lfsr_q[31] ^ lfsr_q[34] ^ data_in[1] ^ data_in[2] ^ data_in[3] ^ data_in[5] ^ data_in[6] ^ data_in[7] ^ data_in[9] ^ data_in[10] ^ data_in[12] ^ data_in[15] ^ data_in[18] ^ data_in[20] ^ data_in[23] ^ data_in[27] ^ data_in[29] ^ data_in[31] ^ data_in[34];
                lfsr_c[4] = lfsr_q[0] ^ lfsr_q[2] ^ lfsr_q[3] ^ lfsr_q[6] ^ lfsr_q[7] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[14] ^ lfsr_q[18] ^ lfsr_q[19] ^ lfsr_q[20] ^ lfsr_q[22] ^ lfsr_q[25] ^ lfsr_q[26] ^ lfsr_q[28] ^ lfsr_q[31] ^ lfsr_q[32] ^ data_in[0] ^ data_in[2] ^ data_in[3] ^ data_in[6] ^ data_in[7] ^ data_in[11] ^ data_in[12] ^ data_in[14] ^ data_in[18] ^ data_in[19] ^ data_in[20] ^ data_in[22] ^ data_in[25] ^ data_in[26] ^ data_in[28] ^ data_in[31] ^ data_in[32];
                lfsr_c[5] = lfsr_q[0] ^ lfsr_q[1] ^ lfsr_q[3] ^ lfsr_q[7] ^ lfsr_q[10] ^ lfsr_q[14] ^ lfsr_q[15] ^ lfsr_q[16] ^ lfsr_q[18] ^ lfsr_q[19] ^ lfsr_q[22] ^ lfsr_q[23] ^ lfsr_q[24] ^ lfsr_q[25] ^ lfsr_q[27] ^ lfsr_q[29] ^ lfsr_q[30] ^ lfsr_q[31] ^ lfsr_q[32] ^ lfsr_q[33] ^ lfsr_q[35] ^ data_in[0] ^ data_in[1] ^ data_in[3] ^ data_in[7] ^ data_in[10] ^ data_in[14] ^ data_in[15] ^ data_in[16] ^ data_in[18] ^ data_in[19] ^ data_in[22] ^ data_in[23] ^ data_in[24] ^ data_in[25] ^ data_in[27] ^ data_in[29] ^ data_in[30] ^ data_in[31] ^ data_in[32] ^ data_in[33] ^ data_in[35];
                lfsr_c[6] = lfsr_q[1] ^ lfsr_q[2] ^ lfsr_q[4] ^ lfsr_q[8] ^ lfsr_q[11] ^ lfsr_q[15] ^ lfsr_q[16] ^ lfsr_q[17] ^ lfsr_q[19] ^ lfsr_q[20] ^ lfsr_q[23] ^ lfsr_q[24] ^ lfsr_q[25] ^ lfsr_q[26] ^ lfsr_q[28] ^ lfsr_q[30] ^ lfsr_q[31] ^ lfsr_q[32] ^ lfsr_q[33] ^ lfsr_q[34] ^ data_in[1] ^ data_in[2] ^ data_in[4] ^ data_in[8] ^ data_in[11] ^ data_in[15] ^ data_in[16] ^ data_in[17] ^ data_in[19] ^ data_in[20] ^ data_in[23] ^ data_in[24] ^ data_in[25] ^ data_in[26] ^ data_in[28] ^ data_in[30] ^ data_in[31] ^ data_in[32] ^ data_in[33] ^ data_in[34];
                lfsr_c[7] = lfsr_q[0] ^ lfsr_q[2] ^ lfsr_q[3] ^ lfsr_q[4] ^ lfsr_q[5] ^ lfsr_q[8] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[13] ^ lfsr_q[14] ^ lfsr_q[17] ^ lfsr_q[22] ^ lfsr_q[27] ^ lfsr_q[29] ^ lfsr_q[30] ^ lfsr_q[32] ^ lfsr_q[33] ^ lfsr_q[34] ^ data_in[0] ^ data_in[2] ^ data_in[3] ^ data_in[4] ^ data_in[5] ^ data_in[8] ^ data_in[9] ^ data_in[10] ^ data_in[13] ^ data_in[14] ^ data_in[17] ^ data_in[22] ^ data_in[27] ^ data_in[29] ^ data_in[30] ^ data_in[32] ^ data_in[33] ^ data_in[34];
                lfsr_c[8] = lfsr_q[0] ^ lfsr_q[1] ^ lfsr_q[3] ^ lfsr_q[5] ^ lfsr_q[6] ^ lfsr_q[8] ^ lfsr_q[9] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[13] ^ lfsr_q[15] ^ lfsr_q[16] ^ lfsr_q[20] ^ lfsr_q[21] ^ lfsr_q[22] ^ lfsr_q[23] ^ lfsr_q[24] ^ lfsr_q[25] ^ lfsr_q[26] ^ lfsr_q[28] ^ lfsr_q[33] ^ lfsr_q[34] ^ data_in[0] ^ data_in[1] ^ data_in[3] ^ data_in[5] ^ data_in[6] ^ data_in[8] ^ data_in[9] ^ data_in[11] ^ data_in[12] ^ data_in[13] ^ data_in[15] ^ data_in[16] ^ data_in[20] ^ data_in[21] ^ data_in[22] ^ data_in[23] ^ data_in[24] ^ data_in[25] ^ data_in[26] ^ data_in[28] ^ data_in[33] ^ data_in[34];
                lfsr_c[9] = lfsr_q[1] ^ lfsr_q[2] ^ lfsr_q[4] ^ lfsr_q[6] ^ lfsr_q[7] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[12] ^ lfsr_q[13] ^ lfsr_q[14] ^ lfsr_q[16] ^ lfsr_q[17] ^ lfsr_q[21] ^ lfsr_q[22] ^ lfsr_q[23] ^ lfsr_q[24] ^ lfsr_q[25] ^ lfsr_q[26] ^ lfsr_q[27] ^ lfsr_q[29] ^ lfsr_q[34] ^ lfsr_q[35] ^ data_in[1] ^ data_in[2] ^ data_in[4] ^ data_in[6] ^ data_in[7] ^ data_in[9] ^ data_in[10] ^ data_in[12] ^ data_in[13] ^ data_in[14] ^ data_in[16] ^ data_in[17] ^ data_in[21] ^ data_in[22] ^ data_in[23] ^ data_in[24] ^ data_in[25] ^ data_in[26] ^ data_in[27] ^ data_in[29] ^ data_in[34] ^ data_in[35];
                lfsr_c[10] = lfsr_q[0] ^ lfsr_q[2] ^ lfsr_q[3] ^ lfsr_q[4] ^ lfsr_q[5] ^ lfsr_q[7] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[15] ^ lfsr_q[16] ^ lfsr_q[17] ^ lfsr_q[20] ^ lfsr_q[21] ^ lfsr_q[23] ^ lfsr_q[27] ^ lfsr_q[28] ^ lfsr_q[31] ^ data_in[0] ^ data_in[2] ^ data_in[3] ^ data_in[4] ^ data_in[5] ^ data_in[7] ^ data_in[11] ^ data_in[12] ^ data_in[15] ^ data_in[16] ^ data_in[17] ^ data_in[20] ^ data_in[21] ^ data_in[23] ^ data_in[27] ^ data_in[28] ^ data_in[31];
                lfsr_c[11] = lfsr_q[0] ^ lfsr_q[1] ^ lfsr_q[3] ^ lfsr_q[5] ^ lfsr_q[6] ^ lfsr_q[10] ^ lfsr_q[14] ^ lfsr_q[17] ^ lfsr_q[20] ^ lfsr_q[25] ^ lfsr_q[26] ^ lfsr_q[28] ^ lfsr_q[29] ^ lfsr_q[30] ^ lfsr_q[31] ^ lfsr_q[32] ^ lfsr_q[35] ^ data_in[0] ^ data_in[1] ^ data_in[3] ^ data_in[5] ^ data_in[6] ^ data_in[10] ^ data_in[14] ^ data_in[17] ^ data_in[20] ^ data_in[25] ^ data_in[26] ^ data_in[28] ^ data_in[29] ^ data_in[30] ^ data_in[31] ^ data_in[32] ^ data_in[35];
                lfsr_c[12] = lfsr_q[0] ^ lfsr_q[1] ^ lfsr_q[2] ^ lfsr_q[6] ^ lfsr_q[7] ^ lfsr_q[8] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[13] ^ lfsr_q[14] ^ lfsr_q[15] ^ lfsr_q[16] ^ lfsr_q[20] ^ lfsr_q[22] ^ lfsr_q[24] ^ lfsr_q[25] ^ lfsr_q[27] ^ lfsr_q[29] ^ lfsr_q[32] ^ lfsr_q[33] ^ lfsr_q[35] ^ data_in[0] ^ data_in[1] ^ data_in[2] ^ data_in[6] ^ data_in[7] ^ data_in[8] ^ data_in[10] ^ data_in[11] ^ data_in[12] ^ data_in[13] ^ data_in[14] ^ data_in[15] ^ data_in[16] ^ data_in[20] ^ data_in[22] ^ data_in[24] ^ data_in[25] ^ data_in[27] ^ data_in[29] ^ data_in[32] ^ data_in[33] ^ data_in[35];
                lfsr_c[13] = lfsr_q[1] ^ lfsr_q[2] ^ lfsr_q[3] ^ lfsr_q[7] ^ lfsr_q[8] ^ lfsr_q[9] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[13] ^ lfsr_q[14] ^ lfsr_q[15] ^ lfsr_q[16] ^ lfsr_q[17] ^ lfsr_q[21] ^ lfsr_q[23] ^ lfsr_q[25] ^ lfsr_q[26] ^ lfsr_q[28] ^ lfsr_q[30] ^ lfsr_q[33] ^ lfsr_q[34] ^ data_in[1] ^ data_in[2] ^ data_in[3] ^ data_in[7] ^ data_in[8] ^ data_in[9] ^ data_in[11] ^ data_in[12] ^ data_in[13] ^ data_in[14] ^ data_in[15] ^ data_in[16] ^ data_in[17] ^ data_in[21] ^ data_in[23] ^ data_in[25] ^ data_in[26] ^ data_in[28] ^ data_in[30] ^ data_in[33] ^ data_in[34];
                lfsr_c[14] = lfsr_q[2] ^ lfsr_q[3] ^ lfsr_q[4] ^ lfsr_q[8] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[12] ^ lfsr_q[13] ^ lfsr_q[14] ^ lfsr_q[15] ^ lfsr_q[16] ^ lfsr_q[17] ^ lfsr_q[18] ^ lfsr_q[22] ^ lfsr_q[24] ^ lfsr_q[26] ^ lfsr_q[27] ^ lfsr_q[29] ^ lfsr_q[31] ^ lfsr_q[34] ^ lfsr_q[35] ^ data_in[2] ^ data_in[3] ^ data_in[4] ^ data_in[8] ^ data_in[9] ^ data_in[10] ^ data_in[12] ^ data_in[13] ^ data_in[14] ^ data_in[15] ^ data_in[16] ^ data_in[17] ^ data_in[18] ^ data_in[22] ^ data_in[24] ^ data_in[26] ^ data_in[27] ^ data_in[29] ^ data_in[31] ^ data_in[34] ^ data_in[35];
                lfsr_c[15] = lfsr_q[3] ^ lfsr_q[4] ^ lfsr_q[5] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[13] ^ lfsr_q[14] ^ lfsr_q[15] ^ lfsr_q[16] ^ lfsr_q[17] ^ lfsr_q[18] ^ lfsr_q[19] ^ lfsr_q[23] ^ lfsr_q[25] ^ lfsr_q[27] ^ lfsr_q[28] ^ lfsr_q[30] ^ lfsr_q[32] ^ lfsr_q[35] ^ data_in[3] ^ data_in[4] ^ data_in[5] ^ data_in[9] ^ data_in[10] ^ data_in[11] ^ data_in[13] ^ data_in[14] ^ data_in[15] ^ data_in[16] ^ data_in[17] ^ data_in[18] ^ data_in[19] ^ data_in[23] ^ data_in[25] ^ data_in[27] ^ data_in[28] ^ data_in[30] ^ data_in[32] ^ data_in[35];
                lfsr_c[16] = lfsr_q[0] ^ lfsr_q[5] ^ lfsr_q[6] ^ lfsr_q[8] ^ lfsr_q[11] ^ lfsr_q[13] ^ lfsr_q[15] ^ lfsr_q[17] ^ lfsr_q[19] ^ lfsr_q[21] ^ lfsr_q[22] ^ lfsr_q[25] ^ lfsr_q[28] ^ lfsr_q[29] ^ lfsr_q[30] ^ lfsr_q[33] ^ lfsr_q[35] ^ data_in[0] ^ data_in[5] ^ data_in[6] ^ data_in[8] ^ data_in[11] ^ data_in[13] ^ data_in[15] ^ data_in[17] ^ data_in[19] ^ data_in[21] ^ data_in[22] ^ data_in[25] ^ data_in[28] ^ data_in[29] ^ data_in[30] ^ data_in[33] ^ data_in[35];
                lfsr_c[17] = lfsr_q[1] ^ lfsr_q[6] ^ lfsr_q[7] ^ lfsr_q[9] ^ lfsr_q[12] ^ lfsr_q[14] ^ lfsr_q[16] ^ lfsr_q[18] ^ lfsr_q[20] ^ lfsr_q[22] ^ lfsr_q[23] ^ lfsr_q[26] ^ lfsr_q[29] ^ lfsr_q[30] ^ lfsr_q[31] ^ lfsr_q[34] ^ data_in[1] ^ data_in[6] ^ data_in[7] ^ data_in[9] ^ data_in[12] ^ data_in[14] ^ data_in[16] ^ data_in[18] ^ data_in[20] ^ data_in[22] ^ data_in[23] ^ data_in[26] ^ data_in[29] ^ data_in[30] ^ data_in[31] ^ data_in[34];
                lfsr_c[18] = lfsr_q[2] ^ lfsr_q[7] ^ lfsr_q[8] ^ lfsr_q[10] ^ lfsr_q[13] ^ lfsr_q[15] ^ lfsr_q[17] ^ lfsr_q[19] ^ lfsr_q[21] ^ lfsr_q[23] ^ lfsr_q[24] ^ lfsr_q[27] ^ lfsr_q[30] ^ lfsr_q[31] ^ lfsr_q[32] ^ lfsr_q[35] ^ data_in[2] ^ data_in[7] ^ data_in[8] ^ data_in[10] ^ data_in[13] ^ data_in[15] ^ data_in[17] ^ data_in[19] ^ data_in[21] ^ data_in[23] ^ data_in[24] ^ data_in[27] ^ data_in[30] ^ data_in[31] ^ data_in[32] ^ data_in[35];
                lfsr_c[19] = lfsr_q[3] ^ lfsr_q[8] ^ lfsr_q[9] ^ lfsr_q[11] ^ lfsr_q[14] ^ lfsr_q[16] ^ lfsr_q[18] ^ lfsr_q[20] ^ lfsr_q[22] ^ lfsr_q[24] ^ lfsr_q[25] ^ lfsr_q[28] ^ lfsr_q[31] ^ lfsr_q[32] ^ lfsr_q[33] ^ data_in[3] ^ data_in[8] ^ data_in[9] ^ data_in[11] ^ data_in[14] ^ data_in[16] ^ data_in[18] ^ data_in[20] ^ data_in[22] ^ data_in[24] ^ data_in[25] ^ data_in[28] ^ data_in[31] ^ data_in[32] ^ data_in[33];
                lfsr_c[20] = lfsr_q[4] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[12] ^ lfsr_q[15] ^ lfsr_q[17] ^ lfsr_q[19] ^ lfsr_q[21] ^ lfsr_q[23] ^ lfsr_q[25] ^ lfsr_q[26] ^ lfsr_q[29] ^ lfsr_q[32] ^ lfsr_q[33] ^ lfsr_q[34] ^ data_in[4] ^ data_in[9] ^ data_in[10] ^ data_in[12] ^ data_in[15] ^ data_in[17] ^ data_in[19] ^ data_in[21] ^ data_in[23] ^ data_in[25] ^ data_in[26] ^ data_in[29] ^ data_in[32] ^ data_in[33] ^ data_in[34];
                lfsr_c[21] = lfsr_q[5] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[13] ^ lfsr_q[16] ^ lfsr_q[18] ^ lfsr_q[20] ^ lfsr_q[22] ^ lfsr_q[24] ^ lfsr_q[26] ^ lfsr_q[27] ^ lfsr_q[30] ^ lfsr_q[33] ^ lfsr_q[34] ^ lfsr_q[35] ^ data_in[5] ^ data_in[10] ^ data_in[11] ^ data_in[13] ^ data_in[16] ^ data_in[18] ^ data_in[20] ^ data_in[22] ^ data_in[24] ^ data_in[26] ^ data_in[27] ^ data_in[30] ^ data_in[33] ^ data_in[34] ^ data_in[35];
                lfsr_c[22] = lfsr_q[0] ^ lfsr_q[4] ^ lfsr_q[6] ^ lfsr_q[8] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[13] ^ lfsr_q[16] ^ lfsr_q[17] ^ lfsr_q[18] ^ lfsr_q[19] ^ lfsr_q[20] ^ lfsr_q[22] ^ lfsr_q[23] ^ lfsr_q[24] ^ lfsr_q[26] ^ lfsr_q[27] ^ lfsr_q[28] ^ lfsr_q[30] ^ lfsr_q[34] ^ data_in[0] ^ data_in[4] ^ data_in[6] ^ data_in[8] ^ data_in[10] ^ data_in[11] ^ data_in[13] ^ data_in[16] ^ data_in[17] ^ data_in[18] ^ data_in[19] ^ data_in[20] ^ data_in[22] ^ data_in[23] ^ data_in[24] ^ data_in[26] ^ data_in[27] ^ data_in[28] ^ data_in[30] ^ data_in[34];
                lfsr_c[23] = lfsr_q[0] ^ lfsr_q[1] ^ lfsr_q[4] ^ lfsr_q[5] ^ lfsr_q[7] ^ lfsr_q[8] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[13] ^ lfsr_q[16] ^ lfsr_q[17] ^ lfsr_q[19] ^ lfsr_q[22] ^ lfsr_q[23] ^ lfsr_q[26] ^ lfsr_q[27] ^ lfsr_q[28] ^ lfsr_q[29] ^ lfsr_q[30] ^ data_in[0] ^ data_in[1] ^ data_in[4] ^ data_in[5] ^ data_in[7] ^ data_in[8] ^ data_in[9] ^ data_in[10] ^ data_in[11] ^ data_in[13] ^ data_in[16] ^ data_in[17] ^ data_in[19] ^ data_in[22] ^ data_in[23] ^ data_in[26] ^ data_in[27] ^ data_in[28] ^ data_in[29] ^ data_in[30];
                lfsr_c[24] = lfsr_q[1] ^ lfsr_q[2] ^ lfsr_q[5] ^ lfsr_q[6] ^ lfsr_q[8] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[14] ^ lfsr_q[17] ^ lfsr_q[18] ^ lfsr_q[20] ^ lfsr_q[23] ^ lfsr_q[24] ^ lfsr_q[27] ^ lfsr_q[28] ^ lfsr_q[29] ^ lfsr_q[30] ^ lfsr_q[31] ^ data_in[1] ^ data_in[2] ^ data_in[5] ^ data_in[6] ^ data_in[8] ^ data_in[9] ^ data_in[10] ^ data_in[11] ^ data_in[12] ^ data_in[14] ^ data_in[17] ^ data_in[18] ^ data_in[20] ^ data_in[23] ^ data_in[24] ^ data_in[27] ^ data_in[28] ^ data_in[29] ^ data_in[30] ^ data_in[31];
                lfsr_c[25] = lfsr_q[2] ^ lfsr_q[3] ^ lfsr_q[6] ^ lfsr_q[7] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[13] ^ lfsr_q[15] ^ lfsr_q[18] ^ lfsr_q[19] ^ lfsr_q[21] ^ lfsr_q[24] ^ lfsr_q[25] ^ lfsr_q[28] ^ lfsr_q[29] ^ lfsr_q[30] ^ lfsr_q[31] ^ lfsr_q[32] ^ data_in[2] ^ data_in[3] ^ data_in[6] ^ data_in[7] ^ data_in[9] ^ data_in[10] ^ data_in[11] ^ data_in[12] ^ data_in[13] ^ data_in[15] ^ data_in[18] ^ data_in[19] ^ data_in[21] ^ data_in[24] ^ data_in[25] ^ data_in[28] ^ data_in[29] ^ data_in[30] ^ data_in[31] ^ data_in[32];
                lfsr_c[26] = lfsr_q[0] ^ lfsr_q[3] ^ lfsr_q[7] ^ lfsr_q[11] ^ lfsr_q[18] ^ lfsr_q[19] ^ lfsr_q[21] ^ lfsr_q[24] ^ lfsr_q[29] ^ lfsr_q[32] ^ lfsr_q[33] ^ lfsr_q[35] ^ data_in[0] ^ data_in[3] ^ data_in[7] ^ data_in[11] ^ data_in[18] ^ data_in[19] ^ data_in[21] ^ data_in[24] ^ data_in[29] ^ data_in[32] ^ data_in[33] ^ data_in[35];
                lfsr_c[27] = lfsr_q[1] ^ lfsr_q[4] ^ lfsr_q[8] ^ lfsr_q[12] ^ lfsr_q[19] ^ lfsr_q[20] ^ lfsr_q[22] ^ lfsr_q[25] ^ lfsr_q[30] ^ lfsr_q[33] ^ lfsr_q[34] ^ data_in[1] ^ data_in[4] ^ data_in[8] ^ data_in[12] ^ data_in[19] ^ data_in[20] ^ data_in[22] ^ data_in[25] ^ data_in[30] ^ data_in[33] ^ data_in[34];
                lfsr_c[28] = lfsr_q[2] ^ lfsr_q[5] ^ lfsr_q[9] ^ lfsr_q[13] ^ lfsr_q[20] ^ lfsr_q[21] ^ lfsr_q[23] ^ lfsr_q[26] ^ lfsr_q[31] ^ lfsr_q[34] ^ lfsr_q[35] ^ data_in[2] ^ data_in[5] ^ data_in[9] ^ data_in[13] ^ data_in[20] ^ data_in[21] ^ data_in[23] ^ data_in[26] ^ data_in[31] ^ data_in[34] ^ data_in[35];
                lfsr_c[29] = lfsr_q[3] ^ lfsr_q[6] ^ lfsr_q[10] ^ lfsr_q[14] ^ lfsr_q[21] ^ lfsr_q[22] ^ lfsr_q[24] ^ lfsr_q[27] ^ lfsr_q[32] ^ lfsr_q[35] ^ data_in[3] ^ data_in[6] ^ data_in[10] ^ data_in[14] ^ data_in[21] ^ data_in[22] ^ data_in[24] ^ data_in[27] ^ data_in[32] ^ data_in[35];
                lfsr_c[30] = lfsr_q[4] ^ lfsr_q[7] ^ lfsr_q[11] ^ lfsr_q[15] ^ lfsr_q[22] ^ lfsr_q[23] ^ lfsr_q[25] ^ lfsr_q[28] ^ lfsr_q[33] ^ data_in[4] ^ data_in[7] ^ data_in[11] ^ data_in[15] ^ data_in[22] ^ data_in[23] ^ data_in[25] ^ data_in[28] ^ data_in[33];
                lfsr_c[31] = lfsr_q[5] ^ lfsr_q[8] ^ lfsr_q[12] ^ lfsr_q[16] ^ lfsr_q[23] ^ lfsr_q[24] ^ lfsr_q[26] ^ lfsr_q[29] ^ lfsr_q[34] ^ data_in[5] ^ data_in[8] ^ data_in[12] ^ data_in[16] ^ data_in[23] ^ data_in[24] ^ data_in[26] ^ data_in[29] ^ data_in[34];
                lfsr_c[32] = lfsr_q[0] ^ lfsr_q[4] ^ lfsr_q[6] ^ lfsr_q[8] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[12] ^ lfsr_q[14] ^ lfsr_q[16] ^ lfsr_q[17] ^ lfsr_q[18] ^ lfsr_q[20] ^ lfsr_q[21] ^ lfsr_q[22] ^ lfsr_q[26] ^ lfsr_q[27] ^ lfsr_q[31] ^ data_in[0] ^ data_in[4] ^ data_in[6] ^ data_in[8] ^ data_in[9] ^ data_in[10] ^ data_in[12] ^ data_in[14] ^ data_in[16] ^ data_in[17] ^ data_in[18] ^ data_in[20] ^ data_in[21] ^ data_in[22] ^ data_in[26] ^ data_in[27] ^ data_in[31];
                lfsr_c[33] = lfsr_q[1] ^ lfsr_q[5] ^ lfsr_q[7] ^ lfsr_q[9] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[13] ^ lfsr_q[15] ^ lfsr_q[17] ^ lfsr_q[18] ^ lfsr_q[19] ^ lfsr_q[21] ^ lfsr_q[22] ^ lfsr_q[23] ^ lfsr_q[27] ^ lfsr_q[28] ^ lfsr_q[32] ^ data_in[1] ^ data_in[5] ^ data_in[7] ^ data_in[9] ^ data_in[10] ^ data_in[11] ^ data_in[13] ^ data_in[15] ^ data_in[17] ^ data_in[18] ^ data_in[19] ^ data_in[21] ^ data_in[22] ^ data_in[23] ^ data_in[27] ^ data_in[28] ^ data_in[32];
                lfsr_c[34] = lfsr_q[2] ^ lfsr_q[6] ^ lfsr_q[8] ^ lfsr_q[10] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[14] ^ lfsr_q[16] ^ lfsr_q[18] ^ lfsr_q[19] ^ lfsr_q[20] ^ lfsr_q[22] ^ lfsr_q[23] ^ lfsr_q[24] ^ lfsr_q[28] ^ lfsr_q[29] ^ lfsr_q[33] ^ data_in[2] ^ data_in[6] ^ data_in[8] ^ data_in[10] ^ data_in[11] ^ data_in[12] ^ data_in[14] ^ data_in[16] ^ data_in[18] ^ data_in[19] ^ data_in[20] ^ data_in[22] ^ data_in[23] ^ data_in[24] ^ data_in[28] ^ data_in[29] ^ data_in[33];
                lfsr_c[35] = lfsr_q[3] ^ lfsr_q[7] ^ lfsr_q[9] ^ lfsr_q[11] ^ lfsr_q[12] ^ lfsr_q[13] ^ lfsr_q[15] ^ lfsr_q[17] ^ lfsr_q[19] ^ lfsr_q[20] ^ lfsr_q[21] ^ lfsr_q[23] ^ lfsr_q[24] ^ lfsr_q[25] ^ lfsr_q[29] ^ lfsr_q[30] ^ lfsr_q[34] ^ data_in[3] ^ data_in[7] ^ data_in[9] ^ data_in[11] ^ data_in[12] ^ data_in[13] ^ data_in[15] ^ data_in[17] ^ data_in[19] ^ data_in[20] ^ data_in[21] ^ data_in[23] ^ data_in[24] ^ data_in[25] ^ data_in[29] ^ data_in[30] ^ data_in[34];


        end // always

        always @(posedge clk) begin
                if(rst) begin
                        lfsr_q  <= {36{1'b1}};
                end
                else begin
                        lfsr_q  <= crc_en ? lfsr_c : lfsr_q;
                end
        end // always
endmodule // crc