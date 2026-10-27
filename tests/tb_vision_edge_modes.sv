`timescale 1ns/1ps
module tb_vision_edge_modes;
    localparam W = 64, H = 48;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=0, de=0, vs=0, hs=0, user=0, last=0;
    reg [23:0] rgb=0;
    reg [2:0] mode=0;
    wire [23:0] new_rgb, old_rgb;
    wire [4:0] new_ctrl, old_ctrl;
    wire new_found, old_found, new_toggle, old_toggle;
    wire [23:0] new_pixels, old_pixels;
    wire [7:0] new_luma, old_luma;
    wire [11:0] new_high, old_high, new_low, old_low;
    hx_vision_pipeline #(.ENABLE_RAW_SHARPEN(0),.IMAGE_WIDTH(W), .MIN_TARGET_PIXELS(16), .ENABLE_EDGE_REFINEMENT(1),
                        .ENABLE_STATUS_OSD(0), .ENABLE_ANLOGIC_LOGO(0)) updated (
        .I_clk(clk), .I_rst_n(rst), .I_vsync(vs), .I_hsync(hs), .I_de(de), .I_user(user), .I_last(last),
        .I_rgb(rgb), .I_mode(mode), .I_exposure_level(2'd1), .I_auto_exposure(1'b1),
        .I_raw_sharpen_enable(1'b0), .I_template_command(1'b0), .I_applied_exposure(16'd0), .I_applied_gain_regs(24'd0),
        .I_applied_status(2'd0), .I_applied_has_value(1'b0), .I_applied_update_toggle(1'b0), .I_cal_status(2'd0),
        .O_vsync(new_ctrl[4]), .O_hsync(new_ctrl[3]), .O_de(new_ctrl[2]), .O_user(new_ctrl[1]), .O_last(new_ctrl[0]),
        .O_rgb(new_rgb), .O_target_found(new_found), .O_target_pixels(new_pixels),
        .O_frame_luma(new_luma), .O_frame_highlights(new_high), .O_frame_shadows(new_low), .O_frame_luma_toggle(new_toggle)
    );
    hx_vision_pipeline #(.ENABLE_RAW_SHARPEN(0),.IMAGE_WIDTH(W), .MIN_TARGET_PIXELS(16), .ENABLE_EDGE_REFINEMENT(0),
                        .ENABLE_STATUS_OSD(0), .ENABLE_ANLOGIC_LOGO(0)) bypassed (
        .I_clk(clk), .I_rst_n(rst), .I_vsync(vs), .I_hsync(hs), .I_de(de), .I_user(user), .I_last(last),
        .I_rgb(rgb), .I_mode(mode), .I_exposure_level(2'd1), .I_auto_exposure(1'b1),
        .I_raw_sharpen_enable(1'b0), .I_template_command(1'b0), .I_applied_exposure(16'd0), .I_applied_gain_regs(24'd0),
        .I_applied_status(2'd0), .I_applied_has_value(1'b0), .I_applied_update_toggle(1'b0), .I_cal_status(2'd0),
        .O_vsync(old_ctrl[4]), .O_hsync(old_ctrl[3]), .O_de(old_ctrl[2]), .O_user(old_ctrl[1]), .O_last(old_ctrl[0]),
        .O_rgb(old_rgb), .O_target_found(old_found), .O_target_pixels(old_pixels),
        .O_frame_luma(old_luma), .O_frame_highlights(old_high), .O_frame_shadows(old_low), .O_frame_luma_toggle(old_toggle)
    );
    integer xx, yy, frame_id, checked=0, differences=0, grad_pixels=0, i;
    always @(posedge clk) if (rst) begin
        #1;
        if (new_ctrl !== old_ctrl) $fatal(1, "Video control changed");
        if ({new_found,new_pixels,new_luma,new_high,new_low,new_toggle} !==
            {old_found,old_pixels,old_luma,old_high,old_low,old_toggle}) $fatal(1, "Target/AE statistics changed");
        if (new_ctrl[2]) begin
            if (mode != 3 && new_rgb !== old_rgb) $fatal(1, "Non-edge mode %0d changed", mode);
            if (mode == 3 && new_rgb !== old_rgb) differences = differences+1;
            if (mode == 3 && (new_rgb !== 24'h000000 && new_rgb !== 24'hffffff)) $fatal(1, "Edge output unknown/nonbinary");
            if (mode == 4 && (new_rgb[23:16] !== new_rgb[15:8] || new_rgb[15:8] !== new_rgb[7:0]))
                $fatal(1, "GRAD output is not gray %06h", new_rgb);
            if (mode == 4 && new_rgb !== 24'h000000) grad_pixels = grad_pixels+1;
            checked = checked+1;
        end
    end
    task idle;
        begin @(posedge clk); #2; de=0; user=0; last=0; hs=0; vs=0; rgb=0; end
    endtask
    initial begin
        repeat (5) @(negedge clk);
        #1; rst=1;
        for (frame_id=0; frame_id<8; frame_id=frame_id+1) begin
            repeat (8) idle();
            mode=frame_id%5;
            for (yy=0; yy<H; yy=yy+1) begin
                for (xx=0; xx<W; xx=xx+1) begin
                    @(posedge clk); #2;
                    de=1; user=(xx==0 && yy==0); last=(xx==W-1); hs=(xx<3); vs=(yy==0);
                    if (frame_id<4) begin
                        case ((xx/8)%4)
                            0: rgb=24'hf03020;
                            1: rgb=24'h20f030;
                            2: rgb=24'h3020f0;
                            default: rgb=((xx/4+yy/4)%2) ? 24'hffffff : 24'h101010;
                        endcase
                    end else rgb=((xx*5+yy*3)%19<7) ? 24'hffffff : 24'h000000;
                end
                repeat (12) idle();
            end
        end
        repeat (16) idle();
        if (checked != 8*W*H) $fatal(1, "Pixel count mismatch %0d", checked);
        if (differences==0) $fatal(1, "Refinement did not affect edge mode");
        if (grad_pixels==0) $fatal(1, "GRAD mode produced no gradient pixels");
        $display("PASS vision modes: %0d output pixels; RGB/GRAY/COLOR/GRAD unchanged, controls and target/AE statistics unchanged; %0d edge differences, %0d GRAD pixels", checked, differences, grad_pixels);
        $finish;
    end
    initial begin #10000000; $fatal(1, "Timeout"); end
endmodule
