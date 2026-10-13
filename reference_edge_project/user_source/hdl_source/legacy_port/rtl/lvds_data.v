`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/06/10 17:51:43
// Design Name: 
// Module Name: lvds_data
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


module lvds_data(
input clk,
input clk0,
input rstn,
input rstn0,
input [34:0]lvds_0_data,
input [34:0]lvds_1_data,
output [31:0] R   ,
output [31:0] G   ,
output [31:0] B   ,
output [3:0]DE_out_use_0 ,
output [3:0]DE_out_use_1 ,
output [3:0]DE_out_use_2 ,
output [3:0]DE_out_use_3 ,
output [3:0]HS_out_use     ,
output [3:0]VS_out_use
    );
wire [31:0] Y    ;
wire [31:0] U    ;
wire [31:0] V    ;
wire        HS   ;
wire        VS   ;
genvar i;
wire [34:0]lvds_data_out0;
wire [34:0]lvds_data_out1;
wire mmcm_reset;
assign mmcm_reset = ~rstn;
wire mmcm_reset0;
assign mmcm_reset0 = ~rstn0;
wire mis_aligned;
wire deskew_rddval;
reg                  deskew_rddval_reg;
wire rd_empty0;
wire rd_empty1;

//assign  deskew_rddval = ((rd_empty=={2{1'b0}}));

// always @ (posedge clk)
// if(mmcm_reset)
    // deskew_rddval_reg <= 1'b0;
// else 
    // deskew_rddval_reg <= deskew_rddval;

 // generate for (i=0; i<2 ; i= i+1) begin : deyuv
// always@(posedge clk)begin	
   // if(mmcm_reset)begin
     // lvds_data_in_use[i]<=0;
   // end else begin
     // lvds_data_in_use[i]<=lvds_data_in[i];
	// end
// end	
	// reg   wrreq;
	// reg   de_reg;
	// always @ (posedge clk)
// if(mmcm_reset) begin
    // wrreq  <= 1'b0;
// end    else  begin
    // wrreq <=DE[i];
// end     


// fifo_generator_0 fifo_generator_0_INST (
  // .clk            (clk),                          // input wire clk
  // .srst           (mmcm_reset|HS),                // input wire srst
  // .din            (lvds_data_in_use[i]), // input wire [34 : 0] din
  // .wr_en          (wrreq),                                 // input wire wr_en
  // .rd_en          (deskew_rddval),                         // input wire rd_en
  // .dout           (lvds_data_out[i]),                           // output wire [34 : 0] dout
  // .full           (),                                      // output wire full
  // .almost_full    (),                                      // output wire almost_full
  // .empty          (rd_empty[i]),                                      // output wire empty
  // .almost_empty   ());                           // output wire almost_empty
	
  
  
  
// end
// endgenerate
wire   rd_en;
assign rd_en = ~rd_empty0 & ~rd_empty1;
// always@(posedge clk)begin
// rd_en <=   ~rd_empty0 & ~rd_empty1;
// end
fifo_generator_0 fifo_generator_0_INST (
  .wr_clk            (clk0),                          // input wire clk
  .rst           (mmcm_reset0|HS|VS),                // input wire srst
  .din            (lvds_0_data), // input wire [34 : 0] din
  .wr_en          (lvds_0_data[2]),                                 // input wire wr_en
  .rd_clk         (clk),
  .rd_en          (rd_en),                         // input wire rd_en
  .dout           (lvds_data_out0),                           // output wire [34 : 0] dout
  .full           (),                                      // output wire full
  .empty          (rd_empty0)
  );                           // output wire almost_empty
	
  fifo_generator_0 fifo_generator_1_INST (
  .wr_clk            (clk),                          // input wire clk
  .rst           (mmcm_reset|HS|VS),                // input wire srst
  .din            (lvds_1_data), // input wire [34 : 0] din
  .wr_en          (lvds_1_data[2]),                                 // input wire wr_en
  .rd_clk         (clk),
  .rd_en          (rd_en),                         // input wire rd_en
  .dout           (lvds_data_out1),                           // output wire [34 : 0] dout
  .full           (),                                      // output wire full
  .empty          (rd_empty1)
  );        
                          // output wire almost_empty
	  // fifo_generator_1 fifo_generator_2_INST (
  // .clk            (clk),                          // input wire clk
  // .srst           (mmcm_reset|HS|VS),                // input wire srst
  // .din            (lvds_1_data), // input wire [34 : 0] din
  // .wr_en          (lvds_1_data[34]),                                 // input wire wr_en
  // .rd_en          (rd_en),                         // input wire rd_en
  // .dout           (lvds_data_out1),                           // output wire [34 : 0] dout
  // .full           (),                                      // output wire full                     
  // .empty          (rd_empty1)                                    // output wire empty
  // );                           // output wire almost_empty
		// fifo_generator_1 fifo_generator_3_INST (
  // .clk            (clk),                          // input wire clk
  // .srst           (mmcm_reset|HS),                // input wire srst
  // .din            (lvds_0_data), // input wire [34 : 0] din
  // .wr_en          (lvds_0_data[34]),                                 // input wire wr_en
  // .rd_en          (rd_en),                         // input wire rd_en
  // .dout           (lvds_data_out0),                           // output wire [34 : 0] dout
  // .full           (),                                      // output wire full                     
  // .empty          (rd_empty0)                                    // output wire empty
  // );      
  


wire [31:0] Y    ;
wire [31:0] U    ;
wire [31:0] V    ;
wire  DE_true   ;
wire        HS   ;
wire        VS   ;
wire  [1:0] VC   ;    
assign Y  = {lvds_data_out1[31:13],lvds_data_out1[33],lvds_data_out1[11:8],lvds_data_out1[32],lvds_data_out1[6:3],lvds_data_out1[34],lvds_data_out1[1:0]};
assign U  = {lvds_data_out0[15:8],lvds_data_out0[15:8],lvds_data_out0[7:3],lvds_data_out0[34],lvds_data_out0[1:0],lvds_data_out0[7:3],lvds_data_out0[34],lvds_data_out0[1:0]};
assign V  = {lvds_data_out0[31:24],lvds_data_out0[31:24],lvds_data_out0[23:16],lvds_data_out0[23:16]};
assign DE_true =rd_en; 
assign HS = {lvds_1_data[12]};  
assign VS = {lvds_1_data[7]};   
assign VC = {lvds_data_out0[33:32]};   
reg [1:0]VC_1;
reg [1:0]VC_2;
always@(posedge clk)begin
VC_1 <=VC;
VC_2 <=VC_1;
end
wire [31:0]R ;
wire [31:0]G ;
wire [31:0]B ;
wire  HS_out;
wire  VS_out;
wire  DE_out;
 yuv_rgb  yuv_rgb_i(
.vid_clk(clk),
.vid_rst(mmcm_reset),
.RGB_Y  (Y),
.RGB_U  (U),
.RGB_V  (V),
.TPG_HS (HS),
.TPG_VS (VS),
.TPG_DE (DE_true),
.HS     (HS_out),
.VS     (VS_out),
.DE     (DE_out),
.R      (R),
.G      (G),
.B      (B)

);
wire DE_out_vc0;
wire DE_out_vc1;
wire DE_out_vc2;
wire DE_out_vc3;
assign DE_out_vc0 = DE_out & (VC_2==0);
assign DE_out_vc1 = DE_out & (VC_2==1);
assign DE_out_vc2 = DE_out & (VC_2==2);
assign DE_out_vc3 = DE_out & (VC_2==3);

wire [3:0] HS_out_use  ;
wire [3:0] VS_out_use  ;
wire [3:0] DE_out_use  ;
assign HS_out_use = {HS_out,HS_out,HS_out,HS_out};
assign VS_out_use = {VS_out,VS_out,VS_out,VS_out};
assign DE_out_use_0 = {DE_out_vc0,DE_out_vc0,DE_out_vc0,DE_out_vc0};
assign DE_out_use_1 = {DE_out_vc1,DE_out_vc1,DE_out_vc1,DE_out_vc1};   
assign DE_out_use_2 = {DE_out_vc2,DE_out_vc2,DE_out_vc2,DE_out_vc2};
assign DE_out_use_3 = {DE_out_vc3,DE_out_vc3,DE_out_vc3,DE_out_vc3};
// reg [15:0]h_count;
// reg [15:0]h_count1;
// reg [15:0]v_count;
// reg [15:0]v_count1;
// always@(posedge clk)begin
// if(HS_use_pos)begin
// h_count1<=0;
// h_count<=h_count1;
// end
// else if (DE_true)begin
// h_count1<=h_count1+1;
// end
// end
// always@(posedge clk)begin
// if(vs_pos)begin
// v_count1<=0;
// v_count<=v_count1;
// end
// else if (hs_pos)begin
// v_count1<=v_count1+1;
// end
// end

// reg HS_use;
// wire HS_use_pos;
// assign HS_use_pos=HS&~HS_use;
// always@(posedge clk)begin
// HS_use<=HS;
// end

// wire hs_use0;
// assign hs_use0 = HS&(VC==0);
// reg hs_1;
// wire hs_pos;
// assign hs_pos=hs_use0&~hs_1;
// always@(posedge clk)begin
// hs_1<=hs_use0;
// end
// reg vs_1;
// wire vs_pos;
// assign vs_pos=VS&~vs_1;
// always@(posedge clk)begin
// vs_1<=VS;
// end

// ila_0 ila_0 (
// .clk(clk),
// .probe0(lvds_1_data),
// .probe1(lvds_data_out1),
// .probe2(lvds_0_data),
// .probe3(lvds_data_out0),
// .probe4(rd_en),
// .probe5({HS,VS,rd_empty1,rd_empty0}),
// .probe6(h_count),
// .probe7(v_count)

// );


endmodule
