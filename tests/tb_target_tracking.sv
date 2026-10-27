`timescale 1ns/1ps
// Full RGB frames, real vendor ERAM timing; no forced detector statistics.
module tb_target_tracking #(parameter integer HOLD_FRAMES=10);
    localparam W=96, H=96, ACQUIRE=800, RELEASE=400;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=0, de=0, user=0, last=0;
    reg [23:0] rgb=0;
    wire found;
    wire [23:0] pixels;
    hx_vision_pipeline #(.ENABLE_RAW_SHARPEN(0),
        .IMAGE_WIDTH(W), .MIN_TARGET_PIXELS(ACQUIRE), .TARGET_RELEASE_PIXELS(RELEASE),
        .TARGET_HOLD_FRAMES(HOLD_FRAMES), .ENABLE_ANLOGIC_LOGO(0), .ENABLE_EDGE_REFINEMENT(0)
    ) dut (
        .I_clk(clk), .I_rst_n(rst), .I_vsync(1'b0), .I_hsync(1'b0),
        .I_de(de), .I_user(user), .I_last(last), .I_rgb(rgb), .I_mode(3'd2),
        .I_exposure_level(2'd0), .I_auto_exposure(1'b1), .I_raw_sharpen_enable(1'b0), .I_template_command(1'b0),
        .I_applied_exposure(16'd0), .I_applied_gain_regs(24'd0), .I_applied_status(2'd0),
        .I_applied_has_value(1'b0), .I_applied_update_toggle(1'b0), .I_cal_status(2'd0),
        .O_target_found(found), .O_target_pixels(pixels),
        .O_vsync(), .O_hsync(), .O_de(), .O_user(), .O_last(), .O_rgb(),
        .O_frame_luma(), .O_frame_highlights(), .O_frame_shadows(), .O_frame_luma_toggle()
    );

    integer pending_count=0, pending_color=0;
    integer px0=0, px1=0, py0=0, py1=0;
    reg expected_found=0, expected_fresh=0;
    integer misses=0, expected_color=0, bx0=0, bx1=0, by0=0, by1=0;
    integer frames=0, tracked=0, held=0, lost=0, received=0;
    integer xx, yy, n;
    reg [31:0] rng=32'h190617ab;
    reg [10:0] probe_x=0, probe_y=0;

    // Independent decimal conversion (not the RTL's double-dabble algorithm).
    function automatic [23:0] decimal_bcd(input integer value);
        integer digit, remaining;
        begin
            decimal_bcd=0;
            remaining=value;
            for(digit=0;digit<6;digit=digit+1) begin
                decimal_bcd[digit*4 +:4]=remaining%10;
                remaining=remaining/10;
            end
        end
    endfunction

    task idle;
        begin @(posedge clk); #2; de=0; user=0; last=0; rgb=0; end
    endtask

    task check_publication;
        reg [15:0] expected_x_bcd, expected_y_bcd;
        begin
            expected_fresh=(pending_count>0 && pending_count >= (expected_found ? RELEASE : ACQUIRE));
            if(expected_fresh) begin
                if(expected_found) begin
                    bx0=(bx0+px0)/2; bx1=(bx1+px1)/2;
                    by0=(by0+py0)/2; by1=(by1+py1)/2;
                end else begin bx0=px0; bx1=px1; by0=py0; by1=py1; end
                expected_found=1;
                expected_color=pending_color;
                misses=0;
                tracked=tracked+1;
            end else if(expected_found && misses<HOLD_FRAMES) begin
                misses=misses+1;
                held=held+1;
            end else begin
                expected_found=0;
                expected_color=0;
                bx0=0; bx1=0; by0=0; by1=0; misses=0;
                lost=lost+1;
            end
            expected_x_bcd=decimal_bcd((bx0+bx1)/2);
            expected_y_bcd=decimal_bcd((by0+by1)/2);
            if(found !== expected_found || dut.target_fresh !== expected_fresh || pixels !== pending_count)
                $fatal(1,"Frame %0d state/count mismatch: found=%b fresh=%b pixels=%0d expected=%b/%b/%0d",
                       frames,found,dut.target_fresh,pixels,expected_found,expected_fresh,pending_count);
            if(dut.target_miss_count !== misses || dut.box_color !== expected_color ||
               dut.box_xmin !== bx0 || dut.box_xmax !== bx1 || dut.box_ymin !== by0 || dut.box_ymax !== by1)
                $fatal(1,"Frame %0d stale box/colour or wrong hold budget",frames);
            if(dut.center_x_bcd !== expected_x_bcd || dut.center_y_bcd !== expected_y_bcd ||
               dut.pixel_count_bcd !== decimal_bcd(pending_count))
                $fatal(1,"Frame %0d BCD mismatch (area must always be the actual measurement)",frames);
            frames=frames+1;
        end
    endtask

    task check_osd;
        integer col;
        reg [39:0] state_text;
        reg [23:0] expected_fg;
        reg [7:0] expected_char;
        begin
            state_text=!expected_found ? "LOST " : expected_fresh ? "TRACK" : "HOLD ";
            expected_fg=!expected_found ? 24'hff6060 : expected_fresh ? 24'h60ff60 : 24'hffb040;
            // Read-only overlay probes during blanking; detector inputs/statistics remain untouched.
            force dut.draw_x=probe_x;
            force dut.draw_y=probe_y;
            for(col=0;col<5;col=col+1) begin
                probe_x=(22+col)*16; probe_y=0;
                #1;
                if(dut.osd_char !== state_text[39-col*8 -:8] || dut.osd_fg !== expected_fg)
                    $fatal(1,"Frame %0d status label/colour mismatch",frames);
            end
            probe_y=16; probe_x=2*16;
            #1;
            expected_char=!expected_found ? "-" : expected_color==1 ? "R" : expected_color==2 ? "G" : "B";
            if(dut.osd_char !== expected_char || dut.osd_fg !== expected_fg)
                $fatal(1,"Held C is not labelled correctly");
            for(col=0;col<6;col=col+1) begin
                probe_x=(20+col)*16;
                expected_char="0"+(pending_count/(10**(5-col)))%10;
                #1;
                if(dut.osd_char !== expected_char) $fatal(1,"P is stale/hidden in HOLD or LOST");
            end
            // Probe a box pixel below the text region, including the actual glyph/background gates.
            probe_x=bx0; probe_y=by0;
            force dut.stage_de=1'b1;
            #1;
            if(expected_found && (!dut.box_border || dut.overlay_rgb !== (expected_fresh ? 24'hffff00 : 24'hffb040)))
                $fatal(1,"Fresh/held box colour mismatch");
            if(!expected_found && dut.box_border) $fatal(1,"Lost box still visible");
            release dut.draw_x;
            release dut.draw_y;
            release dut.stage_de;
        end
    endtask

    task frame(input integer rw, rh, colour, ox);
        reg [23:0] target_rgb;
        begin
            target_rgb=colour==1 ? 24'he01010 : colour==2 ? 24'h10e010 : 24'h1010e0;
            for(yy=0;yy<H;yy=yy+1) begin
                for(xx=0;xx<W;xx=xx+1) begin
                    @(posedge clk); #1;
                    if(xx==1 && yy==0) check_publication();
                    #1;
                    de=1; user=(xx==0 && yy==0); last=(xx==W-1);
                    rgb=(xx>=ox && xx<ox+rw && yy>=40 && yy<40+rh) ? target_rgb : 24'h202020;
                    received=received+1;
                end
                repeat(4) idle();
            end
            // A solid rectangle survives the causal colour filter except its first row/column.
            if(dut.cur_count !== ((rw>1 && rh>1) ? (rw-1)*(rh-1) : 0))
                $fatal(1,"Real RGB colour-neighbour count differs from independent rectangle oracle");
            repeat(6) idle();
            check_osd(); // This frame's public results still describe the preceding completed frame.
            pending_count=(rw>1 && rh>1) ? (rw-1)*(rh-1) : 0;
            pending_color=colour;
            px0=ox+1; px1=ox+rw-1; py0=41; py1=40+rh-1;
        end
    endtask

    task reset_tracker;
        begin
            idle(); rst=0;
            repeat(4) idle();
            if(found !== 0 || pixels !== 0 || dut.target_fresh !== 0 || dut.target_miss_count !== 0)
                $fatal(1,"Reset did not clear tracking state");
            if(dut.box_color !== 0 || dut.center_x_bcd !== 0 || dut.center_y_bcd !== 0 ||
               dut.pixel_count_bcd !== 0 || dut.box_xmin !== 0 || dut.box_ymin !== 0 ||
               dut.box_xmax !== 0 || dut.box_ymax !== 0)
                $fatal(1,"Reset left stale colour/coordinates/area");
            expected_found=0; expected_fresh=0; misses=0; expected_color=0;
            bx0=0; bx1=0; by0=0; by1=0; pending_count=0;
            #1; rst=1;
        end
    endtask

    initial begin
        reset_tracker();
        frame(0,0,1,8);
        frame(18,48,1,8); // 799: cannot acquire.
        frame(41,21,1,8); // 800: acquire at the exact boundary.
        frame(18,48,1,9); // 799: remain locked via hysteresis.
        frame(41,11,1,10); // 400: update at exact release threshold.
        frame(20,22,3,11); // 399: hold previous red C/X/Y, never publish this blue candidate.
        for(n=0;n<HOLD_FRAMES+2;n=n+1) frame(0,0,1,8);
        frame(41,11,2,8); // 400 cannot acquire once lost.
        frame(41,21,2,8);
        frame(0,0,1,8);
        frame(41,11,2,10); // Recover before expiry when holding is enabled.
        frame(41,21,3,12);
        frame(0,0,1,8);
        frame(0,0,1,8); // Publish a miss before reset, exercising HOLD reset too.
        if(HOLD_FRAMES>0 && (!found || dut.target_fresh)) $fatal(1,"HOLD reset case not reached");
        reset_tracker();
        frame(41,11,1,8);
        frame(41,21,1,8);
        // Long disappearance must not wrap the miss counter and resurrect a lock.
        for(n=0;n<35;n=n+1) frame(0,0,1,8);
        for(n=0;n<24;n=n+1) begin
            rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            frame(8+rng[4:0],8+rng[9:5],1+(rng[11:10]%3),4+rng[15:12]);
        end
        frame(0,0,1,8); // Publish the last random frame.
        frame(41,21,1,8);
        frame(0,0,1,8); // Ensure reset test starts with a live lock.
        reset_tracker();
        if(tracked<6 || lost<30 || (HOLD_FRAMES>0 && held==0)) $fatal(1,"Insufficient state coverage");
        $display("PASS target tracking HOLD=%0d: %0d publications, %0d RGB pixels, TRACK=%0d HOLD=%0d LOST=%0d; exact thresholds, recovery, expiry, reset, actual P and OSD verified",
                 HOLD_FRAMES,frames,received,tracked,held,lost);
        $finish;
    end
endmodule
