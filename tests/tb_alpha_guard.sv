`timescale 1ns/1ps
module tb_alpha_guard;
 reg clk=0; always #5 clk=~clk; reg rst=0; integer checks=0;
 hx_template_tracker #(.IMAGE_WIDTH(1280),.IMAGE_HEIGHT(720),.AUTO_REACQUIRE(0),.FAST_REACQUIRE(0),.PREDICTION_MIN_MARGIN(128)) dut(
  .clk(clk),.rst_n(rst),.command(1'b0),.de(1'b0),.x(11'd0),.y(11'd0),.luma(8'd0),.status(),.center_x(),.center_y(),.busy(),.debug_reason(),.debug_best(),.debug_margin(),.debug_misses());
 task check(input signed [8:0] got, input signed [8:0] expected);begin checks=checks+1;if(got!==expected)$fatal(1,"Velocity got %0d expected %0d",got,expected);end endtask
 initial begin
  repeat(3) @(negedge clk);rst=1;@(negedge clk);
  check(dut.bounded_velocity(106,100,0),96);
  check(dut.bounded_velocity(118,106,96),128);
  check(dut.bounded_velocity(122,118,128),96);
  check(dut.bounded_velocity(122,122,96),0);
  check(dut.bounded_velocity(114,122,96),-128);
  check(dut.bounded_velocity(500,100,0),128);
  check(dut.bounded_velocity(100,500,0),-128);
  if(dut.predicted_center(32,-128,1280)!=32 || dut.predicted_center(1248,128,1280)!=1248)$fatal(1,"Boundary clamp failed");
  if(dut.predicted_center(500,-120,1280)!=492 || dut.predicted_center(500,120,1280)!=508)$fatal(1,"Signed rounding failed");
  force dut.status=2;force dut.phase=5;force dut.best=100;force dut.second_best=170;
  force dut.cx=100;force dut.cy=100;force dut.best_x=106;force dut.best_y=100;
  @(posedge clk);#1;if(dut.velocity_x!==0)$fatal(1,"Weak confidence drove velocity");
  @(negedge clk);force dut.second_best=228;
  @(posedge clk);#1;if(dut.velocity_x!==96)$fatal(1,"Strong confidence failed to update velocity %0d",dut.velocity_x);
  release dut.status;release dut.phase;release dut.best;release dut.second_best;release dut.cx;release dut.cy;release dut.best_x;release dut.best_y;
  $display("PASS alpha-beta fixed-point, bounds, stop, reversal and confidence gating (%0d arithmetic checks)",checks);$finish;
 end
endmodule
