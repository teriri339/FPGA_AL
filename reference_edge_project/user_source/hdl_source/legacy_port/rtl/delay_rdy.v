`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/08/28 15:55:26
// Design Name: 
// Module Name: delay_rdy
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


module delay_rdy(

input  ref_clk,
input  i_rst,
output delay_ready

    );
 wire ref_clk      ;
 wire delay_ready  ;
    IDELAYCTRL icontrol(// Instantiate input delay control block
    .REFCLK (ref_clk),
    .RST    (i_rst),
    .RDY    (delay_ready)
    );
    
    
endmodule
