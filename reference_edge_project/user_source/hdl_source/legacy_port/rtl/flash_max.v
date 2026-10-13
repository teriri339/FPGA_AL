`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/12/16 11:13:14
// Design Name: 
// Module Name: flash_max
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
module flash_mux_3(
input [1:0] SELECT_I,
//out
output CS_O,
output MOSI_O,
input  MISO_I,

//inter0
input  CLK_0_I,
input  CS_0_I,
input  MOSI_0_I,
output MISO_0_O,

//inter1
input  CLK_1_I,
input  CS_1_I,
input  MOSI_1_I,
output MISO_1_O,

//inter2
input  CLK_2_I,
input  CS_2_I,
input  MOSI_2_I,
output MISO_2_O


);  

assign  MISO_0_O = (SELECT_I==2'b00) ?  MISO_I  : 0  ;
assign  MISO_1_O = (SELECT_I==2'b01) ?  MISO_I  : 0  ;
assign  MISO_2_O = (SELECT_I==2'b10) ?  MISO_I  : 0  ;
assign  MOSI_O   = (SELECT_I==2'b00) ? MOSI_0_I  : ( (SELECT_I==2'b01) ? MOSI_1_I : ( (SELECT_I==2'b10) ? MOSI_2_I : 0 ) );
assign  CS_O     = (SELECT_I==2'b00) ? CS_0_I  : ( (SELECT_I==2'b01) ? CS_1_I : ( (SELECT_I==2'b10) ? CS_2_I : 0 ) );
//////////////////////////////////////////////////////////////////////////////////
wire    USRCCLK;
assign  USRCCLK  = (SELECT_I==2'b00) ? CLK_0_I  : ( (SELECT_I==2'b01) ? CLK_1_I : ( (SELECT_I==2'b10) ? CLK_2_I : 0 ) );
 STARTUPE2 #(
      .PROG_USR("FALSE"),  // Activate program event security feature. Requires encrypted bitstreams.
      .SIM_CCLK_FREQ(0.0)  // Set the Configuration Clock Frequency(ns) for simulation.
    )
    STARTUPE2_u (
      .CFGCLK(CFGCLK),     // 1-bit output: Configuration main clock output
      .CFGMCLK(CFGMCLK),   // 1-bit output: Configuration internal oscillator clock output
      .EOS(EOS),           // 1-bit output: Active high output signal indicating the End Of Startup.
      .PREQ(),             // 1-bit output: PROGRAM request to fabric output
      .CLK(0),             // 1-bit input: User start-up clock input
      .GSR(0),             // 1-bit input: Global Set/Reset input (GSR cannot be used for the port name)
      .GTS(0),             // 1-bit input: Global 3-state input (GTS cannot be used for the port name)
      .KEYCLEARB(),        // 1-bit input: Clear AES Decrypter Key input from Battery-Backed RAM (BBRAM)
      .PACK(),             // 1-bit input: PROGRAM acknowledge input
      .USRCCLKO(USRCCLK),  // 1-bit input: User CCLK input
      .USRCCLKTS(0),       // 1-bit input: User CCLK 3-state enable input
      .USRDONEO(1),        // 1-bit input: User DONE pin output control
      .USRDONETS(1)        // 1-bit input: User DONE 3-state enable output
    );
//////////////////////////////////////////////////////////////////////////////////
    
    
endmodule
