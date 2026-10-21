`timescale 1ns/1ps
module tb_picture_ae;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,auto_on=0,toggle=0;
    reg [1:0] manual=2;
    reg [7:0] luma=0;
    reg [11:0] highlights=0,shadows=3600;
    wire req;wire [15:0] ae,ag;
    ae_set dut(.I_clk(clk),.I_rst(rst),.I_btn(4'd0),.I_auto_enable(auto_on),
        .I_manual_exposure_level(manual),.I_frame_luma(luma),.I_frame_highlights(highlights),
        .I_frame_shadows(shadows),.I_frame_luma_toggle(toggle),.I_ae_cfg_done(1'b1),
        .I_cam_cfg_done(1'b1),.O_ae_req(req),.O_ae(ae),.O_ag(ag));
    task wait_cycles;begin repeat(12)@(negedge clk);end endtask
    task frames(input integer count);
        integer i;begin for(i=0;i<count;i=i+1)begin toggle=~toggle;wait_cycles();end end
    endtask
    initial begin
        wait_cycles();rst=0;wait_cycles();
        manual=0;wait_cycles();if(ae!=600||ag!=16)$fatal(1,"EXP0 changed");
        manual=1;wait_cycles();if(ae!=1200||ag!=48)$fatal(1,"EXP1 changed");
        manual=2;wait_cycles();if(ae!=1990||ag!=80)$fatal(1,"EXP2 changed");
        manual=3;wait_cycles();if(ae!=1990||ag!=144)$fatal(1,"EXP3 changed");
        auto_on=1;wait_cycles();frames(16*13);
        if(ag!=176)$fatal(1,"AUTO low-light range not restored: %d",ag);
        frames(16*30);if(ag!=176||ae!=1990)$fatal(1,"AUTO ceiling violated");
        highlights=1000;wait_cycles();frames(8*45);
        if(ag!=16||ae>=1990)$fatal(1,"Severe highlight reduction failed");
        highlights=0;luma=220;shadows=0;wait_cycles();frames(16*40);
        if(ae!=300||ag!=16)$fatal(1,"Minimum exposure clamp failed");
        luma=0;shadows=3600;wait_cycles();frames(16*80);
        if(ae!=1990||ag!=176)$fatal(1,"Dark recovery/cap failed");
        auto_on=0;manual=2;wait_cycles();if(ag!=80)$fatal(1,"Manual preset restore failed");
        auto_on=1;luma=50;highlights=150;shadows=2400;wait_cycles();frames(16*8);
        if(ag<=96)$fatal(1,"Small bright patch blocked a dark scene");
        begin : hold_check
            integer held_gain;
            held_gain=ag;highlights=400;wait_cycles();frames(16*8);
            if(ag!=held_gain)$fatal(1,"Large highlight area should prevent further brightening");
            highlights=150;luma=96;shadows=1800;wait_cycles();frames(16);
            if(ag!=held_gain)$fatal(1,"Nondark luma must retain highlight hold");
            luma=50;shadows=1799;wait_cycles();frames(16);
            if(ag!=held_gain)$fatal(1,"Small shadow area must retain highlight hold");
            shadows=1800;highlights=300;wait_cycles();frames(16);
            if(ag!=held_gain)$fatal(1,"Highlight reduce boundary must retain hold");
            highlights=299;wait_cycles();frames(16);
            if(ag!=held_gain+4)$fatal(1,"Dark mixed scene boundary failed");
            held_gain=ag;highlights=120;wait_cycles();frames(16);
            if(ag!=held_gain+4)$fatal(1,"Small-highlight boundary failed");
        end
        highlights=1000;wait_cycles();frames(8*40);
        if(ag!=16)$fatal(1,"Severe highlights must reduce gain even in dark scene");
        auto_on=0;manual=3;wait_cycles();if(ag!=144)$fatal(1,"Manual high gain lost");
        rst=1;wait_cycles();if(ae!=1990||ag!=80)$fatal(1,"Reset changed");
        $display("PASS picture AE: manual presets, restored low-light gain, mixed-scene highlight policy, bright/dark clamps, reset");$finish;
    end
endmodule
