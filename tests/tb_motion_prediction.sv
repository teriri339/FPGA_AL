`timescale 1ns/1ps
module tb_motion_prediction;
 localparam W=320,H=160;
 reg clk=0; always #5 clk=~clk;
 reg rst=0, command=0, de=0;
 reg [10:0] x=0,y=0; reg [7:0] luma=0;
 wire [2:0] s0,s1; wire [10:0] x0,y0,x1,y1; wire [3:0] r0,r1;
 integer xx,yy,f,dx,good0=0,good1=0;
 hx_template_tracker #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),.AUTO_REACQUIRE(0),.FAST_REACQUIRE(0),.ENABLE_MOTION_PREDICTION(0)) base (
  .clk(clk),.rst_n(rst),.command(command),.de(de),.x(x),.y(y),.luma(luma),.status(s0),.center_x(x0),.center_y(y0),.busy(),.debug_reason(r0),.debug_best(),.debug_margin(),.debug_misses());
 hx_template_tracker #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),.AUTO_REACQUIRE(0),.FAST_REACQUIRE(0),.ENABLE_MOTION_PREDICTION(1)) dut (
  .clk(clk),.rst_n(rst),.command(command),.de(de),.x(x),.y(y),.luma(luma),.status(s1),.center_x(x1),.center_y(y1),.busy(),.debug_reason(r1),.debug_best(),.debug_margin(),.debug_misses());
 function integer pattern(input integer a,b); integer p,q; begin
  p=(a*3+b+4096)%47; q=(b*2-a+4096)%37; if(p>23)p=46-p; if(q>18)q=36-q; pattern=40+4*p+3*q;
 end endfunction
 task idle(input integer cycles); begin repeat(cycles) begin @(negedge clk);de=0;command=0;end end endtask
 task frame(input integer dx,input integer blanked); begin
  for(yy=0;yy<H;yy=yy+1) begin
   for(xx=0;xx<W;xx=xx+1) begin @(negedge clk);de=1;x=xx;y=yy;luma=blanked ? 8'd96 : pattern(xx-dx,yy);end
   idle(4);
  end
  idle(49500);
 end endtask
 task start; begin rst=0;idle(4);rst=1;idle(4);@(negedge clk);command=1;idle(1);frame(0,0);if(s0!=2 || s1!=2)$fatal(1,"Learning failed");end endtask
 initial begin
  start();frame(0,0); frame(6,0);
  if(s1!=2 || x1!=166)$fatal(1,"Initial movement not tracked: %0d %0d",s1,x1);
  for(f=1;f<=4;f=f+1)begin dx=6+12*f;frame(dx,0);if(s0==2 && x0==160+dx)good0=good0+1;if(s1==2 && x1==160+dx)good1=good1+1;$display("MOTION target=%0d base=%0d/%0d/%0d candidate=%0d/%0d/%0d",160+dx,s0,x0,r0,s1,x1,r1);end
  if(good1<=good0 || good1<3)$fatal(1,"No improvement base=%0d candidate=%0d",good0,good1);
  frame(dx,0); if(s1!=2 || x1!=160+dx)$fatal(1,"Stop failed");
  frame(dx,1);if(s1!=3 || dut.velocity_x!=0 || dut.velocity_y!=0)$fatal(1,"Missing target must hold and clear velocity");
  frame(dx,0);if(s1!=2 || x1!=160+dx)$fatal(1,"Hold recovery failed");
  start(); frame(-6,0);frame(-18,0); if(s1!=2 || x1!=142)$fatal(1,"Negative motion failed status=%0d x=%0d",s1,x1);
  start();frame(6,0);frame(0,0);
  $display("REVERSAL baseline=%0d/%0d candidate=%0d/%0d reason=%0d",s0,x0,s1,x1,r1);
  if(s0!=2 || x0!=160)$fatal(1,"Baseline sudden reversal not tracked");
  if(s1==2 && x1!=160)$fatal(1,"Sudden reversal caused an incorrect lock");
  frame(0,0); if(s1!=2 || x1!=160)$fatal(1,"Sudden reversal did not recover");
  $display("PASS motion prediction: fast exact frames baseline=%0d candidate=%0d; stop, miss/velocity reset, recovery, negative motion",good0,good1);$finish;
 end
 initial begin #300000000;$fatal(1,"timeout");end
endmodule
