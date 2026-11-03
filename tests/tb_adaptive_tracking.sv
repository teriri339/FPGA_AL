`timescale 1ns/1ps
module tb_adaptive_tracking #(parameter W=160,H=128,ROW_IDLE=4,LONG_FRAMES=180);
 reg clk=0;always #5 clk=~clk;reg rst=0,command=0,de=0;
 reg [10:0] x=0,y=0;reg [7:0] luma=0;
 wire [2:0] s0,s1;wire [10:0] x0,y0,x1,y1;wire busy;
 integer appearance=0,k,old_good=0,new_good=0;reg [7:0] frozen[0:63];reg [10:0] saved[0:63];
 integer xx,yy,f,dx,dy=0,direction=1,checks=0,cycles=0,max_cycles=0;
 hx_template_tracker #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),.SEARCH_RADIUS(12),.HOLD_FRAMES(10),.EARLY_RECOVERY(1),.FAST_REACQUIRE(0)) old_dut(
 .clk(clk),.rst_n(rst),.command(command),.de(de),.x(x),.y(y),.luma(luma),.status(s0),.center_x(x0),.center_y(y0),.busy(),.debug_reason(),.debug_best(),.debug_margin(),.debug_misses());
 hx_template_tracker #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),.SEARCH_RADIUS(12),.HOLD_FRAMES(10),.EARLY_RECOVERY(1),.FAST_REACQUIRE(0),.ADAPTIVE_TEMPLATE(1)) dut(
 .clk(clk),.rst_n(rst),.command(command),.de(de),.x(x),.y(y),.luma(luma),.status(s1),.center_x(x1),.center_y(y1),.busy(busy),.debug_reason(),.debug_best(),.debug_margin(),.debug_misses());
 always @(posedge clk)begin if(!rst)cycles=0;else if(busy)begin cycles=cycles+1;if(cycles>max_cycles)max_cycles=cycles;end else cycles=0;end
 function integer pattern(input integer a,b);integer p,q;begin
 p=(a*3+b+8192)%47;q=(b*2-a+8192)%37;if(p>23)p=46-p;if(q>18)q=36-q;pattern=40+4*p+3*q+(((a/8+b/8)%2)==0 ? appearance : -appearance);
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
 restart();for(k=0;k<64;k=k+1)frozen[k]=dut.template_mem[k];
 for(f=0;f<68;f=f+1)begin
 appearance=f/4;frame(0,0,0);
 if(f%4==0)$display("ADAPT f=%0d best=%0d margin=%0d reliable=%0d original=%0d adaptive=%0d",f,dut.debug_best,dut.debug_margin,dut.reliable_frames,dut.template_mem[0],dut.adaptive_mem[0]);
 if(s0==2 && x0==W/2 && y0==H/2)old_good=old_good+1;
 if(s1==2 && x1==W/2 && y1==H/2)new_good=new_good+1;
 else $fatal(1,"Adaptive lost gradual change f=%0d appearance=%0d status=%0d pos=%0d,%0d error=%0d margin=%0d",f,appearance,s1,x1,y1,dut.debug_best,dut.debug_margin);
 for(k=0;k<64;k=k+1)if(dut.template_mem[k]!==frozen[k])$fatal(1,"Original template changed");
 end
 if(new_good<=old_good)$fatal(1,"No gain over frozen template old=%0d new=%0d",old_good,new_good);
 for(k=0;k<64;k=k+1)saved[k]=dut.adaptive_mem[k];
 frame(0,0,1);if(s1!=3)$fatal(1,"Short occlusion must HOLD");
 for(k=0;k<64;k=k+1)if(dut.adaptive_mem[k]!==saved[k])$fatal(1,"Short occlusion updated template");
 frame(0,0,0);if(s1!=2 || x1!=W/2 || y1!=H/2)$fatal(1,"Short occlusion lost adaptive template");
 for(f=0;f<11;f=f+1)begin
 frame(0,0,1);if(s1==2)$fatal(1,"Blank frame falsely accepted");
 for(k=0;k<64;k=k+1)if(dut.adaptive_mem[k]!==saved[k] || dut.template_mem[k]!==frozen[k])$fatal(1,"Occlusion updated template");
 end
 appearance=0;
 for(f=0;f<8;f=f+1)frame(0,0,0);
 if(s1!=2 || x1!=W/2 || y1!=H/2)$fatal(1,"Original-template reacquire failed");
 fork
 begin repeat(4)frame(0,0,0);end
 begin
 wait(dut.phase==12);@(negedge clk);#1;command=1;@(negedge clk);#1;command=0;
 end
 join
 if(s1!=0 || dut.adaptive_valid || dut.use_adaptive)$fatal(1,"Cancel during update did not invalidate partial update");
 for(k=0;k<64;k=k+1)if(dut.template_mem[k]!==frozen[k])$fatal(1,"Cancel changed original template");
 if(max_cycles>=49500)$fatal(1,"Frame processing budget exceeded");
 $display("PASS adaptive tracking: gradual change old=%0d new=%0d; frozen anchor, occlusion freeze, original reacquire; max_cycles=%0d",old_good,new_good,max_cycles);$finish;
 end
 initial begin #2000000000;$fatal(1,"timeout");end
endmodule
