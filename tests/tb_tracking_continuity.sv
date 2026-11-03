`timescale 1ns/1ps
module tb_tracking_continuity #(parameter W=256,H=160,ROW_IDLE=4,LONG_FRAMES=180);
 reg clk=0;always #5 clk=~clk;reg rst=0,command=0,de=0;
 reg [10:0] x=0,y=0;reg [7:0] luma=0;
 wire [2:0] s0,s1;wire [10:0] x0,y0,x1,y1;wire busy;
 integer xx,yy,f,dx,dy=0,direction=1,checks=0,cycles=0,max_cycles=0;
 hx_template_tracker #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),.SEARCH_RADIUS(12),.HOLD_FRAMES(16),.FAST_REACQUIRE(1)) old_dut(
 .clk(clk),.rst_n(rst),.command(command),.de(de),.x(x),.y(y),.luma(luma),.status(s0),.center_x(x0),.center_y(y0),.busy(),.debug_reason(),.debug_best(),.debug_margin(),.debug_misses());
 hx_template_tracker #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),.SEARCH_RADIUS(12),.HOLD_FRAMES(10),.EARLY_RECOVERY(1),.FAST_REACQUIRE(1),.ADAPTIVE_TEMPLATE(1)) dut(
 .clk(clk),.rst_n(rst),.command(command),.de(de),.x(x),.y(y),.luma(luma),.status(s1),.center_x(x1),.center_y(y1),.busy(busy),.debug_reason(),.debug_best(),.debug_margin(),.debug_misses());
 always @(posedge clk)begin if(!rst)cycles=0;else if(busy)begin cycles=cycles+1;if(cycles>max_cycles)max_cycles=cycles;end else cycles=0;end
 function integer pattern(input integer a,b);integer p,q;begin
 p=(a*3+b+8192)%47;q=(b*2-a+8192)%37;if(p>23)p=46-p;if(q>18)q=36-q;pattern=40+4*p+3*q;
 end endfunction
 task idle(input integer n);begin repeat(n)begin @(negedge clk);de=0;command=0;end end endtask
 task frame(input integer sx,sy,blanked);integer v;begin
 for(yy=0;yy<H;yy=yy+1)begin
 for(xx=0;xx<W;xx=xx+1)begin @(negedge clk);de=1;x=xx;y=yy;
 v=pattern(xx-sx,yy-sy);luma=blanked?96:v;
 end idle(ROW_IDLE);end idle(49500);
 if(busy)$fatal(1,"Frame deadline missed");end endtask
 task check;begin checks=checks+1;
 if(s1!=2 || x1!=W/2+dx || y1!=H/2+dy)$fatal(1,"Continuity failed frame=%0d state=%0d reason=%0d got=%0d,%0d expected=%0d,%0d",f,s1,dut.debug_reason,x1,y1,W/2+dx,H/2+dy);
 end endtask
 task restart;begin rst=0;idle(4);rst=1;idle(4);@(negedge clk);command=1;idle(1);dx=0;dy=0;frame(0,0,0);check();end endtask
 initial begin
 restart();dx=8;frame(dx,0,0);check();dx=16;frame(dx,0,1);
 if(s1!=3)$fatal(1,"Occlusion must HOLD");
 dx=24;frame(dx,0,0);check();
 if(s0==2 && x0==W/2+dx)$fatal(1,"Regression case failed to distinguish old behavior");
 $display("Recovered moving target immediately after one missing frame; old state=%0d reason=%0d",s0,old_dut.debug_reason);
 for(direction=-1;direction<=1;direction=direction+2)begin
 restart();dx=direction*8;frame(dx,0,0);check();
 frame(dx,0,0);check();
 if(dut.velocity_x!=direction*128)$fatal(1,"Single repeated frame cleared speed");
 dx=direction*24;frame(dx,0,0);check();
 if(s0==2 && x0==W/2+dx)$fatal(1,"Duplicate-frame comparison did not distinguish old behavior");
 frame(dx,0,0);check();frame(dx,0,0);check();
 if(dut.velocity_x!=0)$fatal(1,"Two stationary frames must clear speed");
 dx=dx-direction*8;frame(dx,0,0);check();
 end
 restart();direction=1;
 for(f=0;f<LONG_FRAMES;f=f+1)begin
 if(dx>=56)direction=-1;if(dx<=-56)direction=1;dx=dx+direction*4;
 frame(dx,0,(f%37)==20);
 if((f%37)==20)begin if(s1!=3)$fatal(1,"Blank scene false TRACK");end
 else check();
 end
 restart();dx=8;frame(dx,0,0);check();
 frame(dx,0,1);if(s1!=3)$fatal(1,"First miss must HOLD");
 frame(dx,0,1);if(s1!=3)$fatal(1,"Second miss must HOLD");
 if(!dut.g_fast.u_proposer.collect && dut.g_fast.u_proposer.phase==0)$fatal(1,"Coarse recovery did not start during HOLD");
 for(f=3;f<=10;f=f+1)begin
 frame(dx,0,1);
 if(f<10 && s1!=3)$fatal(1,"Must remain HOLD through miss 9, miss=%0d state=%0d",f,s1);
 if(f==10 && (s1!=4 || s0!=3))$fatal(1,"Must enter LOST on miss 10; reference still HOLD");
 end
 @(negedge clk);command=1;idle(1);if(s1!=1)$fatal(1,"Reselection after loss failed");
 if(max_cycles>=49500)$fatal(1,"Processing deadline");
 $display("PASS tracking continuity: %0d checks, %0d sustained frames with reversals/occlusions, early scan, 10-miss recovery, max_cycles=%0d",checks,LONG_FRAMES,max_cycles);$finish;
 end
 initial begin #2000000000;$fatal(1,"timeout");end
endmodule
