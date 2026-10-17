`timescale 1ns/1ps
// Gain-control unit test. Divider and transport are deterministic stubs below;
// this tests the actual project AWB, not demosaic, divider IP, or line RAM timing.
module tb_white_field_awb;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=0,valid=0,user=0;
    wire [95:0] fixed_rgb,auto_rgb;
    wire fixed_valid,auto_valid;
    awb #(.FIXED_GAINS(1)) fixed_dut (
        .I_clk(clk),.I_rst_n(rst),.I_tlast(1'b0),.I_tuser(user),
        .I_tdata({4{24'h321e14}}),.I_tvalid(valid),.I_tready(),
        .O_tlast(),.O_tuser(),.O_tdata(fixed_rgb),.O_tvalid(fixed_valid),.O_tready(1'b1));
    awb #(.FIXED_GAINS(0)) auto_dut (
        .I_clk(clk),.I_rst_n(rst),.I_tlast(1'b0),.I_tuser(user),
        .I_tdata({4{24'h321e14}}),.I_tvalid(valid),.I_tready(),
        .O_tlast(),.O_tuser(),.O_tdata(auto_rgb),.O_tvalid(auto_valid),.O_tready(1'b1));
    integer j;
    initial begin
        repeat(3)@(negedge clk);rst=1;valid=1;user=1;
        @(negedge clk);user=0;
        repeat(12)@(negedge clk);
        if(!fixed_valid || !auto_valid) $fatal(1,"AWB output invalid");
        if(fixed_rgb !== {4{24'h321e14}}) $fatal(1,"Fixed AWB changed pixels %h",fixed_rgb);
        if(auto_rgb !== {4{24'h641e28}}) $fatal(1,"Dynamic AWB no longer updates gains %h",auto_rgb);
        for(j=0;j<3;j=j+1)begin
            user=1;@(negedge clk);user=0;
            repeat(12)@(negedge clk);
            if(fixed_dut.in_r_r1!==20'h10000 || fixed_dut.in_b_r1!==20'h10000)
                $fatal(1,"Fixed gains changed at frame boundary");
            if(fixed_rgb !== {4{24'h321e14}}) $fatal(1,"Fixed AWB changed across frames");
            if(auto_rgb !== {4{24'h641e28}}) $fatal(1,"Dynamic AWB failed across frames");
        end
        $display("PASS: actual project AWB fixed-unity and dynamic-gain controls, 4 lanes, 4 frame boundaries (stub divider/transport)");
        $finish;
    end
endmodule
module divider(input clk,rst,start,input [31:0] denominator,
    input [47:0] numerator,output [47:0] quotient,output done);
    assign quotient=48'h20000;
    assign done=start;
endmodule
module signal_delay #(parameter IMG_HEIGHT=720,IMG_WIDTH=1280,DATA_WIDTH=96,DELAY_CYCLE=50)(
    input I_clk,I_rst_n,I_tuser,I_valid,input [DATA_WIDTH-1:0] I_data,
    output O_valid,output [DATA_WIDTH-1:0] O_data,output O_tuser);
    assign O_valid=I_valid;
    assign O_data=I_data;
    assign O_tuser=I_tuser;
endmodule
