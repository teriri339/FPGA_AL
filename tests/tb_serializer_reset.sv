`timescale 1ps/1ps
// Behavioral ODDR comparison stub. The test verifies RTL serialization/reset
// sequencing, NOT vendor I/O delays, electrical behavior, or silicon timing.
module PH1P_LOGIC_ODDR(input wire clk,rst,d0,d1,output reg q);
    always @(posedge clk or negedge clk or posedge rst)
        if(rst) q<=0; else q<=clk ? d0 : d1;
endmodule

module tb_serializer_reset;
    reg pixel_clk=0; always #10000 pixel_clk=~pixel_clk;
    reg serial_clk=0; always #2000 serial_clk=~serial_clk;
    reg rst=1;
    reg [9:0] data=10'h35a;
    wire q, q_ref;
    reg compare_enable=0;
    integer phase, checked=0;
    time last_serial_rise=0;
    lane_lvds_10_1 #(.DEVICE("PH1P")) dut(pixel_clk,serial_clk,rst,data,q);
    lane_lvds_10_1_legacy #(.DEVICE("PH1P")) ref_dut(pixel_clk,serial_clk,rst,data,q_ref);
    always @(negedge pixel_clk) data<={data[8:0],data[9]^data[6]};
    always @(posedge serial_clk) last_serial_rise=$time;
    always @(negedge dut.S_serial_rst) begin
        #1;
        if(!serial_clk || $time-last_serial_rise>2)
            $fatal(1,"Serializer reset released outside a serial clock edge");
    end
    always @(posedge serial_clk or negedge serial_clk) begin
        #10;
        if(compare_enable) begin
            if(q!==q_ref || dut.S_shift_data!==ref_dut.S_shift_data ||
               dut.S_load_en_2d!==ref_dut.S_load_en_2d)
                $fatal(1,"Serializer steady-state data/phase changed after reset");
            checked=checked+1;
        end
    end
    initial begin
        for(phase=0;phase<20;phase=phase+1) begin
            @(negedge pixel_clk); compare_enable=0; rst=1;
            repeat(3) @(negedge pixel_clk);
            #(phase*1000+1); rst=0;
            repeat(40) @(negedge serial_clk);
            #20; compare_enable=1;
            repeat(256) @(negedge serial_clk);
        end
        #20; compare_enable=0;
        if(checked<10000) $fatal(1,"Insufficient serializer comparisons");
        $display("PASS serializer reset: 20 release phases, %0d edge/data comparisons; serial-local release, legacy steady-state bit stream unchanged",checked);
        $finish;
    end
    initial begin #100000000; $fatal(1,"Timeout"); end
endmodule
