`timescale 1ns/1ps
module tb_display_mode_cycle;
 reg clk=0;always #5 clk=~clk;reg rst=0;reg [1:0] keys=3;
 wire [1:0] mode,cal_mode;wire sharp,command,auto_exp;integer i,commands=0;
 hx_button_mode_ctrl #(.DEBOUNCE_CYCLES(2),.RAW_SHARP_HOLD_CYCLES(200),.ENABLE_TEMPLATE_CONTROL(1),.TEMPLATE_HOLD_CYCLES(200)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_button_n(keys),.I_cal_busy(1'b0),.O_mode(mode),.O_raw_sharpen_enable(sharp),.O_template_command(command),.O_auto_exposure(auto_exp));
 hx_button_mode_ctrl #(.DEBOUNCE_CYCLES(2),.SELF_CALIBRATION(1),.CAL_HOLD_CYCLES(200)) cal(
 .I_clk(clk),.I_rst_n(rst),.I_button_n(keys),.I_cal_busy(1'b0),.O_mode(cal_mode));
 always @(posedge clk)if(rst && command)commands=commands+1;
 task wait_cycles(input integer n);begin repeat(n)@(negedge clk);end endtask
 task press(input [1:0] k,input integer n);begin keys=k;wait_cycles(n);keys=3;wait_cycles(12);end endtask
 initial begin
 wait_cycles(4);rst=1;wait_cycles(4);
 for(i=0;i<9;i=i+1)begin
 press(2'b10,8);
 if(mode!==(i%3==0?2'd1:i%3==1?2'd3:2'd0) || cal_mode!==mode)$fatal(1,"Invalid mode cycle %0d mode=%0d cal=%0d",i,mode,cal_mode);
 end
 press(2'b10,220);if(mode!=0 || !sharp)$fatal(1,"Long KEY2 changed mode instead of sharpness");
 press(2'b01,8);if(auto_exp!==0 || commands!=0)$fatal(1,"Short KEY3 exposure broken");
 press(2'b01,220);if(commands!=1 || mode!=0)$fatal(1,"Long KEY3 template lock broken");
 $display("PASS RAW/GRAY/CANNY cycle, no COLOR, sharpness/exposure/template controls retained");$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
