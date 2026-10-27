`timescale 1ns / 1ps
//【HX1P35A-移植适配】两级同步、稳定计数消抖和单脉冲按键控制；输入按键低有效。
module hx_button_mode_ctrl #(
    parameter integer DEBOUNCE_CYCLES = 20'd742500
) (
    input wire I_clk,
    input wire I_rst_n,
    input wire [1:0] I_button_n,
<<<<<<< Updated upstream
    output reg [1:0] O_mode,
=======
    input wire I_cal_busy,
    output reg O_calibrate,O_invalidate_calibration,
    output reg [2:0] O_mode,
>>>>>>> Stashed changes
    output reg O_alarm_enable,
    output reg [1:0] O_exposure_level, //【HX1P35A-移植适配】KEY3 手动曝光档位。
    output reg O_auto_exposure //【HX1P35A-移植适配】上电默认启用自动曝光。
);
    reg [1:0] sync_ff1, sync_ff2, stable_state;
    reg [19:0] count0, count1;
    wire press0 = stable_state[0] && !sync_ff2[0] && (count0 == DEBOUNCE_CYCLES-1);
    wire press1 = stable_state[1] && !sync_ff2[1] && (count1 == DEBOUNCE_CYCLES-1);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            sync_ff1 <= 2'b11; sync_ff2 <= 2'b11; stable_state <= 2'b11;
            count0 <= 0; count1 <= 0; O_mode <= 0; O_alarm_enable <= 1'b1;
            O_exposure_level <= 2'd2; //【HX1P35A-移植适配】退出自动曝光前的初始手动档位。
            O_auto_exposure <= 1'b1; //【HX1P35A-移植适配】上电直接根据画面亮度闭环调节。
        end else begin
            sync_ff1 <= I_button_n;
            sync_ff2 <= sync_ff1;
            if (sync_ff2[0] == stable_state[0]) count0 <= 0;
            else if (count0 == DEBOUNCE_CYCLES-1) begin stable_state[0] <= sync_ff2[0]; count0 <= 0; end
            else count0 <= count0 + 1'b1;
            if (sync_ff2[1] == stable_state[1]) count1 <= 0;
            else if (count1 == DEBOUNCE_CYCLES-1) begin stable_state[1] <= sync_ff2[1]; count1 <= 0; end
            else count1 <= count1 + 1'b1;
<<<<<<< Updated upstream
            if (press0) O_mode <= O_mode + 1'b1;
            if (press1) begin //【HX1P35A-移植适配】KEY3 循环 AUTO、EXP0、EXP1、EXP2、EXP3。
=======
            if(!SELF_CALIBRATION)begin
                if(release0)begin
                    if(!long_handled)O_mode<= (O_mode==3'd4) ? 3'd0 : O_mode+1'b1; //【GRAD】五档循环 RAW/GRAY/COLOR/CANNY/GRAD。
                    long_handled<=0;
                    hold_count<=0;
                end else if(!stable_state[0])begin
                    if(!long_handled)begin
                        if(hold_count>=RAW_SHARP_HOLD_CYCLES-1)begin
                            O_raw_sharpen_enable<=~O_raw_sharpen_enable;
                            long_handled<=1;
                        end else hold_count<=hold_count+1'b1;
                    end
                end else begin
                    hold_count<=0;
                    long_handled<=0;
                end
            end else begin
                if(stable_state[0])hold_count<=0;
                else if(!long_handled && !I_cal_busy)begin
                    if(hold_count==CAL_HOLD_CYCLES-1)begin
                        O_calibrate<=1;long_handled<=1;O_mode<=0;
                        if(O_auto_exposure)begin O_auto_exposure<=0;O_exposure_level<=0;end
                    end else hold_count<=hold_count+1'b1;
                end
                if(release0)begin
                    if(!long_handled && !I_cal_busy)O_mode<= (O_mode==3'd4) ? 3'd0 : O_mode+1'b1;
                    long_handled<=0;hold_count<=0;
                end
            end
            if (exposure_press && (!SELF_CALIBRATION || !I_cal_busy)) begin // Short KEY3 still cycles exposure; long KEY3 never changes it.
                if(SELF_CALIBRATION)O_invalidate_calibration<=1;
>>>>>>> Stashed changes
                if (O_auto_exposure) begin
                    O_auto_exposure <= 1'b0; //【HX1P35A-移植适配】AUTO 后进入最低手动曝光档。
                    O_exposure_level <= 2'd0; //【HX1P35A-移植适配】手动 EXP0。
                end else if (O_exposure_level == 2'd3) begin
                    O_auto_exposure <= 1'b1; //【HX1P35A-移植适配】EXP3 后返回自动曝光。
                end else begin
                    O_exposure_level <= O_exposure_level + 1'b1; //【HX1P35A-移植适配】手动曝光逐档增加。
                end
            end
        end
    end
endmodule
