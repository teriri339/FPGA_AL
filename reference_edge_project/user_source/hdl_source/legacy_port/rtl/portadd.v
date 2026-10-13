`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/12/03 15:07:51
// Design Name: 
// Module Name: portadd
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


 module portadd(
input vid_clk,
input [7:0] R_1,
input [7:0] G_1,
input [7:0] B_1,
input [7:0] R_2,
input [7:0] G_2,
input [7:0] B_2,
input DE_1,
input HS_1,
input VS_1,
input DE_2,
input HS_2,
input VS_2,
output [15:0] R_O,
output [15:0] G_O,
output [15:0] B_O,
output [1:0]  DE_O,
output [1:0]  HS_O,
output [1:0]  VS_O,
input port_swap

  );
wire port_swap;   
reg    port_swap_vclk;
always@(posedge vid_clk)begin
port_swap_vclk<=port_swap;
end
assign   R_O = port_swap_vclk ?  {R_1,R_2}   :{R_2,R_1}  ;
assign   G_O = port_swap_vclk ?  {G_1,G_2}   :{G_2,G_1}  ;   
assign   B_O = port_swap_vclk ?  {B_1,B_2}   :{B_2,B_1}  ;  
assign   DE_O= port_swap_vclk ?  {DE_1,DE_2} :{DE_2,DE_1};
assign   HS_O= port_swap_vclk ?  {HS_1,HS_2} :{HS_2,HS_1};
assign   VS_O= port_swap_vclk ?  {VS_1,VS_2} :{VS_2,VS_1};

    
endmodule
