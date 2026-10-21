`timescale 1ns/1ps
module tb_raw_sharpen #(parameter integer ROW_IDLE_CYCLES=3, W=64, H=40);
    localparam LAT=2054;
    reg clk=0; always #5 clk=~clk;
    reg rst=0, de=0, user=0, last=0, vs=0, hs=0;
    reg [23:0] rgb=0;
    reg [1:0] mode=0;
    reg sharpen=0;
    wire [23:0] sharp_rgb, ref_rgb;
    wire [4:0] sharp_ctrl, ref_ctrl;
    wire [57:0] sharp_stats, ref_stats;

    hx_vision_pipeline #(.IMAGE_WIDTH(W), .ENABLE_RAW_SHARPEN(1),
        .ENABLE_STATUS_OSD(0), .ENABLE_ANLOGIC_LOGO(0)) dut (
        .I_clk(clk), .I_rst_n(rst), .I_vsync(vs), .I_hsync(hs), .I_de(de), .I_user(user), .I_last(last),
        .I_rgb(rgb), .I_mode(mode), .I_exposure_level(2'd2), .I_auto_exposure(1'b1),
        .I_raw_sharpen_enable(sharpen), .I_template_command(1'b0), .I_applied_exposure(16'd0), .I_applied_gain_regs(24'd0),
        .I_applied_status(2'd0), .I_applied_has_value(1'b0), .I_applied_update_toggle(1'b0), .I_cal_status(2'd0),
        .O_vsync(sharp_ctrl[4]), .O_hsync(sharp_ctrl[3]), .O_de(sharp_ctrl[2]),
        .O_user(sharp_ctrl[1]), .O_last(sharp_ctrl[0]), .O_rgb(sharp_rgb),
        .O_target_found(sharp_stats[57]), .O_target_pixels(sharp_stats[56:33]),
        .O_frame_luma(sharp_stats[32:25]), .O_frame_highlights(sharp_stats[24:13]),
        .O_frame_shadows(sharp_stats[12:1]), .O_frame_luma_toggle(sharp_stats[0])
    );
    hx_vision_pipeline #(.IMAGE_WIDTH(W), .ENABLE_RAW_SHARPEN(1),
        .ENABLE_STATUS_OSD(0), .ENABLE_ANLOGIC_LOGO(0)) reference (
        .I_clk(clk), .I_rst_n(rst), .I_vsync(vs), .I_hsync(hs), .I_de(de), .I_user(user), .I_last(last),
        .I_rgb(rgb), .I_mode(mode), .I_exposure_level(2'd2), .I_auto_exposure(1'b1),
        .I_raw_sharpen_enable(1'b0), .I_template_command(1'b0), .I_applied_exposure(16'd0), .I_applied_gain_regs(24'd0),
        .I_applied_status(2'd0), .I_applied_has_value(1'b0), .I_applied_update_toggle(1'b0), .I_cal_status(2'd0),
        .O_vsync(ref_ctrl[4]), .O_hsync(ref_ctrl[3]), .O_de(ref_ctrl[2]),
        .O_user(ref_ctrl[1]), .O_last(ref_ctrl[0]), .O_rgb(ref_rgb),
        .O_target_found(ref_stats[57]), .O_target_pixels(ref_stats[56:33]),
        .O_frame_luma(ref_stats[32:25]), .O_frame_highlights(ref_stats[24:13]),
        .O_frame_shadows(ref_stats[12:1]), .O_frame_luma_toggle(ref_stats[0])
    );

    reg [7:0] image[0:H-1][0:W-1];
    reg [4:0] ctrl_q[0:LAT-1];
    reg [1:0] mode_q[0:LAT-1];
    reg sharp_q[0:LAT-1];
    reg [23:0] pixel_q[0:LAT-1];
    integer qptr=0,out_idx=0;
    integer mx=0, my=0, i, j, c, gray, blur_sum, blur, hp, amount, value;
    integer checked=0, raw_checked=0, flat_changed=0, detailed_changed=0, noise_max=0, boundary=0;
    integer frame_id, xx, yy, sample_value;
    reg [23:0] expected_pixel;
    reg [31:0] rng=32'h8f31c2a5;

    function [23:0] scene(input integer f, input integer sx, input integer sy);
        case(f)
            0:scene=(96+(sx*3+sy*5)%7-3)*24'h010101;
            1:scene=((sx==12 || sx==13 || sy==18 || (sx>=24 && sx<28 && sy>=10 && sy<30)) ? 24'he8e8e8 : 24'h202020);
            2:scene=((sx==31 && sy==20) || (sx==40 && sy==10) ? 24'hffffff : 24'h404040);
            3:scene=(sx<32 ? 24'h000000 : 24'hffffff);
            4:scene=(sx<32 ? 24'h7090b0 : 24'h303030);
            8:scene=((sx*5+sy*3)%240)*24'h010101;
            9:scene=((sx==W-13 || sx==W-14 || sy==H-19) ? 24'he0e0e0 : 24'h303030);
            default:scene=((sx+sy)%7<3 ? 24'hd02030 : 24'h2030d0);
        endcase
    endfunction

    function integer gray_ref(input [23:0] p);
        begin gray_ref=(p[23:16]*77+p[15:8]*150+p[7:0]*29)/256; end
    endfunction
    function [7:0] sat_channel(input [7:0] channel, input integer delta);
        integer t;
        begin
            t=channel+delta;
            if(t<0) sat_channel=0;
            else if(t>255) sat_channel=255;
            else sat_channel=t[7:0];
        end
    endfunction

    always @(posedge clk) begin
        if (!rst) begin
            mx=0; my=0; qptr=0; out_idx=0;
            for(i=0;i<LAT;i=i+1) begin ctrl_q[i]=0; mode_q[i]=0; sharp_q[i]=0; pixel_q[i]=0; end
            for(i=0;i<H;i=i+1) for(j=0;j<W;j=j+1) image[i][j]=0;
        end else begin
            ctrl_q[qptr]={vs,hs,de,user,last};
            mode_q[qptr]=mode;
            sharp_q[qptr]=sharpen;
            pixel_q[qptr]=0;
            if(de) begin
                if(user) begin mx=0; my=0; end
                gray=gray_ref(rgb);
                if(mode==0 && sharpen && (mx==0 || my==0 || mx==W-1 || my==H-1)) boundary=boundary+1;
                expected_pixel=rgb;
                if(mode==1) expected_pixel=gray*24'h010101;
                if(mode==0 && sharpen && mx>0 && my>0 && mx<W-1 && my<H-1 && !(frame_id==4 && mx>=31)) begin
                    // Independent, CENTERED model uses future rows/columns.
                    blur_sum=gray_ref(scene(frame_id,mx-1,my-1))+2*gray_ref(scene(frame_id,mx,my-1))+gray_ref(scene(frame_id,mx+1,my-1))+
                             2*gray_ref(scene(frame_id,mx-1,my))+4*gray+2*gray_ref(scene(frame_id,mx+1,my))+
                             gray_ref(scene(frame_id,mx-1,my+1))+2*gray_ref(scene(frame_id,mx,my+1))+gray_ref(scene(frame_id,mx+1,my+1));
                    blur=blur_sum/16;
                    hp=gray-blur;
                    if(hp<0)amount=(-hp>6)?((-hp-6)/2):0;
                    else amount=(hp>6)?((hp-6)/2):0;
                    if(amount>8)amount=8;
                    if(amount>0 || hp<0 && (-hp)>6) begin
                        if(hp<0)amount=-amount;
                        expected_pixel={sat_channel(rgb[23:16],amount),sat_channel(rgb[15:8],amount),sat_channel(rgb[7:0],amount)};
                    end
                    if(frame_id==0 && expected_pixel!==rgb) flat_changed=flat_changed+1;
                    if((frame_id==1 || frame_id==2 || frame_id==3) && expected_pixel!==rgb) detailed_changed=detailed_changed+1;
                    if(frame_id==2) begin
                        for(c=0;c<3;c=c+1) begin
                            value=(expected_pixel>>(c*8))&255;
                            sample_value=(rgb>>(c*8))&255;
                            if(value-sample_value>noise_max)noise_max=value-sample_value;
                            if(sample_value-value>noise_max)noise_max=sample_value-value;
                        end
                    end
                end
                pixel_q[qptr]=expected_pixel;
                image[my][mx]=gray;
                if(last)begin mx=0;my=my+1;end else mx=mx+1;
            end
            out_idx=(qptr+1)%LAT; qptr=out_idx;
            #1;
            if(sharp_ctrl!==ref_ctrl)$fatal(1,"Video control signals diverged");
            if(sharp_stats!==ref_stats)$fatal(1,"RAW sharp display altered exposure/target statistics");
            if(sharp_ctrl!==ctrl_q[out_idx])$fatal(1,"Lookahead RGB/control alignment changed");
            if(sharp_ctrl[2])begin
                checked=checked+1;
                if(mode_q[out_idx]<2)begin
                    if(sharp_rgb!==pixel_q[out_idx])$fatal(1,"Centered RAW/GRAY mismatch at output %0d mode %0d sharp %0d: got %h expected %h",checked,mode_q[out_idx],sharp_q[out_idx],sharp_rgb,pixel_q[out_idx]);
                    if(mode_q[out_idx]==0)begin
                        raw_checked=raw_checked+1;
                        if(!sharp_q[out_idx] && sharp_rgb!==ref_rgb)$fatal(1,"Bypass RAW pixels changed");
                    end
                end else if(sharp_rgb!==ref_rgb)$fatal(1,"COLOR/CANNY were modified by the RAW-only sharpener");
            end else if(sharp_rgb!==0)$fatal(1,"Blanking RGB must remain zero");
        end
    end

    task idle;
        begin @(posedge clk); #2; de=0; user=0; last=0; vs=0; hs=0; rgb=0; end
    endtask

    task frame(input integer f);
        begin
            frame_id=f;
            repeat(6) idle();
            for(yy=0;yy<H;yy=yy+1) begin
                for(xx=0;xx<W;xx=xx+1) begin
                    @(posedge clk); #2;
                    de=1; user=(xx==0 && yy==0); last=(xx==W-1); vs=(yy==0); hs=(xx<2);
                    rgb=scene(f,xx,yy);
                    mode=(f==4 && xx>=32) ? 2'd1 : (f==5 ? 2'd2 : (f==6 ? 2'd3 : 2'd0));
                    sharpen=(f!=7) && !(f==9 && xx>=32); // Mid-line switch must travel with its pixel.
                    if(xx==7 && yy==8) idle(); // A DE gap must not corrupt line/history alignment.
                end
                repeat(ROW_IDLE_CYCLES) idle();
            end
        end
    endtask

    initial begin
        repeat(5) idle(); rst=1;
        frame(0); // Flat field with low-amplitude grain: all detail stays below the noise gate.
        frame(1); // Fine line and text-like strokes.
        frame(2); // Isolated high-contrast noise impulses; output boost is capped.
        frame(3); // Black/white step tests saturation at both extremes.
        frame(4); // RAW/GRAY switch inside a frame; sharpening is RAW-only.
        frame(5); // COLOR bypass.
        frame(6); // CANNY bypass.
        frame(7); // Explicit RAW bypass path.
        frame(8); // Linear ramps: reject the old directionally displaced predictor.
        repeat(LAT+8) idle();
        rst=0; repeat(5) idle(); rst=1; // Clear/re-warm RAM slots; no stale correction may leak.
        frame(9); // Reflected fine structures; same centered spatial rule.
        repeat(LAT+8) idle();
        if(checked!=10*W*H)$fatal(1,"Output pixel count mismatch: %0d",checked);
        if(flat_changed!=0)$fatal(1,"Flat field changed despite noise gate: %0d",flat_changed);
        if(detailed_changed==0)$fatal(1,"High-frequency line/text test saw no sharpening");
        if(noise_max>8)$fatal(1,"Impulse boost exceeded configured cap: %0d",noise_max);
        if(boundary==0 || raw_checked==0)$fatal(1,"Boundary/bypass coverage missing");
        $display("PASS RAW sharpen: %0d aligned pixels; flat=%0d changed=%0d; detail=%0d; impulse max delta=%0d; boundary=%0d; RAW=%0d; mode/statistics isolation verified",checked,flat_changed,flat_changed,detailed_changed,noise_max,boundary,raw_checked);
        $finish;
    end
    initial begin #300000000; $fatal(1,"Timeout"); end
endmodule
