`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2022/11/19 11:55:12
// Design Name: 
// Module Name: yuv_rgb
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

module yuv_rgb(
	input 		 vid_clk,
	input 		 vid_rst,

	input [31:0]  RGB_Y,
	input [31:0]  RGB_U,
	input [31:0]  RGB_V,
	
	input  		  TPG_HS,
	input  		  TPG_VS,
	input  		  TPG_DE,
	
	output 		  HS,
	output 		  VS,
	output 		  DE,
	
	output [31:0] R,
	output [31:0] G,
	output [31:0] B,
	output [95:0] data_rgb
);



wire [95:0]data_rgb;
assign data_rgb={
              R[31:24],G[31:24],B[31:24],
			  R[23:16],G[23:16],B[23:16],
			  R[15:8] ,G[15:8] ,B[15:8] ,
              R[7:0]  ,G[7:0]  ,B[7:0]  };
wire [31:0] R;
wire [31:0] G;
wire [31:0] B;


//delay clock num
localparam A0 = 1;
localparam A1 = 0;
localparam A2 = 0;
localparam A3 = 0;

 SRL16E #(.INIT(16'h0000)) DE_inst (
      .A0(A0),.A1(A1),.A2(A2),.A3(A3),     
      .CE(~vid_rst), .CLK(vid_clk),  
	  .Q(DE),	.D(TPG_DE) );

 SRL16E #(.INIT(16'h0000)) HS_inst (
      .A0(A0),.A1(A1),.A2(A2),.A3(A3),     
      .CE(~vid_rst), .CLK(vid_clk),  
			.Q(HS),	.D(TPG_HS) );

 SRL16E #(.INIT(16'h0000)) VS_inst (
      .A0(A0),.A1(A1),.A2(A2),.A3(A3),     
      .CE(~vid_rst), .CLK(vid_clk),  
		.Q(VS),	.D(TPG_VS) );

genvar i;
generate 
for (i = 0 ; i < 4; i = i + 1)  begin :csc

reg[19:0] R_temp;
reg[19:0] G_temp;
reg[19:0] B_temp;



assign R[8*i+:8] = (R_temp[19:17]) ? 8'd255 :  R_temp[16:9];
assign G[8*i+:8] = (G_temp[19:17]) ? 8'd255 :  G_temp[16:9];
assign B[8*i+:8] = (B_temp[19:17]) ? 8'd255 :  B_temp[16:9];


	
reg [19:0] t_596Y  ;
reg [19:0] t_817Cr ;
reg [19:0] t_200Cb ;
reg [19:0] t_416Cr ;
reg [19:0] t_1033Cb;


reg r_jud;
reg g_jud;
reg b_jud;




always @(posedge vid_clk)
if(vid_rst) begin 
	t_596Y   <= 'b0; 
    t_817Cr  <= 'b0;
    t_200Cb  <= 'b0;
	t_416Cr  <= 'b0;
    t_1033Cb <= 'b0;
end else begin 
	t_596Y     <= 596 * RGB_Y[8*i +: 8]; 
    t_817Cr    <=817 * RGB_V[8*i +: 8];
    t_200Cb    <= 200 * RGB_U[8*i +: 8];
	t_416Cr    <=416 * RGB_V[8*i +: 8]; 
    t_1033Cb   <= 1033* RGB_U[8*i +: 8];
end 





//always @(posedge vid_clk) begin 
always @(*) begin 
	r_jud<= ((t_596Y + t_817Cr) >= 114131);
	g_jud<= ((t_596Y + 69370) >= (t_200Cb + t_416Cr));
	b_jud<= ((t_596Y + t_1033Cb) >= 141787);
end

always @(posedge vid_clk)
if(vid_rst) begin 
	R_temp <= 'b0; 
    G_temp <= 'b0;
    B_temp <= 'b0;
end else 	 begin 
	R_temp <= r_jud ? t_596Y + t_817Cr - 114131 : 8'd0; 
    G_temp <= g_jud ? t_596Y + 69370 - t_200Cb - t_416Cr : 8'd0;
    B_temp <= b_jud ? t_596Y + t_1033Cb - 141787 : 8'd0; 
end 
end
endgenerate 



endmodule 



// module yuv_rgb(

// input [31:0]Y0 ,
// input [31:0]Y1 ,
// input [31:0]U  ,
// input [31:0]V  ,
// input ref_clk  ,
// input rx_en    ,
// input rx_clk   ,
// input rst      ,
// output[95:0]data_rgb

    // );


	
	
	
// genvar i;
// wire [95:0]data_rgb;
// assign data_rgb={RGB_R[7:0]  ,RGB_G[7:0]  ,RGB_B[7:0]   ,
                 // RGB_R[15:8] ,RGB_G[15:8] ,RGB_B[15:8]  ,
				 // RGB_R[23:16],RGB_G[23:16],RGB_B[23:16] ,
                 // RGB_R[31:24],RGB_G[31:24],RGB_B[31:24]			 				 
				// };

// wire [31:0] RGB_R;
// wire [31:0] RGB_G;
// wire [31:0] RGB_B;

// generate for (i = 0 ; i < 4; i = i + 1)  begin :yuv_to_rgb	
// reg[19:0] R_temp__f;
// reg[19:0] G_temp__f;
// reg[19:0] B_temp__f;
    
// reg [19:0] t_596Y__1  ;
// reg [19:0] t_817Cr__1 ;
// reg [19:0] t_200Cb__1 ;
// reg [19:0] t_416Cr__1 ;
// reg [19:0] t_1033Cb__1;

// reg[19:0] RGB_R_temp;
// reg[19:0] RGB_G_temp;
// reg[19:0] RGB_B_temp;

// reg r_jud__2;
// reg g_jud__2;
// reg b_jud__2;	
	
// always @(posedge rx_clk)begin
    // if(~rst) begin 
        // t_596Y__1     <= 0; 
        // t_817Cr__1    <= 0;
        // t_200Cb__1    <= 0;
        // t_416Cr__1    <= 0;
        // t_1033Cb__1   <= 0;
        // RGB_R_temp <= 0;
        // RGB_G_temp <= 0;
        // RGB_B_temp <= 0;
    // end 
    // else begin 
 
            // t_596Y__1     <= 596 * Y0[8*i +: 8];
            // t_817Cr__1    <= 817 * V[8*i +: 8];
            // t_200Cb__1    <= 200 * U[8*i +: 8];
            // t_416Cr__1    <= 416 * V[8*i +: 8]; 
            // t_1033Cb__1   <= 1033* U[8*i +: 8];

    // end 
// end

// reg [20:0] r_temp1__2;
// reg [20:0] g_temp1__2;
// reg [20:0] g_temp2__2;
// reg [20:0] b_temp1__2;

// always @(posedge rx_clk) begin 
    // if(~rst)begin
        // r_jud__2   <= 0;
        // g_jud__2   <= 0;
        // b_jud__2   <= 0;
        // r_temp1__2 <= 0;
        // g_temp1__2 <= 0;
        // g_temp2__2 <= 0;
        // b_temp1__2 <= 0;
    // end
    // else begin 
        // r_jud__2   <= ((t_596Y__1 + t_817Cr__1) >= 114131);
        // g_jud__2   <= ((t_596Y__1 + 69370) >= (t_200Cb__1 + t_416Cr__1));
        // b_jud__2   <= ((t_596Y__1 + t_1033Cb__1) >= 141787);
        // r_temp1__2 <= t_596Y__1 + t_817Cr__1;
        // g_temp1__2 <= t_596Y__1 + 69370;
        // g_temp2__2 <= t_200Cb__1 + t_416Cr__1;
        // b_temp1__2 <= t_596Y__1 + t_1033Cb__1;         
    // end
// end

// always @(posedge rx_clk)begin
    // if(~rst) begin 
        // R_temp__f <= 0; 
        // G_temp__f <= 0;
        // B_temp__f <= 0;
    // end 
    // else begin 
        // R_temp__f <= r_jud__2 ? r_temp1__2 - 114131 : 8'd0; 
        // G_temp__f <= g_jud__2 ? g_temp1__2 - g_temp2__2 : 8'd0;
        // B_temp__f <= b_jud__2 ? b_temp1__2 - 141787 : 8'd0;    
    // end 
// end
// assign RGB_R[8*i+:8] =(R_temp__f[19:17]) ? 8'd255 :  R_temp__f[16:9]  ;
// assign RGB_G[8*i+:8] =(G_temp__f[19:17]) ? 8'd255 :  G_temp__f[16:9]  ;
// assign RGB_B[8*i+:8] =(B_temp__f[19:17]) ? 8'd255 :  B_temp__f[16:9]  ;


// end
// endgenerate	
	
// ila_1 ila_1(
// .clk(rx_clk),
// .probe0(data_rgb),
// .probe1(RGB_R),
// .probe2(RGB_G),
// .probe3(RGB_B)



// );
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
// endmodule
