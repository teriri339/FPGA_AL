`timescale 1ns/1ps
// Exercise the unchanged fast-recovery stimulus against the released source.
module tb_template_fast_resource_equivalence #(
    parameter integer W=320,H=256,ROW_IDLE=20,ONLY_720P=0,ONLY_PHASES=0
);
    tb_template_fast_reacquire #(.W(W),.H(H),.ROW_IDLE(ROW_IDLE),
        .ONLY_720P(ONLY_720P),.ONLY_PHASES(ONLY_PHASES)) stimulus();
    wire [2:0] status;
    wire [10:0] cx,cy;
    wire busy;
    wire [3:0] reason;
    wire [14:0] best,margin;
    wire [4:0] misses;
    integer compared=0,read_compared=0;
    hx_template_tracker_fast_ref #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H)) reference_dut (
        .clk(stimulus.clk),.rst_n(stimulus.rst),.command(stimulus.command),
        .de(stimulus.de),.x(stimulus.x),.y(stimulus.y),.luma(stimulus.luma),
        .status(status),.center_x(cx),.center_y(cy),.busy(busy),
        .debug_reason(reason),.debug_best(best),.debug_margin(margin),.debug_misses(misses));
    always @(posedge stimulus.clk)begin
        #1;
        if(stimulus.rst)begin
            compared=compared+1;
            // center_x/center_y 现在带显示平滑（只影响 OSD 画框），等价性比较真实跟踪中心。
            if({status,reference_dut.cx,reference_dut.cy,busy,reason,best,margin,misses} !==
               {stimulus.dut.status,stimulus.dut.cx,stimulus.dut.cy,
                stimulus.dut.busy,stimulus.dut.debug_reason,stimulus.dut.debug_best,
                stimulus.dut.debug_margin,stimulus.dut.debug_misses} ||
                reference_dut.fast_available!==stimulus.dut.fast_available ||
                reference_dut.search_x!==stimulus.dut.search_x ||
                reference_dut.search_y!==stimulus.dut.search_y ||
                reference_dut.g_fast.u_proposer.phase!==stimulus.dut.g_fast.u_proposer.phase ||
                reference_dut.g_fast.u_proposer.tpl_ok!==stimulus.dut.g_fast.u_proposer.tpl_ok ||
                reference_dut.g_fast.u_proposer.score!==stimulus.dut.g_fast.u_proposer.score)
                $fatal(1,"Fast resource optimization changed cycle/state/score at %0d",compared);
            if(reference_dut.fast_available &&
                {reference_dut.fast_x,reference_dut.fast_y}!=={stimulus.dut.fast_x,stimulus.dut.fast_y})
                $fatal(1,"Fast proposal changed");
            if(reference_dut.g_fast.u_proposer.phase==6)begin
                read_compared=read_compared+1;
                if(reference_dut.g_fast.u_proposer.image_q!==stimulus.dut.g_fast.u_proposer.image_q)
                    $fatal(1,"Packed snapshot read differs at %0d",compared);
            end
        end
    end
    final begin
        if(compared<100000 || read_compared<10000)$error("Fast equivalence coverage insufficient");
        else $display("PASS fast resource equivalence: %0d cycles, %0d full-precision snapshot reads; exact states, fine/coarse scores, candidates and latency",compared,read_compared);
    end
endmodule
