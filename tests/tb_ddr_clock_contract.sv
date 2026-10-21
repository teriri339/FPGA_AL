`timescale 1ps/1ps
// Parameter-level check of the vendor DDR2 initialization module. This is not
// a DDR memory/PHY analog simulation or a substitute for a board memory test.
module tb_ddr_clock_contract;
    parameter integer TCK=1875;
    localparam integer ACTUAL_TCK=1875; // 100 MHz *32 /3 /2 =533.333 MHz.
    wire done, phy_rst, valid;
    wire [31:0] code;
    wire [12:0] mr1;
    ph1p_ddrphy_dram_init #(.tCK(TCK),.CL(7),.CWL(6)) dut(
        .clk(1'b0),.rst_n(1'b0),.start(1'b0),.done(done),
        .phy_rst_n(phy_rst),.cmd_vld(valid),.cmd_code(code),.mr1(mr1));
    initial begin
        #1;
        if(TCK!=ACTUAL_TCK)
            $fatal(1,"DDR tCK contract mismatch: parameter=%0d ps actual=%0d ps; WR=%0d cycles gives %0d ps versus 15000 ps minimum",TCK,ACTUAL_TCK,dut.nWR,dut.nWR*ACTUAL_TCK);
        if(dut.nWR*ACTUAL_TCK<15000 || dut.nWR!=8 || dut.MR0_WR!==3'b111)
            $fatal(1,"DDR write recovery encoding does not satisfy vendor module's 15 ns minimum");
        $display("PASS DDR clock contract: 533.333 MHz, tCK=1875 ps, MR0 write recovery=8 cycles / 15000 ps");
        $finish;
    end
endmodule
