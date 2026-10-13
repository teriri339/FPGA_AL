`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/10/25 15:47:12
// Design Name: 
// Module Name: a2b
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


module a2b(
input [39:0] R_I, 
input [39:0] G_I,
input [39:0] B_I,

output [31:0] R_O,
output [31:0] G_O,
output [31:0] B_O

  );
   
   
assign   R_O = {R_I[39:32],R_I[29:22],R_I[19:12],R_I[9:2]};
assign   G_O = {G_I[39:32],G_I[29:22],G_I[19:12],G_I[9:2]};   
assign   B_O = {B_I[39:32],B_I[29:22],B_I[19:12],B_I[9:2]};  


    
  
     
endmodule
