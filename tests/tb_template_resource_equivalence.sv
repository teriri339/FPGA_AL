`timescale 1ns/1ps
// Exact, cycle-by-cycle reference: the user-validated expanded-recovery release.
module tb_template_resource_equivalence;
    tb_template_expanded_reacquire stimulus();
    wire [2:0] status;
    wire [10:0] cx,cy;
    wire busy;
    wire [3:0] reason;
    wire [14:0] best,margin;
    wire [4:0] misses;
    integer compared=0,scored=0;
    hx_template_tracker_resource_ref #(.IMAGE_WIDTH(192),.IMAGE_HEIGHT(160)) reference_dut (
        .clk(stimulus.clk),.rst_n(stimulus.rst),.command(stimulus.command),
        .de(stimulus.de),.x(stimulus.x),.y(stimulus.y),.luma(stimulus.luma),
        .status(status),.center_x(cx),.center_y(cy),.busy(busy),
        .debug_reason(reason),.debug_best(best),.debug_margin(margin),.debug_misses(misses)
    );
    always @(posedge stimulus.clk)begin
        #1;
        if(stimulus.rst)begin
            compared=compared+1;
            // center_x/center_y 现在带显示平滑（只影响 OSD 画框），等价性比较真实跟踪中心。
            if({status,reference_dut.cx,reference_dut.cy,busy,reason,best,margin,misses} !==
               {stimulus.dut.status,stimulus.dut.cx,stimulus.dut.cy,
                stimulus.dut.busy,stimulus.dut.debug_reason,stimulus.dut.debug_best,
                stimulus.dut.debug_margin,stimulus.dut.debug_misses})
                $fatal(1,"Resource optimization changed observable result, frame %0d",stimulus.frames);
            if(reference_dut.phase!==stimulus.dut.phase || reference_dut.sample!==stimulus.dut.sample ||
               reference_dut.search_x!==stimulus.dut.search_x || reference_dut.search_y!==stimulus.dut.search_y ||
               reference_dut.retry_step!==stimulus.dut.retry_step)
                $fatal(1,"Resource optimization changed scheduling/latency");
            if(reference_dut.index>=128 || reference_dut.check_index>=128 || reference_dut.patch_count>=8192)
                $fatal(1,"Reference exceeded narrowed counter bounds");
            if(reference_dut.phase==3 && reference_dut.job!=0)begin
                scored=scored+1;
                if(reference_dut.patch_q!==stimulus.dut.patch_q || reference_dut.template_q!==stimulus.dut.template_q ||
                   reference_dut.score_sum!==stimulus.dut.score_sum || reference_dut.mean_sum!==stimulus.dut.mean_sum)
                    $fatal(1,"RAM data or SAD/mean arithmetic differs");
                if(reference_dut.patch_addr>=8192)$fatal(1,"Reference exceeded 13-bit read address");
            end
        end
    end
    final begin
        if(compared<50000000 || scored<1000000)$error("Insufficient equivalence coverage");
        else $display("PASS resource equivalence: %0d cycles, %0d scoring cycles; exact RAM/SAD/status/coordinates/schedule/latency",compared,scored);
    end
endmodule
