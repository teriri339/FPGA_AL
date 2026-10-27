`timescale 1ns/1ps
// Reuse the complete recovery stimulus, compare after BOTH engines finish.
module tb_template_pipeline_equivalence;
    tb_template_reacquire stimulus();
    wire [2:0] status;
    wire [10:0] cx,cy;
    wire busy;
    wire [3:0] reason;
    wire [14:0] best,margin;
    wire [4:0] misses;
    reg prev_fast=0,prev_slow=0,done_fast=0,done_slow=0,checked=0;
    integer comparisons=0,i;
    hx_template_tracker_serial_ref #(.IMAGE_WIDTH(320),.IMAGE_HEIGHT(192)) reference_dut (
        .clk(stimulus.clk),.rst_n(stimulus.rst),.command(stimulus.command),
        .de(stimulus.de),.x(stimulus.x),.y(stimulus.y),.luma(stimulus.luma),
        .status(status),.center_x(cx),.center_y(cy),.busy(busy),
        .debug_reason(reason),.debug_best(best),.debug_margin(margin),.debug_misses(misses)
    );
    always @(posedge stimulus.clk) begin
        #1;
        if(!stimulus.rst || stimulus.command || (stimulus.de && stimulus.x==0 && stimulus.y==0))begin
            done_fast=0;done_slow=0;checked=0;
        end else begin
            if(prev_fast && !stimulus.dut.busy)done_fast=1;
            if(prev_slow && !busy)done_slow=1;
            if(done_fast && done_slow && !checked)begin
                checked=1;comparisons=comparisons+1;
                // center_x/center_y 现在带显示平滑（只影响 OSD 画框），等价性比较真实的
                // 跟踪中心 cx/cy，保持对搜索/判定行为的严格约束。
                if({status,reference_dut.cx,reference_dut.cy,reason,best,margin,misses} !==
                   {stimulus.dut.status,stimulus.dut.cx,stimulus.dut.cy,
                    stimulus.dut.debug_reason,stimulus.dut.debug_best,
                    stimulus.dut.debug_margin,stimulus.dut.debug_misses})
                    $fatal(1,"Serial/pipeline result mismatch at frame %0d",stimulus.frames);
                for(i=0;i<64;i=i+1)
                    if(reference_dut.template_mem[i] !== stimulus.dut.template_mem[i])
                        $fatal(1,"Template mismatch sample %0d",i);
                if(stimulus.dut.job==2)
                    for(i=0;i<81;i=i+1)
                        if(reference_dut.coarse_scores[i] !== stimulus.dut.coarse_scores[i])
                            $fatal(1,"Zero-mean SAD mismatch candidate %0d",i);
            end
        end
        prev_fast=stimulus.dut.busy;prev_slow=busy;
    end
    final begin
        if(comparisons<80)$error("Insufficient serial/pipeline comparisons: %0d",comparisons);
        else $display("PASS serial/pipeline equivalence: %0d completed jobs, exact SAD/OSD/status/template",comparisons);
    end
endmodule
