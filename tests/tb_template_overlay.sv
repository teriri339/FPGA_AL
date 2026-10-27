`timescale 1ns/1ps
module tb_template_overlay #(parameter integer GLOBAL_SCENARIO=0);
    localparam W=160,H=144,LAT=2054;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,de=0,user=0,last=0,hs=0,vs=0,command=0;
    reg [23:0] rgb=0;
    reg [2:0] mode=0;
    wire [23:0] shown,plain;
    wire [4:0] sc,pc;
    wire [57:0] ss,ps;
    defparam dut.g_template.u_tracker.FAST_REACQUIRE=(GLOBAL_SCENARIO==2);
    defparam dut.g_template.u_tracker.GLOBAL_REACQUIRE=(GLOBAL_SCENARIO!=2);
    // 关闭显示框平滑：本用例断言的是框位置与跟踪精度的精确对应关系。
    defparam dut.g_template.u_tracker.DISP_SMOOTH_SHIFT=0;
    defparam dut.g_template.u_tracker.DISP_DEADBAND=0;
    hx_vision_pipeline #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),.ENABLE_TEMPLATE_TRACKING(1)) dut (
        .I_clk(clk),.I_rst_n(rst),.I_vsync(vs),.I_hsync(hs),.I_de(de),.I_user(user),.I_last(last),
        .I_rgb(rgb),.I_mode(mode),.I_template_command(command),.I_raw_sharpen_enable(1'b0),
        .I_exposure_level(2'd1),.I_auto_exposure(1'b0),.I_applied_exposure(16'd1200),
        .I_applied_gain_regs(24'h080080),.I_applied_status(2'd2),.I_applied_has_value(1'b1),
        .I_applied_update_toggle(1'b0),.I_cal_status(2'd0),
        .O_vsync(sc[4]),.O_hsync(sc[3]),.O_de(sc[2]),.O_user(sc[1]),.O_last(sc[0]),.O_rgb(shown),
        .O_target_found(ss[57]),.O_target_pixels(ss[56:33]),.O_frame_luma(ss[32:25]),
        .O_frame_highlights(ss[24:13]),.O_frame_shadows(ss[12:1]),.O_frame_luma_toggle(ss[0])
    );
    hx_vision_pipeline #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),.ENABLE_TEMPLATE_TRACKING(0)) reference (
        .I_clk(clk),.I_rst_n(rst),.I_vsync(vs),.I_hsync(hs),.I_de(de),.I_user(user),.I_last(last),
        .I_rgb(rgb),.I_mode(mode),.I_template_command(1'b0),.I_raw_sharpen_enable(1'b0),
        .I_exposure_level(2'd1),.I_auto_exposure(1'b0),.I_applied_exposure(16'd1200),
        .I_applied_gain_regs(24'h080080),.I_applied_status(2'd2),.I_applied_has_value(1'b1),
        .I_applied_update_toggle(1'b0),.I_cal_status(2'd0),
        .O_vsync(pc[4]),.O_hsync(pc[3]),.O_de(pc[2]),.O_user(pc[1]),.O_last(pc[0]),.O_rgb(plain),
        .O_target_found(ps[57]),.O_target_pixels(ps[56:33]),.O_frame_luma(ps[32:25]),
        .O_frame_highlights(ps[24:13]),.O_frame_shadows(ps[12:1]),.O_frame_luma_toggle(ps[0])
    );
    integer xx,yy,f,k,p=0,q=0,sx=0,sy=0,sf=0;
    integer xq[0:LAT-1],yq[0:LAT-1],fq[0:LAT-1];
    reg [4:0] cq[0:LAT-1];
    integer checked=0,borders=0,texts=0,unchanged=0;
    integer ex,ey;
    reg border,row_tpl;
    reg [23:0] color;
    function integer frame_dx(input integer id);
        begin
            if(GLOBAL_SCENARIO)frame_dx=id>=50 ? -48 : 0;
            else if(id>=2 && id<=5)frame_dx=8;
            else if(id>=7 && id<=12)frame_dx=-(id-6)*8;
            else if(id==13)frame_dx=-48;
            else if(id>=14 && id<=25)frame_dx=(id-19)*8;
            else if(id==26)frame_dx=48;
            else if(id>=86)frame_dx=-48;
            else if(id>=64)frame_dx=24;
            else frame_dx=0;
        end
    endfunction
    always @(posedge clk)begin
        if(!rst)begin
            p=0;q=0;
            for(k=0;k<LAT;k=k+1)begin cq[k]=0;xq[k]=0;yq[k]=0;fq[k]=0;end
        end else begin
            cq[p]={vs,hs,de,user,last};xq[p]=sx;yq[p]=sy;fq[p]=sf;
            q=(p+1)%LAT;p=q;
            #1;
            if(sc!==pc || sc!==cq[q] || ss!==ps)$fatal(1,"Template altered controls/latency or upstream AE/color statistics");
            if(sc[2])begin
                checked=checked+1;
                ex=(fq[q]==3 || fq[q]==4) ? 88 : 80;
                ey=(fq[q]==3 || fq[q]==4) ? 80 : 72;
                if(fq[q]>=7)begin
                    ex=80+frame_dx(fq[q]-1);
                    ey=frame_dx(fq[q]-1);
                    ey=72+(ey < -40 ? -40 : ey>40 ? 40 : ey);
                end
                if(fq[q]>=27 && fq[q]<=44)begin ex=128;ey=112;end
                if(fq[q]>=45)begin ex=80;ey=72;end
                if(fq[q]>=67)begin ex=104;ey=72;end
                if(fq[q]>=90)begin ex=32;ey=32;end
                color=(fq[q]==1 || fq[q]==6) ? 24'hffff00 :
                    (fq[q]==2 || fq[q]==3 || fq[q]==4 || fq[q]>=7) ? 24'h60ff60 : 24'h40e0ff;
                if(fq[q]>=28 && fq[q]<=42)color=24'hffb040;
                if(fq[q]==43 || fq[q]==44)color=24'hff6060;
                if(fq[q]==45 || fq[q]==46)color=24'hffff00;
                if(fq[q]>=49 && fq[q]<=63)color=24'hffb040;
                if(fq[q]>=64 && fq[q]<=66)color=24'hff6060;
                if(fq[q]==67 || fq[q]==68)color=24'hffff00;
                if(fq[q]>=71 && fq[q]<=85)color=24'hffb040;
                if(fq[q]>=86 && fq[q]<=89)color=24'hff6060;
                if(fq[q]==90 || fq[q]==91)color=24'hffff00;
                if(GLOBAL_SCENARIO)begin
                    ex=fq[q]>=(GLOBAL_SCENARIO==2 ?56:52) ? 32 : 80;
                    ey=fq[q]>=(GLOBAL_SCENARIO==2 ?56:52) ? 32 : 72;
                    color=fq[q]==0 ? 24'h40e0ff : fq[q]==1 ? 24'hffff00 : 24'h60ff60;
                    if(fq[q]>=3 && fq[q]<=17)color=24'hffb040;
                    if(fq[q]>=18 && fq[q]<=(GLOBAL_SCENARIO==2 ?55:51))color=24'hff6060;
                    if(fq[q]==(GLOBAL_SCENARIO==2 ?56:52) || fq[q]==(GLOBAL_SCENARIO==2 ?57:53))color=24'hffff00;
                end
                row_tpl=yq[q]>=32 && yq[q]<48 && xq[q]<224;
                border=(fq[q]!=4 || GLOBAL_SCENARIO) &&
                    (((xq[q]==ex-32 || xq[q]==ex+31) && yq[q]>=ey-32 && yq[q]<ey+32) ||
                     ((yq[q]==ey-32 || yq[q]==ey+31) && xq[q]>=ex-32 && xq[q]<ex+32));
                if(row_tpl)begin
                    texts=texts+1;
                    if(shown!==color && shown!==24'h101018)$fatal(1,"TPL status glyph/background mismatch frame %0d at %0d,%0d: %h expected %h",fq[q],xq[q],yq[q],shown,color);
                end else if(border && yq[q]>=32)begin
                    borders=borders+1;
                    if(shown!==color)$fatal(1,"Tracking box mismatch frame %0d at %0d,%0d got %h",fq[q],xq[q],yq[q],shown);
                end else begin
                    unchanged=unchanged+1;
                    if(shown!==plain)$fatal(1,"Pixel outside TPL overlay changed frame %0d at %0d,%0d",fq[q],xq[q],yq[q]);
                end
            end else if(shown!==0)$fatal(1,"Template overlay leaked into blanking");
        end
    end
    task idle(input integer count);
        begin repeat(count)begin @(negedge clk);de=0;user=0;last=0;hs=0;vs=0;command=0;end end
    endtask
    task toggle;
        begin @(negedge clk);command=1;@(negedge clk);command=0;end
    endtask
    task frame(input integer frameid);
        integer a,b,v,dx,dy;
        begin
            f=frameid;mode=f==4 ? 3 : f==5 ? 1 : 0;
            if(GLOBAL_SCENARIO)mode=0;
            dx=frame_dx(f);dy=dx < -40 ? -40 : dx>40 ? 40 : dx;
            if(f>=64 && f<86)dy=0;
            for(yy=0;yy<H;yy=yy+1)begin
                for(xx=0;xx<W;xx=xx+1)begin
                    @(negedge clk);de=1;user=(xx==0 && yy==0);last=(xx==W-1);hs=xx<2;vs=yy==0;
                    sx=xx;sy=yy;sf=f;
                    a=xx/8-(6+dx/8);b=yy/8-(5+dy/8);v=32;
                    if(a>=0 && a<8 && b>=0 && b<8)v=64+(a*73+b*151+a*b*37+19)%128;
                    if(f>=27 && f<=42)v=32;
                    if(f>=48 && f<=63)v=32;
                    if(f>=70 && f<=85)v=32;
                    if(GLOBAL_SCENARIO)begin
                        v=32;
                        if(!(f>=2 && f<=49) && a>=0 && a<8 && b>=0 && b<8)
                            v=64+(a*73+b*151+a*b*37+19)%128;
                    end
                    rgb=v*24'h010101;
                end
                idle(20);
            end
            idle(40000);
            $display("INTEGRATED frame=%0d status=%0d center=%0d,%0d reason=%0d error=%0d margin=%0d",f,dut.template_status,dut.template_cx,dut.template_cy,dut.template_reason,dut.template_best,dut.template_margin);
        end
    endtask
    initial begin
        idle(5);rst=1;idle(5);
        if(GLOBAL_SCENARIO)begin
            frame(0);toggle();frame(1);
            if(dut.template_status!=2)$fatal(1,"Global integrated acquisition failed");
            for(integer fi=2;fi<=49;fi=fi+1)frame(fi);
            if(dut.template_status!=4 || (GLOBAL_SCENARIO==1 && dut.g_template.u_tracker.global_warmup!=32))
                $fatal(1,"Global integrated warmup failed");
            if(GLOBAL_SCENARIO==2)begin
                frame(50);frame(51);frame(52);frame(53);frame(54);
                if(dut.template_status!=4)$fatal(1,"Fast overlay fallback unexpectedly accepted target");
                frame(55);
                if(dut.template_status!=6 || !dut.g_template.u_tracker.recovery_slot_fast)
                    $fatal(1,"Fast video did not use coarse-to-fine proposal");
                frame(56);if(dut.template_status!=6)$fatal(1,"Fast video skipped confirmation");
                frame(57);
                if(dut.template_status!=2 || dut.template_reason!=10 || dut.template_cx!=32 || dut.template_cy!=32)
                    $fatal(1,"Fast video recovery failed");
                frame(58);idle(LAT+10);
                if(checked!=59*W*H || borders==0 || texts==0 || unchanged==0)$fatal(1,"Fast video coverage missing");
                $display("PASS fast template overlay: %0d pixels, %0d box pixels, %0d TPL slots; real Gaussian/box-pyramid/fast candidate/fine VERIFY, controls/base image/AE/color preserved",checked,borders,texts);
                $finish;
            end
            frame(50);if(dut.template_status!=4)$fatal(1,"Local window accepted global test target");
            frame(51);
            if(dut.template_status!=6 || !dut.g_template.u_tracker.recovery_slot_global)
                $fatal(1,"Global integration did not use global window");
            frame(52);if(dut.template_status!=6)$fatal(1,"Global integration skipped verification");
            frame(53);
            if(dut.template_status!=2 || dut.template_reason!=10 || dut.template_cx!=32 || dut.template_cy!=32)
                $fatal(1,"Global integrated recovery failed");
            frame(54);idle(LAT+10);
            if(checked!=55*W*H || borders==0 || texts==0 || unchanged==0)$fatal(1,"Global integration coverage missing");
            $display("PASS global template overlay: %0d pixels, %0d box pixels, %0d TPL slots; real Gaussian/global proposal/3-frame confirmation, controls/base image/AE/color statistics preserved",checked,borders,texts);
            $finish;
        end else begin
        frame(0);toggle();frame(1);
        if(dut.template_status!=2)$fatal(1,"Integrated template acquisition failed");
        frame(2);
        if(dut.template_cx!=88 || dut.template_cy!=80 || dut.template_status!=2)$fatal(1,"Integrated translation failed");
        frame(3);frame(4);toggle();frame(5);
        toggle();frame(6);frame(7);frame(8);frame(9);frame(10);frame(11);frame(12);frame(13);
        if(dut.template_cx!=32 || dut.template_cy!=32 || dut.template_status!=2)$fatal(1,"Integrated Gaussian top-left border failed");
        for(integer fi=14;fi<=26;fi=fi+1)frame(fi);
        if(dut.template_cx!=128 || dut.template_cy!=112 || dut.template_status!=2)$fatal(1,"Integrated Gaussian bottom-right border failed");
        for(integer lost_f=27;lost_f<=42;lost_f=lost_f+1)frame(lost_f);
        if(dut.template_status!=4)$fatal(1,"Integrated missing target should reach LOST");
        frame(43);if(dut.template_status!=4)$fatal(1,"Last-location scan should not relock centre target");
        frame(44);if(dut.template_status!=6)$fatal(1,"Central search should begin VERIFY");
        frame(45);if(dut.template_status!=6)$fatal(1,"Recovery must require three frames");
        frame(46);if(dut.template_status!=2 || dut.template_reason!=10)$fatal(1,"Integrated recovery failed");
        frame(47);
        for(integer lost_f=48;lost_f<=63;lost_f=lost_f+1)frame(lost_f);
        if(dut.template_status!=4)$fatal(1,"Expanded scenario did not enter LOST");
        frame(64);if(dut.template_status!=4)$fatal(1,"Fast last window unexpectedly accepted 24-pixel return");
        frame(65);if(dut.template_status!=4)$fatal(1,"Fast central window unexpectedly accepted 24-pixel return");
        frame(66);if(dut.template_status!=6)$fatal(1,"Expanded window did not propose candidate");
        frame(67);if(dut.template_status!=6)$fatal(1,"Expanded recovery skipped confirmation");
        frame(68);if(dut.template_status!=2 || dut.template_reason!=10 || dut.template_cx!=104 || dut.template_cy!=72)$fatal(1,"Integrated expanded recovery failed");
        frame(69);
        for(integer lost_f=70;lost_f<=85;lost_f=lost_f+1)frame(lost_f);
        if(dut.template_status!=4)$fatal(1,"Far integration scenario did not enter LOST");
        frame(86);frame(87);frame(88);
        if(dut.template_status!=4)$fatal(1,"Near windows falsely accepted far return");
        frame(89);if(dut.template_status!=6)$fatal(1,"Far window did not propose Gaussian candidate");
        frame(90);if(dut.template_status!=6)$fatal(1,"Far integration skipped confirmation");
        frame(91);
        if(dut.template_status!=2 || dut.template_reason!=10 || dut.template_cx!=32 || dut.template_cy!=32)
            $fatal(1,"Integrated far recovery failed");
        frame(92);frame(93);
        idle(LAT+10);
        if(checked!=94*W*H || borders==0 || texts==0 || unchanged==0)$fatal(1,"Missing integration coverage");
        $display("PASS template overlay: %0d pixels, %0d box pixels, %0d TPL status slots; RAW/GRAY/Canny controls, original overlays and upstream statistics preserved",checked,borders,texts);
        $finish;
        end
    end
    initial begin #200000000; $fatal(1,"Timeout");end
endmodule

// Check the entire diagnostic string, including fields beyond the small video fixture.
module tb_template_debug_osd;
    reg clk=0;always #5 clk=~clk;
    reg [10:0] probe_x=0,probe_y=32;
    integer col;
    reg [303:0] expected;
    hx_vision_pipeline #(.ENABLE_TEMPLATE_TRACKING(1),.ENABLE_RAW_SHARPEN(0)) dut (
        .I_clk(clk),.I_rst_n(1'b0),.I_vsync(1'b0),.I_hsync(1'b0),.I_de(1'b0),
        .I_user(1'b0),.I_last(1'b0),.I_rgb(24'd0),.I_mode(3'd0),
        .I_exposure_level(2'd0),.I_auto_exposure(1'b0),.I_raw_sharpen_enable(1'b0),
        .I_template_command(1'b0),.I_applied_exposure(16'd0),.I_applied_gain_regs(24'd0),
        .I_applied_status(2'd0),.I_applied_has_value(1'b0),.I_applied_update_toggle(1'b0),
        .I_cal_status(2'd0),.O_vsync(),.O_hsync(),.O_de(),.O_user(),.O_last(),.O_rgb(),
        .O_target_found(),.O_target_pixels(),.O_frame_luma(),.O_frame_highlights(),
        .O_frame_shadows(),.O_frame_luma_toggle()
    );
    initial begin
        force dut.draw_x=probe_x;force dut.draw_y=probe_y;
        force dut.template_status=3'd4;
        force dut.template_reason=4'd2;force dut.template_best=15'h0301;
        force dut.template_margin=15'h0008;force dut.template_misses=5'd15;
        expected="TPL: LOST     E:0301 U:0008 R:2 M:0F  ";
        if(dut.font5x7("U",0)!==5'b10001 || dut.font5x7("U",6)!==5'b01110)
            $fatal(1,"Uniqueness label font is missing");
        // Literal is 38 characters; verify all slots and exact row boundaries.
        for(col=0;col<38;col=col+1)begin
            probe_x=col*16;#2;
            if(!dut.template_osd_region || dut.template_char!==((expected >> ((37-col)*8)) & 8'hff))
                $fatal(1,"Debug OSD column %0d got %c",col,dut.template_char);
        end
        probe_x=608;#2;if(dut.template_osd_region)$fatal(1,"Debug OSD overflow");
        probe_x=0;probe_y=48;#2;if(dut.template_osd_region)$fatal(1,"Debug OSD row overflow");
        force dut.template_status=3'd6;probe_y=32;probe_x=80;#2;
        if(dut.template_text!=="VERIFY  " || dut.template_char!=="V" || dut.template_fg!==24'hffff00)
            $fatal(1,"Recovery confirmation OSD must be yellow VERIFY");
        if(dut.font5x7("V",6)!==5'b00100)$fatal(1,"VERIFY label font missing");
        force dut.template_status=3'd2;force dut.template_reason=4'd10;probe_x=480;#2;
        if(dut.template_char!=="A" || dut.template_fg!==24'h60ff60)$fatal(1,"Recovery success diagnostic must render R:A");
        $display("PASS template debug OSD: full status/error/uniqueness/reason/misses string and bounds");
        $finish;
    end
endmodule
