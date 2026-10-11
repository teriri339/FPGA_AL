`timescale 1ns / 1ps
//【HX1P35A-移植适配】两级同步、稳定计数消抖和单脉冲按键控制；输入按键低有效。
module hx_button_mode_ctrl #(
    parameter integer DEBOUNCE_CYCLES = 20'd742500
) (
    input wire I_clk,
    input wire I_rst_n,
    input wire [1:0] I_button_n,
    output reg [1:0] O_mode,
    output reg O_alarm_enable
);
    reg [1:0] sync_ff1, sync_ff2, stable_state;
    reg [19:0] count0, count1;
    wire press0 = stable_state[0] && !sync_ff2[0] && (count0 == DEBOUNCE_CYCLES-1);
    wire press1 = stable_state[1] && !sync_ff2[1] && (count1 == DEBOUNCE_CYCLES-1);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            sync_ff1 <= 2'b11; sync_ff2 <= 2'b11; stable_state <= 2'b11;
            count0 <= 0; count1 <= 0; O_mode <= 0; O_alarm_enable <= 1'b1;
        end else begin
            sync_ff1 <= I_button_n;
            sync_ff2 <= sync_ff1;
            if (sync_ff2[0] == stable_state[0]) count0 <= 0;
            else if (count0 == DEBOUNCE_CYCLES-1) begin stable_state[0] <= sync_ff2[0]; count0 <= 0; end
            else count0 <= count0 + 1'b1;
            if (sync_ff2[1] == stable_state[1]) count1 <= 0;
            else if (count1 == DEBOUNCE_CYCLES-1) begin stable_state[1] <= sync_ff2[1]; count1 <= 0; end
            else count1 <= count1 + 1'b1;
            if (press0) O_mode <= O_mode + 1'b1;
            if (press1) O_alarm_enable <= ~O_alarm_enable;
        end
    end
endmodule
