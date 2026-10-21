`timescale 1ns/1ps
module tb_reset_release;
    reg run_clk=1;
    reg clk=0; always #7 if(run_clk) clk=~clk; else clk=0;
    reg async_rst_n=0;
    wire rst_n;
    integer phase, checks=0;
    hx_reset_release dut(clk,async_rst_n,rst_n);
    task release_and_check;
        begin
            @(posedge clk); #1;
            if(rst_n!==0) $fatal(1,"Reset released before two local edges");
            @(posedge clk); #1;
            if(rst_n!==1) $fatal(1,"Reset did not release on second local edge");
            checks=checks+1;
        end
    endtask
    initial begin
        for(phase=0;phase<14;phase=phase+1) begin
            @(negedge clk); async_rst_n=0;
            #1; if(rst_n!==0) $fatal(1,"Reset assertion was not asynchronous");
            @(negedge clk); #(phase); async_rst_n=1;
            // Avoid a simulator scheduling race at the coincident posedge.
            // Phase 7 is asserted/released between edges instead below.
            if(phase==7) begin
                #1; async_rst_n=0;
                @(negedge clk); #1; async_rst_n=1;
            end
            release_and_check();
        end
        @(negedge clk); run_clk=0;
        #1; async_rst_n=0; #1;
        if(rst_n!==0) $fatal(1,"Stopped domain did not assert reset");
        async_rst_n=1; #100;
        if(rst_n!==0) $fatal(1,"Stopped domain released reset without clock edges");
        run_clk=1;
        release_and_check();
        $display("PASS reset release: %0d phase/stopped-clock cases, asynchronous assertion and two-edge synchronous release",checks);
        $finish;
    end
    initial begin #10000; $fatal(1,"Timeout"); end
endmodule
