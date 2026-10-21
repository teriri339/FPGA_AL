`timescale 1ns/1ps
module tb_button_sharpen;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0;
    reg [1:0] button_n=2'b11;
    wire [1:0] mode;
    wire [1:0] exposure;
    wire auto_exp, raw_sharpen;
    wire alarm_enable, calibrate, invalidate;

    hx_button_mode_ctrl #(.DEBOUNCE_CYCLES(3), .RAW_SHARP_HOLD_CYCLES(12)) dut (
        .I_clk(clk), .I_rst_n(rst_n), .I_button_n(button_n), .I_cal_busy(1'b0),
        .O_calibrate(calibrate), .O_invalidate_calibration(invalidate), .O_mode(mode),
        .O_alarm_enable(alarm_enable), .O_exposure_level(exposure),
        .O_auto_exposure(auto_exp), .O_raw_sharpen_enable(raw_sharpen)
    );

    task cycles(input integer n);
        integer k;
        begin for(k=0;k<n;k=k+1) @(posedge clk); #1; end
    endtask
    task short_key2;
        begin button_n[0]=0; cycles(7); button_n[0]=1; cycles(7); end
    endtask
    task long_key2;
        begin button_n[0]=0; cycles(20); button_n[0]=1; cycles(7); end
    endtask
    task short_key3;
        begin button_n[1]=0; cycles(7); button_n[1]=1; cycles(7); end
    endtask

    initial begin
        cycles(4); rst_n=1; cycles(4);
        if(mode!==0 || raw_sharpen!==0 || !auto_exp) $fatal(1,"Incorrect reset defaults");
        short_key2();
        if(mode!==1 || raw_sharpen!==0) $fatal(1,"Short KEY2 must only advance display mode");
        long_key2();
        if(mode!==1 || raw_sharpen!==1) $fatal(1,"Long KEY2 must toggle sharp without changing mode");
        short_key2();
        if(mode!==2 || raw_sharpen!==1) $fatal(1,"Short KEY2 must preserve sharp selection and advance mode");
        long_key2();
        if(mode!==2 || raw_sharpen!==0) $fatal(1,"Second long KEY2 must turn sharp off without mode change");
        short_key3();
        if(auto_exp!==0 || exposure!==0) $fatal(1,"KEY3 AUTO-to-EXP0 behavior changed");
        $display("PASS button control: short KEY2 mode cycle preserved; long KEY2 toggles RAW sharp only; KEY3 exposure behavior preserved");
        $finish;
    end
    initial begin #1000000; $fatal(1,"Timeout"); end
endmodule
