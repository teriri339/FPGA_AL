`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/09/05 10:23:19
// Design Name: 
// Module Name: para
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


module para(
input  [1:0] w_polar				,	//2
input  [7:0]  misc0		    	, //8
input  [7:0] misc1		    	, //8                   
input  [31:0] PIX_CLK_FREQ   , //32
input  [15:0] H_ACTIVE       , //16
input  [15:0] H_FP           , //16
input  [15:0] H_SYNC         , //16
input  [15:0] H_BP           , //16
input  [15:0] V_ACTIVE       , //16
input  [15:0] V_FP           , //16
input  [15:0] V_SYNC         , //16
input  [15:0] V_BP           , //16
input  [0:0] YUV420			,		


output [178:0] NATIVE_PAR 

    );
    
    assign  NATIVE_PAR= {w_polar				,	//2
					 misc0		    	, //8
                     misc1		    	, //8                   
                     PIX_CLK_FREQ   , //32
                     H_ACTIVE       , //16
                     H_FP           , //16
                     H_SYNC         , //16
                     H_BP           , //16
                     V_ACTIVE       , //16
                     V_FP           , //16
                     V_SYNC         , //16
                     V_BP           , //16
				     YUV420					  //1
};
endmodule
