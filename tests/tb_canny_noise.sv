`timescale 1ns/1ps
module tb_canny_noise;
    localparam W=256,H=192;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,de=0,user=0,last=0,vs=0,hs=0;
    reg [23:0] rgb=0;
    reg [2:0] mode=0;
    wire [23:0] tuned,prior;
    wire [4:0] tc,pc;
    wire [57:0] ts,ps;
    hx_vision_pipeline #(.ENABLE_RAW_SHARPEN(0),.IMAGE_WIDTH(W),.ENABLE_STATUS_OSD(0),.ENABLE_ANLOGIC_LOGO(0)) dut (
        .I_clk(clk),.I_rst_n(rst),.I_de(de),.I_user(user),.I_last(last),.I_vsync(vs),.I_hsync(hs),
        .I_rgb(rgb),.I_mode(mode),.I_exposure_level(2'd2),.I_auto_exposure(1'b1),
        .I_raw_sharpen_enable(1'b0), .I_template_command(1'b0),.I_applied_exposure(16'd0),.I_applied_gain_regs(24'd0),
        .I_applied_status(2'd0),.I_applied_has_value(1'b0),.I_applied_update_toggle(1'b0),.I_cal_status(2'd0),
        .O_rgb(tuned),.O_vsync(tc[4]),.O_hsync(tc[3]),.O_de(tc[2]),.O_user(tc[1]),.O_last(tc[0]),
        .O_target_found(ts[57]),.O_target_pixels(ts[56:33]),.O_frame_luma(ts[32:25]),
        .O_frame_highlights(ts[24:13]),.O_frame_shadows(ts[12:1]),.O_frame_luma_toggle(ts[0])
    );
    hx_vision_pipeline #(.ENABLE_RAW_SHARPEN(0),.IMAGE_WIDTH(W),.ENABLE_STATUS_OSD(0),.ENABLE_ANLOGIC_LOGO(0),
        .SOBEL_THRESHOLD_DARK(40),.SOBEL_THRESHOLD_NORMAL(60),.SOBEL_THRESHOLD_BRIGHT(64),
        .SOBEL_STRONG_THRESHOLD_DARK(72),.SOBEL_STRONG_THRESHOLD_NORMAL(96),.SOBEL_STRONG_THRESHOLD_BRIGHT(112)) baseline (
        .I_clk(clk),.I_rst_n(rst),.I_de(de),.I_user(user),.I_last(last),.I_vsync(vs),.I_hsync(hs),
        .I_rgb(rgb),.I_mode(mode),.I_exposure_level(2'd2),.I_auto_exposure(1'b1),
        .I_raw_sharpen_enable(1'b0), .I_template_command(1'b0),.I_applied_exposure(16'd0),.I_applied_gain_regs(24'd0),
        .I_applied_status(2'd0),.I_applied_has_value(1'b0),.I_applied_update_toggle(1'b0),.I_cal_status(2'd0),
        .O_rgb(prior),.O_vsync(pc[4]),.O_hsync(pc[3]),.O_de(pc[2]),.O_user(pc[1]),.O_last(pc[0]),
        .O_target_found(ps[57]),.O_target_pixels(ps[56:33]),.O_frame_luma(ps[32:25]),
        .O_frame_highlights(ps[24:13]),.O_frame_shadows(ps[12:1]),.O_frame_luma_toggle(ps[0])
    );
    integer xx,yy,f,k,n,v,sx=0,sy=0;
    integer xq[0:2],yq[0:2],mq[0:2];
    reg dq[0:2];
    reg [31:0] rng=32'hbd134125;
    integer old_noise=0,new_noise=0,old_line=0,new_line=0,line_changes=0,checked=0;
    always @(posedge clk)begin
        if(!rst)begin
            for(k=0;k<3;k=k+1)begin dq[k]=0;xq[k]=0;yq[k]=0;mq[k]=0;end
        end else begin
            for(k=2;k>0;k=k-1)begin dq[k]=dq[k-1];xq[k]=xq[k-1];yq[k]=yq[k-1];mq[k]=mq[k-1];end
            dq[0]=de;xq[0]=sx;yq[0]=sy;mq[0]=mode;
            #1;
            if(tc!==pc || ts!==ps)$fatal(1,"Changed controls, target or AE statistics");
            if(tc[2]!==dq[2])$fatal(1,"Display latency changed");
            if(tc[2])begin
                checked=checked+1;
                if(mq[2]!=3 && tuned!==prior)$fatal(1,"RAW/GRAY/COLOR changed");
                if(mq[2]==3)begin
                    if((tuned!==0 && tuned!==24'hffffff)||(prior!==0 && prior!==24'hffffff))$fatal(1,"Nonbinary Canny");
                    if(xq[2]>24 && xq[2]<112 && yq[2]>24 && yq[2]<168)begin
                        if(prior!=0)old_noise=old_noise+1;
                        if(tuned!=0)new_noise=new_noise+1;
                    end
                    if(xq[2]>152 && xq[2]<240 && yq[2]>40 && yq[2]<160)begin
                        if(prior!=0)old_line=old_line+1;
                        if(tuned!=0)new_line=new_line+1;
                        if(tuned!==prior)line_changes=line_changes+1;
                    end
                end
            end else if(tuned!==0)$fatal(1,"Blanking changed");
        end
    end
    task idle;begin @(posedge clk);#2;de=0;user=0;last=0;end endtask
    initial begin
        repeat(5)idle();rst=1;
        for(f=0;f<7;f=f+1)begin
            mode=(f<3)?f:3;
            repeat(8)idle();
            for(yy=0;yy<H;yy=yy+1)begin
                for(xx=0;xx<W;xx=xx+1)begin
                    @(posedge clk);#2;sx=xx;sy=yy;de=1;user=(xx==0 && yy==0);last=(xx==W-1);
                    rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
                    n=(rng&127)-64;
                    if(xx<128)begin
                        // Three brightness bands exercise all threshold pairs.
                        v=((yy<64)?64:(yy<128)?128:192)+n/2;
                        rgb=v*24'h010101;
                    end else begin
                        // Large and moderate contrast contours in all bands.
                        case(f)
                            4:v=((xx/12)%2)?72:24;
                            5:v=((xx/12)%2)?152:104;
                            6:v=((xx/12)%2)?224:176;
                            default:v=((xx/12)%2)?224:24;
                        endcase
                        rgb=v*24'h010101;
                    end
                end
                repeat(5)idle();
            end
        end
        repeat(8)idle();
        $display("Noise baseline=%d tuned=%d; strong edges baseline=%d tuned=%d changed=%d",old_noise,new_noise,old_line,new_line,line_changes);
        if(checked!=7*W*H)$fatal(1,"Pixel count mismatch");
        if(old_noise<30 || new_noise>=old_noise)$fatal(1,"No demonstrated noise reduction");
        if(old_line<100 || line_changes!=0)$fatal(1,"Strong contours changed");
        $display("PASS mild Canny noise tuning: %d pixels; non-Canny/AE/target unchanged",checked);$finish;
    end
endmodule
