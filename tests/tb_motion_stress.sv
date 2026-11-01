`timescale 1ns/1ps
module tb_motion_stress;
 localparam W=320,H=256;
 reg clk=0;always #5 clk=~clk;reg rst=0,command=0,de=0;
 reg [10:0] x=0,y=0;reg [7:0] luma=0;
 wire [2:0] s0,s1;wire [10:0] x0,y0,x1,y1;
 integer xx,yy,scenario,f,dx,dy,v,delta,base_ok,candidate_ok,base_false,candidate_false,fast0=0,fast1=0;
 hx_template_tracker #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),.AUTO_REACQUIRE(0),.FAST_REACQUIRE(0),.ENABLE_MOTION_PREDICTION(0)) base(.clk(clk),.rst_n(rst),.command(command),.de(de),.x(x),.y(y),.luma(luma),.status(s0),.center_x(x0),.center_y(y0),.busy(),.debug_reason(),.debug_best(),.debug_margin(),.debug_misses());
 hx_template_tracker #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),.AUTO_REACQUIRE(0),.FAST_REACQUIRE(0),.ENABLE_MOTION_PREDICTION(1)) dut(.clk(clk),.rst_n(rst),.command(command),.de(de),.x(x),.y(y),.luma(luma),.status(s1),.center_x(x1),.center_y(y1),.busy(),.debug_reason(),.debug_best(),.debug_margin(),.debug_misses());
 function integer pattern(input integer a,b,kind); integer p,q;begin
  p=(a*(kind+2)+b+8192)%47;q=(b*(kind+2)-a+8192)%37;
  if(p>23)p=46-p;if(q>18)q=36-q;pattern=40+4*p+3*q;
 end endfunction
 task idle(input integer cycles);begin repeat(cycles)begin @(negedge clk);de=0;command=0;end end endtask
 task frame(input integer dx,dy,kind,noise,brightness);begin
  for(yy=0;yy<H;yy=yy+1)begin
   for(xx=0;xx<W;xx=xx+1)begin @(negedge clk);de=1;x=xx;y=yy;
    v=pattern(xx-dx,yy-dy,kind)+brightness;if(noise)v=v+((xx*13+yy*7+f*19)%9-4);
    luma=v<0?0:v>255?255:v;
   end idle(4);
  end idle(49500);
 end endtask
 task restart(input integer kind);begin rst=0;idle(4);rst=1;idle(4);@(negedge clk);command=1;idle(1);f=0;frame(0,0,kind,0,0);if(s0!=2 || s1!=2)$fatal(1,"Learn failure %0d",kind);end endtask
 initial begin
  for(scenario=0;scenario<4;scenario=scenario+1)begin
   restart(scenario);base_ok=0;candidate_ok=0;base_false=0;candidate_false=0;
   for(f=1;f<=6;f=f+1)begin
    delta=(f==1)?6:6+12*(f-1);dx=(scenario==1)?-delta:delta;dy=(scenario==2)?delta:0;
    frame(dx,dy,scenario,scenario==3,scenario==3?12:0);
    $display("STEP case=%0d f=%0d target=%0d,%0d got=%0d,%0d st=%0d vel=%0d,%0d margin=%0d",scenario,f,160+dx,128+dy,x1,y1,s1,dut.velocity_x,dut.velocity_y,dut.debug_margin);
    if(s0==2 && $signed({1'b0,x0})>=160+dx-2 && $signed({1'b0,x0})<=160+dx+2 && $signed({1'b0,y0})>=128+dy-2 && $signed({1'b0,y0})<=128+dy+2)base_ok=base_ok+1;else if(s0==2)base_false=base_false+1;
    if(s1==2 && $signed({1'b0,x1})>=160+dx-2 && $signed({1'b0,x1})<=160+dx+2 && $signed({1'b0,y1})>=128+dy-2 && $signed({1'b0,y1})<=128+dy+2)candidate_ok=candidate_ok+1;else if(s1==2)candidate_false=candidate_false+1;
   end
   $display("STRESS case=%0d baseline_correct=%0d false=%0d candidate_correct=%0d false=%0d",scenario,base_ok,base_false,candidate_ok,candidate_false);
   fast0=fast0+base_ok;fast1=fast1+candidate_ok;
  end
  if(fast1<=fast0)$fatal(1,"No aggregate improvement: baseline=%0d candidate=%0d",fast0,fast1);
  $display("PASS motion stress aggregate baseline=%0d candidate=%0d across 24 frames; see false-lock counts per case",fast0,fast1);$finish;
 end
 initial begin #500000000;$fatal(1,"timeout");end
endmodule

