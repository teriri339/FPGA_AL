`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/07/01 19:06:46
// Design Name: 
// Module Name: video_data_sw
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


module video_data_sw(
input video_mode,
input  [3:0] DE    ,
input  [3:0] HS    ,
input  [3:0] VS    ,
input  [3:0] DE_1  ,
input  [3:0] HS_1  ,
input  [3:0] VS_1  ,
input  [31:0]R     ,
input  [31:0]G     ,
input  [31:0]B     ,
input  [31:0]R_1   ,
input  [31:0]G_1   ,
input  [31:0]B_1   ,
output [3:0] DE_out,
output [3:0] HS_out,
output [3:0] VS_out,
output [31:0]R_out ,
output [31:0]G_out ,
output [31:0]B_out

    );
 
wire[3:0] DE_out;
wire[3:0] HS_out;
wire[3:0] VS_out;
wire[31:0]R_out ;
wire[31:0]G_out ;
wire[31:0]B_out ;
assign DE_out =  video_mode ?DE_1:DE  ;
assign HS_out =  video_mode ?HS_1:HS  ;
assign VS_out =  video_mode ?VS_1:VS  ;
assign R_out  =  video_mode ?R_1 :R   ;
assign G_out  =  video_mode ?G_1 :G   ;
assign B_out  =  video_mode ?B_1 :B   ;
    
endmodule
