`timescale 1ns/1ps
// Bundled-data timing stress, not an analog metastability model.
// A data bit may arrive one destination sampling edge after the toggle while
// still meeting the 13.033 ns physical data bound. Consume only coherent words.
module tb_ae_cdc_coherency;
    reg clk=0; always #21 clk=~clk;
    reg rst=1;
    reg [7:0] source_luma=0;
    reg [11:0] source_high=0, source_low=0;
    reg source_toggle=0;
    wire [7:0] luma;
    wire [11:0] high_count, low_count;
    assign #13 luma[7:4]=source_luma[7:4];
    assign luma[3:0]=source_luma[3:0];
    assign #13 high_count[11:6]=source_high[11:6];
    assign high_count[5:0]=source_high[5:0];
    assign #13 low_count[11:6]=source_low[11:6];
    assign low_count[5:0]=source_low[5:0];
    wire req;
    wire [15:0] exposure, gain;
    integer checked=0, sample;
    ae_set dut(.I_clk(clk),.I_rst(rst),.I_btn(4'b1111),
        .I_auto_enable(1'b1),.I_manual_exposure_level(2'd2),
        .I_frame_luma(luma),.I_frame_highlights(high_count),
        .I_frame_shadows(low_count),.I_frame_luma_toggle(source_toggle),
        .I_ae_cfg_done(1'b1),.I_cam_cfg_done(1'b1),
        .O_ae_req(req),.O_ae(exposure),.O_ag(gain));

    always @(posedge clk) if(!rst && dut.w_new_luma) begin
        if(dut.r_luma_sync!==source_luma ||
           dut.r_highlight_sync!==source_high || dut.r_shadow_sync!==source_low)
            $fatal(1,"AE CDC consumed torn/stale statistics: got %h/%h/%h expected %h/%h/%h",
                dut.r_luma_sync,dut.r_highlight_sync,dut.r_shadow_sync,
                source_luma,source_high,source_low);
        checked=checked+1;
    end
    initial begin
        repeat(5) @(negedge clk);
        rst=0;
        for(sample=0; sample<42; sample=sample+1) begin
            // Sweep all integer-ns launch phases within a 42 ns receiver cycle.
            @(negedge clk); #(sample);
            source_luma=8'hb3 ^ (sample*19);
            source_high=12'hacd ^ (sample*97);
            source_low=12'h753 ^ (sample*53);
            source_toggle=~source_toggle;
            repeat(9) @(negedge clk);
        end
        if(checked!=42) $fatal(1,"Expected 42 statistics updates, got %0d",checked);
        $display("PASS AE CDC coherency: 42 launch phases, up to 13 ns bus skew, unchanged AE policy");
        $finish;
    end
    initial begin #100000; $fatal(1,"Timeout"); end
endmodule
