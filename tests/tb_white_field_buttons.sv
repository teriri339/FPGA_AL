`timescale 1ns/1ps
module tb_white_field_buttons;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,busy=0;
    reg [1:0] buttons=3;
    wire [1:0] mode,exposure;
    wire auto_exp,request,invalidate;
    integer requests=0,clears=0;
    hx_button_mode_ctrl #(.DEBOUNCE_CYCLES(2),.SELF_CALIBRATION(1),.CAL_HOLD_CYCLES(12)) dut (
        .I_clk(clk),.I_rst_n(rst),.I_button_n(buttons),.I_cal_busy(busy),
        .O_calibrate(request),.O_invalidate_calibration(invalidate),
        .O_mode(mode),.O_alarm_enable(),.O_exposure_level(exposure),.O_auto_exposure(auto_exp));
    always @(posedge clk)begin if(request)requests=requests+1;if(invalidate)clears=clears+1;end
    task cycles;input integer n;begin repeat(n)@(negedge clk);end endtask
    initial begin
        cycles(3);rst=1;cycles(6);
        buttons[0]=0;cycles(8);buttons[0]=1;cycles(8);
        if(mode!=1||requests!=0)$fatal(1,"Short KEY2 action incorrect");
        buttons[0]=0;cycles(35);
        if(requests!=1||mode!=0||auto_exp||exposure!=0)$fatal(1,"Long KEY2 did not lock manual exposure and trigger raw calibration");
        busy=1;buttons[1]=0;cycles(8);buttons[1]=1;cycles(8);
        if(clears!=0||exposure!=0)$fatal(1,"KEY3 changed exposure during capture");
        buttons[0]=1;cycles(8);busy=0;
        if(mode!=0||requests!=1)$fatal(1,"Long-release caused an unwanted short press");
        buttons[1]=0;cycles(8);buttons[1]=1;cycles(8);
        if(clears!=1||exposure!=1)$fatal(1,"KEY3 did not invalidate the old profile");
        $display("PASS: short/long KEY2, one-shot request, fixed exposure, busy lockout, exposure invalidation");
        $finish;
    end
endmodule
