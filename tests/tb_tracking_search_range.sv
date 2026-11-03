`timescale 1ns/1ps
module tb_tracking_search_range #(parameter W=320,H=256,ROW_IDLE=4,ONLY_720P=0);
 reg clk=0;always #5 clk=~clk;reg rst=0,command=0,de=0;
 reg [10:0] x=0,y=0;reg [7:0] luma=0;
 wire [2:0] old_status,new_status;wire [10:0] old_x,old_y,new_x,new_y;wire busy;
 integer xx,yy,f,scenario,dx,dy,old_ok=0,new_ok=0,checks=0,cycles=0,max_cycles=0;
 hx_template_tracker #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),.SEARCH_RADIUS(8),.AUTO_REACQUIRE(0),.FAST_REACQUIRE(0)) old_tracker(
 .clk(clk),.rst_n(rst),.command(command),.de(de),.x(x),.y(y),.luma(luma),.status(old_status),.center_x(old_x),.center_y(old_y),.busy(),.debug_reason(),.debug_best(),.debug_margin(),.debug_misses());
 hx_template_tracker #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),.SEARCH_RADIUS(12),.AUTO_REACQUIRE(0),.FAST_REACQUIRE(0)) dut(
 .clk(clk),.rst_n(rst),.command(command),.de(de),.x(x),.y(y),.luma(luma),.status(new_status),.center_x(new_x),.center_y(new_y),.busy(busy),.debug_reason(),.debug_best(),.debug_margin(),.debug_misses());
 always @(posedge clk)begin
  if(!rst)cycles=0;
  else if(busy)begin cycles=cycles+1;if(cycles>max_cycles)max_cycles=cycles;end
  else cycles=0;
 end
 function integer pattern(input integer a,b);integer p,q;begin
 p=(a*3+b+8192)%47;q=(b*2-a+8192)%37;if(p>23)p=46-p;if(q>18)q=36-q;pattern=40+4*p+3*q;
 end endfunction
 task idle(input integer n);begin repeat(n)begin @(negedge clk);de=0;command=0;end end endtask
 task frame(input integer sx,sy,blanked);begin
 for(yy=0;yy<H;yy=yy+1)begin
 for(xx=0;xx<W;xx=xx+1)begin @(negedge clk);de=1;x=xx;y=yy;luma=blanked?96:pattern(xx-sx,yy-sy);end
 idle(ROW_IDLE);
 end idle(49500);
 if(busy)$fatal(1,"Processing exceeds frame blanking");
 end endtask
 task check_position;begin
 checks=checks+1;
 if(old_status==2 && old_x==W/2+dx && old_y==H/2+dy)old_ok=old_ok+1;
 if(new_status!=2 || new_x!=W/2+dx || new_y!=H/2+dy)$fatal(1,"Wide window failed case=%0d f=%0d status=%0d reason=%0d got=%0d,%0d expected=%0d,%0d",scenario,f,new_status,dut.debug_reason,new_x,new_y,W/2+dx,H/2+dy);
 new_ok=new_ok+1;
 end endtask
 initial begin
 for(scenario=0;scenario<(ONLY_720P?1:4);scenario=scenario+1)begin
 rst=0;idle(4);rst=1;idle(4);@(negedge clk);command=1;idle(1);frame(0,0,0);
 if(new_status!=2 || old_status!=2)$fatal(1,"Learn failed");
 for(f=1;f<=(ONLY_720P?2:6);f=f+1)begin
 dx=scenario==1 ? -12*f : 12*f;dy=scenario==2 ? 12*f : 0;
 if(scenario==3)case(f)1:dx=8;2:dx=26;3:dx=44;4:dx=44;5:dx=36;6:dx=24;endcase
 frame(dx,dy,0);check_position();
 end
 if(!ONLY_720P)begin
 frame(dx,dy,1);if(new_status!=3 || dut.velocity_x!=0 || dut.velocity_y!=0)$fatal(1,"Missing target did not HOLD/clear velocity");
 frame(dx,dy,0);check_position();
 end
 end
 if(new_ok<=old_ok)$fatal(1,"No improved range: old=%0d new=%0d",old_ok,new_ok);
 if(max_cycles>=49500)$fatal(1,"720p processing deadline missed: %0d",max_cycles);
 $display("PASS wider tracking window: old_correct=%0d wide_correct=%0d checks=%0d max_cycles=%0d W=%0d H=%0d",old_ok,new_ok,checks,max_cycles,W,H);$finish;
 end
 initial begin #1500000000;$fatal(1,"timeout");end
endmodule
