`timescale 1ns/1ps
module tb_template_buttons;
    reg clk=0;always #5 clk=~clk;
    reg rst=0;
    reg [1:0] keys=3;
    wire [1:0] mode,exposure;
    wire auto_exp,sharp,command;
    integer commands=0;
    hx_button_mode_ctrl #(.DEBOUNCE_CYCLES(3),.RAW_SHARP_HOLD_CYCLES(12),
        .ENABLE_TEMPLATE_CONTROL(1),.TEMPLATE_HOLD_CYCLES(12)) dut (
        .I_clk(clk),.I_rst_n(rst),.I_button_n(keys),.I_cal_busy(1'b0),
        .O_calibrate(),.O_invalidate_calibration(),.O_alarm_enable(),.O_mode(mode),
        .O_exposure_level(exposure),.O_auto_exposure(auto_exp),
        .O_raw_sharpen_enable(sharp),.O_template_command(command)
    );
    always @(posedge clk)if(command)commands=commands+1;
    task cycles(input integer count);begin repeat(count)@(negedge clk);end endtask
    initial begin
        cycles(5);rst=1;cycles(5);
        keys[1]=0;cycles(7);
        if(!auto_exp)$fatal(1,"Exposure changed before distinguishing long press");
        keys[1]=1;cycles(7);
        if(auto_exp || exposure!=0 || commands!=0)$fatal(1,"Short KEY3 exposure cycle broken");
        keys[0]=0;cycles(7);keys[0]=1;cycles(7);
        if(mode!=1)$fatal(1,"KEY2 short mode cycle broken");
        keys[1]=0;cycles(60);keys[1]=1;cycles(10);
        if(commands!=1 || mode!=0 || auto_exp || exposure!=0)$fatal(1,"Long KEY3 must issue once, enter RAW and preserve exposure");
        keys[0]=0;cycles(30);keys[0]=1;cycles(7);
        if(!sharp || commands!=1 || mode!=0)$fatal(1,"KEY2 long sharpen changed");
        keys[1]=0;cycles(60);keys[1]=1;cycles(7);
        if(commands!=2 || exposure!=0)$fatal(1,"Second command/release retrigger");
        keys[1]=0;cycles(7);keys[1]=1;cycles(7);
        if(exposure!=1 || commands!=2)$fatal(1,"Short KEY3 after long press broken");
        $display("PASS template buttons: short KEY3 exposure, long KEY3 single command/no exposure change, KEY2 short/long preserved");
        $finish;
    end
    initial begin #100000; $fatal(1,"Timeout");end
endmodule
