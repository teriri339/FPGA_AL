`timescale 1ns/1ps
module tb_picture_quality;
    localparam W=1280,H=720;
    reg clk=0; always #5 clk=~clk;
    reg rst=0,de=0,user=0,last=0,vs=0,hs=0;
    reg [23:0] rgb=0;
    reg [1:0] mode=0;
    // DUT uses production defaults (bypass); baseline explicitly tests the
    // retained optional enhancement against the independent integer model.
    wire [23:0] enhanced, original;
    wire [4:0] ec,oc;
    wire [57:0] es,os;
    hx_vision_pipeline #(.ENABLE_RAW_SHARPEN(0),.ENABLE_STATUS_OSD(0),.ENABLE_ANLOGIC_LOGO(0)) dut (
        .I_clk(clk),.I_rst_n(rst),.I_de(de),.I_user(user),.I_last(last),.I_vsync(vs),.I_hsync(hs),
        .I_rgb(rgb),.I_mode(mode),.I_exposure_level(2'd2),.I_auto_exposure(1'b1),
        .I_raw_sharpen_enable(1'b0), .I_template_command(1'b0),.I_applied_exposure(16'd0),.I_applied_gain_regs(24'd0),
        .I_applied_status(2'd0),.I_applied_has_value(1'b0),.I_applied_update_toggle(1'b0),.I_cal_status(2'd0),
        .O_rgb(enhanced),.O_vsync(ec[4]),.O_hsync(ec[3]),.O_de(ec[2]),.O_user(ec[1]),.O_last(ec[0]),
        .O_target_found(es[57]),.O_target_pixels(es[56:33]),.O_frame_luma(es[32:25]),
        .O_frame_highlights(es[24:13]),.O_frame_shadows(es[12:1]),.O_frame_luma_toggle(es[0])
    );
    hx_vision_pipeline #(.ENABLE_RAW_SHARPEN(0),.ENABLE_STATUS_OSD(0),.ENABLE_ANLOGIC_LOGO(0),
        .ENABLE_DISPLAY_DENOISE(1),.ENABLE_SHADOW_LIFT(1)) baseline (
        .I_clk(clk),.I_rst_n(rst),.I_de(de),.I_user(user),.I_last(last),.I_vsync(vs),.I_hsync(hs),
        .I_rgb(rgb),.I_mode(mode),.I_exposure_level(2'd2),.I_auto_exposure(1'b1),
        .I_raw_sharpen_enable(1'b0), .I_template_command(1'b0),.I_applied_exposure(16'd0),.I_applied_gain_regs(24'd0),
        .I_applied_status(2'd0),.I_applied_has_value(1'b0),.I_applied_update_toggle(1'b0),.I_cal_status(2'd0),
        .O_rgb(original),.O_vsync(oc[4]),.O_hsync(oc[3]),.O_de(oc[2]),.O_user(oc[1]),.O_last(oc[0]),
        .O_target_found(os[57]),.O_target_pixels(os[56:33]),.O_frame_luma(os[32:25]),
        .O_frame_highlights(os[24:13]),.O_frame_shadows(os[12:1]),.O_frame_luma_toggle(os[0])
    );
    reg [23:0] rows[0:W-1],left,above_left,b,avg,expect_rgb[0:2];
    reg [23:0] expect_plain[0:2];
    reg [1:0] row_mode[0:W-1],lm,alm,delay_mode[0:2];
    reg [4:0] expect_ctrl[0:2];
    integer px=0,py=0,k,c,v,a,delta,gray,xx,yy,f,n,checked=0,filtered=0,bypassed=0;
    integer raw_sse=0,out_sse=0,noise_samples=0;
    reg flat;
    // Independent integer model, including first row/column and mode tags.
    always @(posedge clk) begin
        if(!rst) begin
            px=0;py=0;left=0;above_left=0;lm=0;alm=0;
            for(k=0;k<3;k=k+1) begin expect_ctrl[k]=0;expect_rgb[k]=0;expect_plain[k]=0;delay_mode[k]=0;end
        end else begin
            for(k=2;k>0;k=k-1) begin
                expect_ctrl[k]=expect_ctrl[k-1];expect_rgb[k]=expect_rgb[k-1];delay_mode[k]=delay_mode[k-1];
                expect_plain[k]=expect_plain[k-1];
            end
            expect_ctrl[0]={vs,hs,de,user,last};delay_mode[0]=mode;
            expect_rgb[0]=0;
            expect_plain[0]=0;
            if(de) begin
                if(user) begin px=0;py=0;end
                gray=(77*rgb[23:16]+150*rgb[15:8]+29*rgb[7:0])/256;
                b=mode==1 ? gray*24'h010101 : rgb;
                expect_plain[0]=b;
                flat=(px>0 && py>0 && mode<2 && lm==mode && row_mode[px]==mode && alm==mode);
                for(c=0;c<3;c=c+1) begin
                    v=(b>>(8*c))&255;
                    a=(left>>(8*c))&255;delta=v-a;if(delta<0)delta=-delta;if(delta>24)flat=0;
                    a=(rows[px]>>(8*c))&255;delta=v-a;if(delta<0)delta=-delta;if(delta>24)flat=0;
                    a=(above_left>>(8*c))&255;delta=v-a;if(delta<0)delta=-delta;if(delta>24)flat=0;
                end
                avg=0;
                for(c=0;c<3;c=c+1) begin
                    v=(b>>(8*c))&255;
                    if(flat) v=(v+((left>>(8*c))&255)+((rows[px]>>(8*c))&255)+((above_left>>(8*c))&255)+2)/4;
                    if(mode<2) begin
                        if(v<64)v=v+v/4;
                        else if(v<128)v=v+(128-v)/4;
                    end
                    avg=avg|(v<<(8*c));
                end
                expect_rgb[0]=avg;
                if(flat)filtered=filtered+1;else bypassed=bypassed+1;
                if(mode==0 && py>10 && px>10 && px<300) begin
                    v=rgb[7:0];if(v<64)v=v+v/4;else if(v<128)v=v+(128-v)/4;
                    raw_sse=raw_sse+(v-107)*(v-107);
                    out_sse=out_sse+($signed({1'b0,avg[7:0]})-107)*($signed({1'b0,avg[7:0]})-107);
                    noise_samples=noise_samples+1;
                end
                above_left=rows[px];alm=row_mode[px];rows[px]=b;row_mode[px]=mode;left=b;lm=mode;
                if(last)begin px=0;py=py+1;end else px=px+1;
            end
            #1;
            if(ec!==oc || es!==os) $fatal(1,"Enhancement changed controls or target/AE statistics");
            if(ec!==expect_ctrl[2]) $fatal(1,"Video latency/control alignment changed");
            if(ec[2]) begin
                checked=checked+1;
                if(delay_mode[2]<2 && enhanced!==expect_plain[2])
                    $fatal(1,"Default RAW/GRAY is not direct passthrough: got %h expected %h at sample %d",enhanced,expect_plain[2],checked);
                if(delay_mode[2]<2 && original!==expect_rgb[2])
                    $fatal(1,"Optional enhancement mismatch got %h expected %h at sample %d",original,expect_rgb[2],checked);
                if(delay_mode[2]>=2 && enhanced!==original) $fatal(1,"COLOR/CANNY changed");
            end else if(enhanced!==0) $fatal(1,"Nonzero blanking");
        end
    end
    task idle;
        begin @(posedge clk);#2;de=0;user=0;last=0;vs=0;hs=0;end
    endtask
    initial begin
        if(dut.ENABLE_DISPLAY_DENOISE!=0 || dut.ENABLE_SHADOW_LIFT!=0)
            $fatal(1,"Production defaults must disable both display enhancements");
        repeat(5)idle();rst=1;
        for(f=0;f<4;f=f+1) begin
            repeat(8)idle();
            for(yy=0;yy<H;yy=yy+1)begin
                for(xx=0;xx<W;xx=xx+1)begin
                    @(posedge clk);#2;
                    mode=f;
                    // Exercise same-row mode changes, including history tags.
                    if(f==0 && yy==100 && xx>=400 && xx<600)mode=1;
                    de=1;user=(xx==0 && yy==0);last=(xx==W-1);vs=(yy==0);hs=(xx<3);
                    n=((xx*17+yy*29+(xx*yy)%23)%17)-8;
                    if(xx<320)rgb=(100+n)*24'h010101;
                    else if(xx<480)rgb=24'hffffff;
                    else if(xx<640)rgb=0;
                    else if(xx<800)rgb=24'hb42850;
                    else if(xx<960)rgb=24'h287050;
                    else rgb={8'(xx+yy),8'(xx*3+yy),8'(xx+yy*7)};
                    if(xx==200 && yy==90)idle(); // DE gap within a line.
                end
                repeat(5)idle();
            end
        end
        repeat(10)idle();
        if(checked!=4*W*H)$fatal(1,"Pixel count mismatch %d",checked);
        if(out_sse*2>=raw_sse)$fatal(1,"Flat-field noise reduction too small");
        $display("PASS picture quality: default RAW/GRAY passthrough and optional enhancement; pixels=%d flat=%d bypass=%d noise_samples=%d input_SSE=%d output_SSE=%d",checked,filtered,bypassed,noise_samples,raw_sse,out_sse);
        $finish;
    end
endmodule
