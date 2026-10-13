`timescale 1ns / 1ps


`define CDC_MULTI_BIT_SIGNAL_OUTGEN(aclk,adata_in,bclk,bdata_out,DATA_WIDTH,DEST_FF)                    generate begin xpm_cdc_array_single #(.DEST_SYNC_FF(DEST_FF),.INIT_SYNC_FF(0),.SIM_ASSERT_CHK(0),.SRC_INPUT_REG(1),.WIDTH(DATA_WIDTH)) cdc_u(.src_clk(aclk),.src_in(adata_in),.dest_clk(bclk),.dest_out(bdata_out));    end  endgenerate  
`define CDC_MULTI_BIT_SIGNAL_OUTGEN_NOIN(adata_in,bclk,bdata_out,DATA_WIDTH,DEST_FF)                    generate begin xpm_cdc_array_single #(.DEST_SYNC_FF(DEST_FF),.INIT_SYNC_FF(0),.SIM_ASSERT_CHK(0),.SRC_INPUT_REG(0),.WIDTH(DATA_WIDTH)) cdc_u(.src_clk( ),.src_in(adata_in),.dest_clk(bclk),.dest_out(bdata_out));    end  endgenerate  
`define CDC_SINGLE_BIT_PULSE_OUTGEN(aclk,arst,apulse_in,bclk,brst,bpulse_out,SIM,DEST_FF)               generate if(SIM==0)begin  xpm_cdc_pulse #(.DEST_SYNC_FF(DEST_FF), .INIT_SYNC_FF(0),.REG_OUTPUT(0),.RST_USED(1),.SIM_ASSERT_CHK (0)) cdc_u (.src_clk(aclk),.src_rst(arst),.src_pulse(apulse_in),.dest_clk(bclk),.dest_rst(brst),.dest_pulse(bpulse_out));   end else begin   reg [5:0] name1 = 0;wire name2;always@(posedge aclk)if(arst)name1[0] <=0;else name1[0] <= apulse_in;assign name2 = apulse_in & ~name1[0]; always@(posedge aclk)if(arst)name1[1] <= 0;else name1[1] <= name2 ? ~name1[1]:name1[1];always@(posedge bclk)if(brst)name1[5:2]<=0;else begin name1[2]<=name1[1];name1[3]<=name1[2];name1[4]<=name1[3];name1[5]<=name1[4];end  assign bpulse_out=name1[4]^name1[5];  end  endgenerate
`define POS_MONITOR_OUTGEN(clk,rst,in,out)                                                              generate  begin  reg buf_name1 = 0; always@(posedge clk)begin if(rst)buf_name1 <= 0; else  buf_name1 <= in; end assign out = (~buf_name1)&(in);  end  endgenerate
`define NEG_MONITOR_OUTGEN(clk,rst,in,out)                                                              generate  begin  reg buf_name1 = 0; always@(posedge clk)begin if(rst)buf_name1 <= 0; else  buf_name1 <= in; end assign out = (buf_name1)&(~in);  end  endgenerate
`define XOR_MONITOR_OUTGEN(clk,rst,in,out)                                                              generate  begin  reg buf_name1 = 0; always@(posedge clk)begin if(rst)buf_name1 <= 0; else  buf_name1 <= in; end assign out = buf_name1^in;  end  endgenerate
`define POS_STRETCH_OUTGEN(clk,rst,pulse_in,pulse_out,DELAY_NUM)                                        generate  begin    reg [DELAY_NUM-2:0] temp_name = 0; always@(posedge clk)begin  if(rst)temp_name <= {(DELAY_NUM-1){1'b0}}; else temp_name <= pulse_in ? {(DELAY_NUM-1){1'b1} }: temp_name<<1 ; end  assign  pulse_out = temp_name[DELAY_NUM-2]|pulse_in;  end  endgenerate
`define NEG_STRETCH_OUTGEN(clk,rst,pulsen_in,pulsen_out,DELAY_NUM)                                      generate  begin    reg [DELAY_NUM-2:0] temp_name = 0; always@(posedge clk)begin  if(rst)temp_name <= {(DELAY_NUM-1){1'b0}}; else temp_name <= ~pulsen_in ? {(DELAY_NUM-1){1'b1} }: temp_name<<1 ; end  assign  pulsen_out = ~( temp_name[DELAY_NUM-2] | ~pulsen_in ) ;  end  endgenerate
`define HANDSHAKE_OUTGEN(aclk,arst,apulse_in,adata_in,bclk,brst,bpulse_out,bdata_out,DATA_WIDTH,SIM)    generate  if(SIM==0) begin  handshake  #(.C_DATA_WIDTH(DATA_WIDTH))  handshake_u (.SRC_CLK_I(aclk),.SRC_RST_I(arst),.SRC_DATA_I( adata_in),.SRC_SYNC_PULSE_I ( apulse_in), .DST_CLK_I ( bclk),.DST_DATA_O (bdata_out),.DST_SYNC_FINISH_O(bpulse_out) ); end  else  begin  handshake2 #(.C_DATA_WIDTH(DATA_WIDTH))  handshake_u (.SRC_CLK_I(aclk),.SRC_RST_I(arst),.SRC_DATA_I( adata_in),.SRC_SYNC_PULSE_I ( apulse_in), .DST_CLK_I (bclk),.DST_DATA_O (bdata_out ),.DST_SYNC_FINISH_O(bpulse_out) ); end  endgenerate   
`define DELAY_OUTGEN(clk,rst,data_in,data_out,DATA_WIDTH,DLY)                                           generate if(DLY==0)begin  assign data_out = data_in; end  else if(DLY==1)begin  reg [DATA_WIDTH-1:0] a_temp = 0; always@(posedge clk) a_temp <= data_in; assign data_out = a_temp ; end  else begin  reg [DATA_WIDTH-1:0] a_temp [DLY-1:0] ;always@(posedge clk) begin  if(rst)a_temp[DLY-1] <= 0; else   a_temp[DLY-1] <= data_in; end  for(i=0;i<=DLY-2;i=i+1)begin  always@(posedge clk)begin  if(rst)begin  a_temp[i] <= 0; end  else begin  a_temp[i] <= a_temp[i+1]; end  end  end  assign data_out = a_temp[0]; end  endgenerate

//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/12/20 14:58:29
// Design Name: 
// Module Name: vs_gen
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module vs_gen(
input   PCLK_I   ,
input   RSTN_I  ,
input   DE_I    ,
output  reg VS_O  = 0 

);


parameter PCLK_CYCLE_NUM_1 = 3000 ;
parameter PCLK_CYCLE_NUM_2 = 50 ;
parameter PCLK_CYCLE_NUM_3 = 600000 ;


reg [7:0] state ;
reg [31:0] cnt = 0;


always@(posedge PCLK_I)begin
    if(~RSTN_I | DE_I )begin //开始检测
        state <= 0;
        cnt   <= 0;
        VS_O  <= 0;
    end
    else begin
        case(state)
            0:begin
                cnt   <= (cnt==PCLK_CYCLE_NUM_1) ? 0 :  cnt + 1 ;
                state <= (cnt==PCLK_CYCLE_NUM_1) ? 1 : state ;
            end
            1:begin
                VS_O <= 1 ;
                cnt  <=   (cnt==PCLK_CYCLE_NUM_2) ? 0 :  cnt + 1 ;
                state <=  (cnt==PCLK_CYCLE_NUM_2) ? 2 : state ;
            end
            2:begin
                VS_O <= 0 ;
                cnt  <=   (cnt==PCLK_CYCLE_NUM_3) ? 0 :  cnt + 1 ;
                state <=  (cnt==PCLK_CYCLE_NUM_3) ? 0 : state ;
            end
            default:;

        endcase
    end
end




endmodule




