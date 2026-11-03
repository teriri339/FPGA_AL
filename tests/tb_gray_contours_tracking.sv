`timescale 1ns/1ps
module tb_gray_contours_tracking #(parameter SHARP=0, DENOISE=0);
 localparam W=96,H=80;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,de=0,user=0,last=0;reg [23:0] rgb=0;reg [1:0] mode=0;
 wire [23:0] shown,plain;wire [4:0] sc,pc;
 hx_vision_pipeline #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),.ENABLE_ANLOGIC_LOGO(0),.ENABLE_STATUS_OSD(0),.ENABLE_RAW_SHARPEN(SHARP),.ENABLE_DISPLAY_DENOISE(DENOISE),.ENABLE_TEMPLATE_TRACKING(1)) dut (
 .I_clk(clk),.I_rst_n(rst),.I_vsync(1'b0),.I_hsync(1'b0),.I_de(de),.I_user(user),.I_last(last),.I_rgb(rgb),.I_mode(mode),.I_template_command(1'b0),.I_raw_sharpen_enable(1'b0),.I_applied_update_toggle(1'b0),.I_exposure_level(2'd1),.I_auto_exposure(1'b0),.I_applied_exposure(16'd1200),.I_applied_gain_regs(24'd0),.I_applied_status(2'd2),.I_applied_has_value(1'b1),.I_cal_status(2'd0),.O_target_found(),.O_target_pixels(),.O_frame_luma(),.O_frame_highlights(),.O_frame_shadows(),.O_frame_luma_toggle(),
 .O_rgb(shown),.O_vsync(sc[4]),.O_hsync(sc[3]),.O_de(sc[2]),.O_user(sc[1]),.O_last(sc[0]));
 hx_vision_pipeline #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),.ENABLE_ANLOGIC_LOGO(0),.ENABLE_STATUS_OSD(0),.ENABLE_RAW_SHARPEN(SHARP),.ENABLE_DISPLAY_DENOISE(DENOISE),.ENABLE_GRAY_CONTOURS(0)) refp (
 .I_clk(clk),.I_rst_n(rst),.I_vsync(1'b0),.I_hsync(1'b0),.I_de(de),.I_user(user),.I_last(last),.I_rgb(rgb),.I_mode(mode),.I_template_command(1'b0),.I_raw_sharpen_enable(1'b0),.I_applied_update_toggle(1'b0),.I_exposure_level(2'd1),.I_auto_exposure(1'b0),.I_applied_exposure(16'd1200),.I_applied_gain_regs(24'd0),.I_applied_status(2'd2),.I_applied_has_value(1'b1),.I_cal_status(2'd0),.O_target_found(),.O_target_pixels(),.O_frame_luma(),.O_frame_highlights(),.O_frame_shadows(),.O_frame_luma_toggle(),
 .O_rgb(plain),.O_vsync(pc[4]),.O_hsync(pc[3]),.O_de(pc[2]),.O_user(pc[1]),.O_last(pc[0]));
 integer xx,yy,f,v,dx,dy,dm;integer borders[0:3];integer red=0,noise_red=0,checked=0;
 reg valid,border;
 always @(posedge clk) if(rst)begin
  dx=dut.draw_x;dy=dut.draw_y;dm=dut.final_mode;valid=dut.final_ctrl[2];
  border=((dx==8 || dx==87) && dy>=0 && dy<80) || ((dy==0 || dy==79) && dx>=8 && dx<88);
  if(f>=5)border=((dx==0 || dx==71) && dy>=0 && dy<=71) || ((dy==0 || dy==71) && dx>=0 && dx<=71);
  if(f>=6 && f!=8)border=0;
  #1;
  if(sc!==pc)$fatal(1,"Controls changed");
  if(valid)begin
   checked=checked+1;
   if(border)begin
    borders[dm]=borders[dm]+1;
    if(shown!==24'h60ff60)$fatal(1,"Missing tracking border mode=%0d x=%0d y=%0d rgb=%h",dm,dx,dy,shown);
   end else if(dm==1 && shown==24'hff0000)begin
    red=red+1;
    // Frames are drained before changing input scenes.
    if(f==2)noise_red=noise_red+1;
    if(f==1 && !((dx==48 && dy>=40) || (dy==40 && dx>=48)))$fatal(1,"Misaligned contour at %0d,%0d",dx,dy);
   end else if(shown!==plain)$fatal(1,"Unexpected image change mode=%0d x=%0d y=%0d",dm,dx,dy);
  end else if(shown!==0)$fatal(1,"Blanking changed");
 end
 task idle(input integer n);begin repeat(n)begin @(negedge clk);de=0;user=0;last=0;end end endtask
 initial begin
  for(f=0;f<4;f=f+1)borders[f]=0;
  idle(4);rst=1;
  force dut.template_status=3'd2;force dut.template_cx=11'd48;force dut.template_cy=11'd40;
  for(f=0;f<13;f=f+1)begin
   mode=f==2 ? 1 : f>=5 ? 0 : f>2 ? f-1 : f;
   if(f==5)begin force dut.template_cx=11'd32;force dut.template_cy=11'd32;end
   if(f>=6)force dut.template_status=f-6;
   for(yy=0;yy<H;yy=yy+1)begin
    for(xx=0;xx<W;xx=xx+1)begin
     @(negedge clk);de=1;user=(xx==0 && yy==0);last=(xx==W-1);
     v=f==2 ? 90+(xx*13+yy*7)%5 : ((xx>=48 && yy>=40)?210:40);
     rgb=v*24'h010101;
    end idle(12);
   end idle(2200);
  end
  if(red==0 || noise_red!=0)$fatal(1,"Contour missing or low contrast noise highlighted red=%0d noise=%0d",red,noise_red);
  for(f=0;f<4;f=f+1)if(borders[f]==0)$fatal(1,"Mode %0d not checked",f);
  $display("PASS gray red contour alignment/noise, all-mode tracking border, controls and unaffected pixels: %0d pixels SHARP=%0d DENOISE=%0d",checked,SHARP,DENOISE);$finish;
 end
 initial begin #10000000;$fatal(1,"timeout");end
endmodule
