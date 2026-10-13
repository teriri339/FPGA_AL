/*******************************MILIANKE*******************************
*Company : MiLianKe Electronic Technology Co., Ltd.
*WebSite:https://www.milianke.com
*TechWeb:https://www.uisrc.com
*tmall-shop:https://milianke.tmall.com
*jd-shop:https://milianke.jd.com
*taobao-shop1: https://milianke.taobao.com
*Create Date: 2023/03/23
*Module Name:
*File Name:
*Description: 
*The reference demo provided by Milianke is only used for learning. 
*We cannot ensure that the demo itself is free of bugs, so users 
*should be responsible for the technical problems and consequences
*caused by the use of their own products.
*Copyright: Copyright (c) MiLianKe
*All rights reserved.
*Revision: 1.0
*Signal description
*1) I_ input
*2) O_ output
*3) IO_ input output
*4) S_ system internal signal
*5) _n activ low
*6) _dg debug signal 
*7) _r delay or register
*8) _s state mechine
*********************************************************************/
/*********ae_set �ֶ��������AE ***********
--�汾��1.0
*********************************************************************/

module ae_set
(
input wire I_clk,
input wire I_rst,
input wire [3:0]I_btn,
input wire I_exposure_step, //【HX1P35A-移植适配】24 MHz 域内消抖后的 KEY3 单周期曝光切换脉冲。
input wire I_ae_cfg_done,
input wire I_cam_cfg_done,
output wire O_ae_req,
output wire [15:0] O_ae,
output wire [15:0] O_ag
);
	

reg 	[19:0] 	rc_ae_tick = 0; 
reg 			r_ae_tick = 0; 
reg 	[4:0] 	rc_ag_tick = 0; 
reg 			r_ag_tick = 0; 
	
always @(posedge I_clk or posedge I_rst) begin
	if(I_rst) begin
		rc_ae_tick <= 0; 
		r_ae_tick <= 0; 
		rc_ag_tick <= 0; 
		r_ag_tick <= 0; 
	end else begin
	//	Trigger AE Inc / Dec per 1 ms. 
		rc_ae_tick <= rc_ae_tick + 1; 
		r_ae_tick <= 0; 
		if(rc_ae_tick >= 99999) begin
			rc_ae_tick <= 0; 
			r_ae_tick <= 1; 
		end 
	//	Trigger AG Inc / Dec per 32 ms. 
		rc_ag_tick <= rc_ag_tick + r_ae_tick; 
		r_ag_tick <= (&rc_ag_tick) && r_ae_tick; 
	end
end
	
//	Use button to add / sub idelay values. I_button[0]:IncDatDly, [1]DecDatDly, [2]IncI_clkDly, [3]DecI_clkDly
reg 	[3:0] 	r_button_0 = 0, r_button_1 = 0; 
reg     [1:0]   r_exposure_level = 2'd2; //【HX1P35A-移植适配】记录已处理档位，避免重复发起 I2C 更新。
// 720p60 uses VTS=1000. Exposure is expressed in half-line units, so 1990
// is close to the legal maximum. AG=80 maps to the selected 4x gain setting.
reg 	[15:0] 	r_ae_set = 1990, r_ag_set = 80; 
always @(posedge I_clk or posedge I_rst) begin
	if(I_rst) begin
		r_button_0 <= 0; 
		r_button_1 <= 0; 
		r_ae_set <= 1990; 
		r_ag_set <= 80; 
		r_exposure_level <= 2'd2; //【HX1P35A-移植适配】默认档 2 与上电首次应用值一致。
	end else begin
	//	When button pressed, r_button_1 bit is 1. 
		r_button_0 <= ~I_btn; 
		r_button_1 <= r_button_0; 
	
		if (I_exposure_step) begin //【HX1P35A-移植适配】每次 KEY3 有效按下只切换一次，避免按住时连续跳档。
			r_exposure_level <= r_exposure_level + 1'b1; //【HX1P35A-移植适配】四档循环。
			case (r_exposure_level) //【HX1P35A-移植适配】case 使用当前档位，写入下一档参数。
				2'd0: begin r_ae_set <= 16'd1200; r_ag_set <= 16'd48;  end //【HX1P35A-移植适配】切换到 EXP:1，中亮、约 2x 增益。
				2'd1: begin r_ae_set <= 16'd1990; r_ag_set <= 16'd80;  end //【HX1P35A-移植适配】切换到 EXP:2，默认、约 4x 增益。
				2'd2: begin r_ae_set <= 16'd1990; r_ag_set <= 16'd144; end //【HX1P35A-移植适配】切换到 EXP:3，暗光、约 16x 增益。
				default: begin r_ae_set <= 16'd600; r_ag_set <= 16'd16; end //【HX1P35A-移植适配】切换回 EXP:0，低亮、约 1x 增益。
			endcase
		end else if(r_button_1[0]) begin
			r_ae_set <= (r_ae_set > 2) ? r_ae_set - r_ae_tick : r_ae_set; 
		end else if(r_button_1[1]) begin
			r_ae_set <= (r_ae_set < 1990) ? r_ae_set + r_ae_tick : r_ae_set; 
		end 
		if(r_button_1[2]) begin
				r_ag_set <= (r_ag_set > 16) ? r_ag_set - r_ag_tick : r_ag_set; 
		end else if(r_button_1[3]) begin
				r_ag_set <= (r_ag_set < 89) ? r_ag_set + r_ag_tick : r_ag_set; 
		end 
		end
	end
	
//	Update AG / AE when changed. 
reg 	[15:0] 	r_ae ; 
reg 	[15:0] 	r_ag ; 
reg 			r_ae_req = 0; //synthesis keep
reg             r_ae_applied = 0; //【HX1P35A-移植适配】保证 SC520 初始化完成后至少下发一次曝光/增益。
assign O_ae = r_ae;
assign O_ag = r_ag;
assign O_ae_req = r_ae_req;

always @(posedge I_clk or posedge I_rst) begin
	if(I_rst) begin
		r_ae_req <= 0; 
		r_ae     <= 1990; 
		r_ag     <= 80; 
		r_ae_applied <= 0; //【HX1P35A-移植适配】传感器复位后重新应用 4x 默认增益。
	end else if(r_ae_req) begin
		r_ae_req <= 0; 
	end else if((!r_ae_applied || (r_ae != r_ae_set) || (r_ag != r_ag_set))&&(I_cam_cfg_done==1'b1)&&(I_ae_cfg_done==1'b1)) begin //【HX1P35A-移植适配】修复初值相同导致首次增益从未写入。
		r_ae     <= r_ae_set; 
		r_ag     <= r_ag_set; 
		r_ae_req <= 1; 
		r_ae_applied <= 1; //【HX1P35A-移植适配】首次写入完成请求已发出。
	end
end


endmodule


	
