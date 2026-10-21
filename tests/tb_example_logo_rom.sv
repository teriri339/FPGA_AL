`timescale 1ns/1ps
module tb_example_logo_rom #(
    parameter VECTOR_DIR="D:/Downloads/qiansai/tmp/example_logo_vectors_20261017_a"
);
    reg [14:0] address=0;
    wire [24:0] pixel;
    reg [24:0] expected[0:32767];
    integer i, opaque=0;
    anlogic_logo_rom dut(.I_addr(address),.O_pixel(pixel));
    initial begin
        $readmemh({VECTOR_DIR,"/logo_expected.mem"},expected);
        for(i=0;i<32768;i=i+1) begin
            address=i;
            #1;
            if(pixel !== expected[i]) $fatal(1,"Original ROM mismatch at %0d: got %h expected %h",i,pixel,expected[i]);
            if(pixel[24]) opaque=opaque+1;
        end
        if(opaque!=6387) $fatal(1,"Unexpected opaque count");
        $display("PASS original example ROM: all 32768 addresses, 6387 RGB888 pixels and transparent defaults exact");
        $finish;
    end
endmodule
