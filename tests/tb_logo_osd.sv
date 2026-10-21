`timescale 1ns/1ps
module tb_logo_osd #(
    parameter VECTOR_DIR="D:/Downloads/qiansai/tmp/example_logo_vectors_20261017_a",
    parameter QUALITY_ENABLE=0
);
    localparam W=1280, H=192, LOGO_X=W-176, LAT=2054;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=0, de=0, user=0, last=0, vs=0, hs=0;
    reg [23:0] rgb=0;
    reg [1:0] mode=0, exposure=0;
    reg auto_exp=1;
    wire [23:0] shown_rgb, plain_rgb;
    wire [4:0] shown_ctrl, plain_ctrl;
    wire [57:0] shown_stats, plain_stats;
    hx_vision_pipeline #(.ENABLE_DISPLAY_DENOISE(QUALITY_ENABLE), .ENABLE_SHADOW_LIFT(QUALITY_ENABLE)) with_overlay (
        .I_clk(clk), .I_rst_n(rst), .I_vsync(vs), .I_hsync(hs), .I_de(de), .I_user(user), .I_last(last),
        .I_rgb(rgb), .I_mode(mode), .I_exposure_level(exposure), .I_auto_exposure(auto_exp),
        .I_raw_sharpen_enable(1'b0), .I_template_command(1'b0), .I_applied_exposure(16'd0), .I_applied_gain_regs(24'd0),
        .I_applied_status(2'd0), .I_applied_has_value(1'b0), .I_applied_update_toggle(1'b0), .I_cal_status(2'd0),
        .O_vsync(shown_ctrl[4]), .O_hsync(shown_ctrl[3]), .O_de(shown_ctrl[2]), .O_user(shown_ctrl[1]), .O_last(shown_ctrl[0]),
        .O_rgb(shown_rgb), .O_target_found(shown_stats[57]), .O_target_pixels(shown_stats[56:33]),
        .O_frame_luma(shown_stats[32:25]), .O_frame_highlights(shown_stats[24:13]),
        .O_frame_shadows(shown_stats[12:1]), .O_frame_luma_toggle(shown_stats[0])
    );
    hx_vision_pipeline #(.ENABLE_STATUS_OSD(0), .ENABLE_ANLOGIC_LOGO(0), .ENABLE_DISPLAY_DENOISE(QUALITY_ENABLE), .ENABLE_SHADOW_LIFT(QUALITY_ENABLE)) without_overlay (
        .I_clk(clk), .I_rst_n(rst), .I_vsync(vs), .I_hsync(hs), .I_de(de), .I_user(user), .I_last(last),
        .I_rgb(rgb), .I_mode(mode), .I_exposure_level(exposure), .I_auto_exposure(auto_exp),
        .I_raw_sharpen_enable(1'b0), .I_template_command(1'b0), .I_applied_exposure(16'd0), .I_applied_gain_regs(24'd0),
        .I_applied_status(2'd0), .I_applied_has_value(1'b0), .I_applied_update_toggle(1'b0), .I_cal_status(2'd0),
        .O_vsync(plain_ctrl[4]), .O_hsync(plain_ctrl[3]), .O_de(plain_ctrl[2]), .O_user(plain_ctrl[1]), .O_last(plain_ctrl[0]),
        .O_rgb(plain_rgb), .O_target_found(plain_stats[57]), .O_target_pixels(plain_stats[56:33]),
        .O_frame_luma(plain_stats[32:25]), .O_frame_highlights(plain_stats[24:13]),
        .O_frame_shadows(plain_stats[12:1]), .O_frame_luma_toggle(plain_stats[0])
    );
    reg [24:0] logo_expected[0:32767];
    integer qptr=0,out_idx=0;
    integer sx=0, sy=0, sf=0, cx[0:LAT-1], cy[0:LAT-1], cf[0:LAT-1];
    reg valid[0:LAT-1];
    integer k, xx, yy, f, checked=0, logo_count=0, transparent_count=0, cyan_count=0, red_count=0, green_count=0, applied_status_count=0;
    reg logo_region, logo_visible;
    reg [24:0] expected_logo;
    integer ppm;
    function [23:0] raw_expected(input integer px,py);
        integer v;
        begin
            v=(px+py)%192+32;
            if(QUALITY_ENABLE)begin
                if(px>0 && py>0 && v>=34)v=v-1;
                if(v<64)v=v+v/4;else if(v<128)v=v+(128-v)/4;
            end
            raw_expected=v*24'h010101;
        end
    endfunction
    always @(posedge clk) begin
        if (!rst) begin
            for(k=0;k<LAT;k=k+1) begin cx[k]=0; cy[k]=0; cf[k]=0; valid[k]=0; end
        end else begin
            cx[qptr]=sx; cy[qptr]=sy; cf[qptr]=sf; valid[qptr]=de;
            out_idx=(qptr+1)%LAT; qptr=out_idx;
            #1;
            if (shown_ctrl !== plain_ctrl || shown_stats !== plain_stats) $fatal(1,"Overlay changed control/target/AE statistics");
            if (shown_ctrl[2] !== valid[out_idx]) $fatal(1,"Centered display latency mismatch");
            if (valid[out_idx]) begin
                checked=checked+1;
                logo_region=(cx[out_idx]>=LOGO_X && cx[out_idx]<LOGO_X+160 && cy[out_idx]>=8 && cy[out_idx]<168);
                expected_logo=logo_region ? logo_expected[(cy[out_idx]-8)*160+cx[out_idx]-LOGO_X] : 25'd0;
                logo_visible=logo_region && expected_logo[24];
                if (logo_region && !logo_visible) transparent_count=transparent_count+1;
                if (logo_visible) begin
                    if (shown_rgb !== expected_logo[23:0])
                        $fatal(1,"Logo pixel mismatch at (%0d,%0d): got %h expected %h",cx[out_idx],cy[out_idx],shown_rgb,
                               expected_logo[23:0]);
                    logo_count=logo_count+1;
                end else if((cx[out_idx]<432 && cy[out_idx]<32) || (cx[out_idx]>=480 && cx[out_idx]<864 && cy[out_idx]<16)) begin
                    if (shown_rgb==24'h40e0ff) cyan_count=cyan_count+1;
                    else if(shown_rgb==24'hff6060) red_count=red_count+1;
                    else if(shown_rgb==24'h60ff60) green_count=green_count+1;
                    else if(shown_rgb==24'hc0c0c0) applied_status_count=applied_status_count+1;
                    else if(shown_rgb!==24'h101018) $fatal(1,"Unexpected OSD status colour");
                    if (cx[out_idx]==10 && shown_rgb!==24'h101018) $fatal(1,"Glyph spacing/background mismatch");
                    if (cx[out_idx]==0 && cy[out_idx]==0 && shown_rgb!==24'h40e0ff) $fatal(1,"MODE first glyph missing");
                end else begin
                    if(shown_rgb !== plain_rgb) $fatal(1,"Image changed outside overlay at %0d,%0d",cx[out_idx],cy[out_idx]);
                    if(cf[out_idx]==0 && shown_rgb !== raw_expected(cx[out_idx],cy[out_idx]))
                        $fatal(1,"RAW pixel is not aligned to the three-stage video controls");
                    if(cf[out_idx]==1 && shown_rgb !== 24'h828282) $fatal(1,"GRAY changed");
                end
                if(cf[out_idx]==3) $fwrite(ppm,"%c%c%c",shown_rgb[23:16],shown_rgb[15:8],shown_rgb[7:0]);
            end else if (shown_rgb !== 24'h0) $fatal(1,"Overlay leaked into blanking");
        end
    end
    task idle;
        begin @(posedge clk); #2; de=0; user=0; last=0; hs=0; vs=0; end
    endtask
    initial begin
        $readmemh({VECTOR_DIR,"/logo_expected.mem"},logo_expected);
        ppm=$fopen({VECTOR_DIR,"/overlay_preview.ppm"},"wb");
        if(ppm==0) $fatal(1,"Cannot open preview");
        $fwrite(ppm,"P6\n%0d %0d\n255\n",W,H);
        repeat(5) @(negedge clk);
        #1; rst=1;
        for(f=0;f<4;f=f+1) begin
            repeat(10) idle();
            mode=f; exposure=f; auto_exp=(f==0);
            for(yy=0;yy<H;yy=yy+1) begin
                for(xx=0;xx<W;xx=xx+1) begin
                    @(posedge clk); #2;
                    sx=xx; sy=yy; sf=f;
                    de=1; user=(xx==0 && yy==0); last=(xx==W-1); hs=(xx<4); vs=(yy==0);
                    case(f)
                        0: rgb=((xx+yy)%192+32)*24'h010101;
                        1: rgb=24'h10d020;
                        2: rgb=24'h2010d0;
                        default: rgb=((xx/16+yy/16)%2) ? 24'hffffff : 24'h000000;
                    endcase
                end
                repeat(20) idle();
            end
        end
        repeat(LAT+10) idle();
        $fclose(ppm);
        if(checked!=4*W*H || logo_count!=4*6387 || transparent_count!=4*(160*160-6387) || cyan_count==0 || red_count==0 || green_count==0 || applied_status_count==0)
            $fatal(1,"Coverage count mismatch pixels=%0d logo=%0d cyan=%0d red=%0d green=%0d",checked,logo_count,cyan_count,red_count,green_count);
        $display("PASS original example logo/OSD: %0d pixels; %0d original RGB pixels; %0d transparent pixels; status cyan=%0d red=%0d green=%0d applied=%0d; underlying image and statistics unchanged",
                 checked,logo_count,transparent_count,cyan_count,red_count,green_count,applied_status_count);
        $finish;
    end
    initial begin #100000000; $fatal(1,"Timeout"); end
endmodule
