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
input wire I_auto_enable, //【HX1P35A-移植适配】1：根据画面亮度自动曝光；0：使用 KEY3 手动档位。
input wire [1:0] I_manual_exposure_level, //【HX1P35A-移植适配】手动 EXP0~3 档位。
input wire [7:0] I_frame_luma, //【HX1P35A-移植适配】视频域输出的全帧平均亮度。
input wire I_frame_luma_toggle, //【HX1P35A-移植适配】每帧翻转一次的亮度更新标志。
input wire I_ae_cfg_done,
input wire I_cam_cfg_done,
output wire O_ae_req,
output wire [15:0] O_ae,
output wire [15:0] O_ag
);

//【HX1P35A-移植适配】异步控制量在 24 MHz 摄像头配置域内做两级同步；亮度总线在翻转标志到达前已稳定一帧。
(* async_reg = "true" *) reg r_auto_meta = 0, r_auto_sync = 0; //【HX1P35A-移植适配】自动曝光状态两级同步器。
reg r_auto_prev = 0; //【HX1P35A-移植适配】同步后自动曝光状态的边沿检测。
(* async_reg = "true" *) reg [1:0] r_manual_meta = 2'd2, r_manual_sync = 2'd2; //【HX1P35A-移植适配】手动档位两级同步器。
reg [1:0] r_manual_prev = 2'd2; //【HX1P35A-移植适配】同步后手动档位变化检测。
(* async_reg = "true" *) reg [7:0] r_luma_meta = 0, r_luma_sync = 0; //【HX1P35A-移植适配】帧平均亮度两级同步器。
(* async_reg = "true" *) reg [2:0] r_luma_toggle_sync = 0; //【HX1P35A-移植适配】三级同步用于可靠检测新帧。
wire w_new_luma = r_luma_toggle_sync[2] ^ r_luma_toggle_sync[1]; //【HX1P35A-移植适配】新亮度数据单周期脉冲。

always @(posedge I_clk or posedge I_rst) begin
	if(I_rst) begin
		r_auto_meta <= 0; r_auto_sync <= 0; //【HX1P35A-移植适配】复位跨域同步链。
		r_manual_meta <= 2'd2; r_manual_sync <= 2'd2; //【HX1P35A-移植适配】默认手动档 2。
		r_luma_meta <= 0; r_luma_sync <= 0; r_luma_toggle_sync <= 0; //【HX1P35A-移植适配】复位亮度跨域同步链。
	end else begin
		r_auto_meta <= I_auto_enable; r_auto_sync <= r_auto_meta; //【HX1P35A-移植适配】同步自动曝光使能。
		r_manual_meta <= I_manual_exposure_level; r_manual_sync <= r_manual_meta; //【HX1P35A-移植适配】同步手动档位。
		r_luma_meta <= I_frame_luma; r_luma_sync <= r_luma_meta; //【HX1P35A-移植适配】同步稳定的帧亮度值。
		r_luma_toggle_sync <= {r_luma_toggle_sync[1:0],I_frame_luma_toggle}; //【HX1P35A-移植适配】同步亮度更新翻转标志。
	end
end

//【HX1P35A-移植适配】720p60 VTS=1000，曝光使用半行单位，1990 接近合法上限；增益控制范围 16~176。
localparam [7:0] C_LUMA_DARK = 8'd72; //【HX1P35A-移植适配】低于此值逐步增亮。
localparam [7:0] C_LUMA_BRIGHT = 8'd145; //【HX1P35A-移植适配】高于此值逐步变暗，中间形成防抖死区。
reg [3:0] r_auto_frame_count = 0; //【HX1P35A-移植适配】每 16 帧最多调整一次，等待传感器和 DDR 画面稳定。
reg [15:0] r_ae_set = 1990, r_ag_set = 80; //【HX1P35A-移植适配】自动曝光目标快门和增益。

always @(posedge I_clk or posedge I_rst) begin
	if(I_rst) begin
		r_ae_set <= 16'd1990; r_ag_set <= 16'd80; //【HX1P35A-移植适配】上电从中高曝光开始闭环。
		r_auto_prev <= 1'b0; r_manual_prev <= 2'd2; r_auto_frame_count <= 0; //【HX1P35A-移植适配】复位模式检测和调节间隔。
	end else begin
		r_auto_prev <= r_auto_sync; r_manual_prev <= r_manual_sync; //【HX1P35A-移植适配】保存同步后的模式供下周期检测变化。
		if (!r_auto_sync) begin
			r_auto_frame_count <= 0; //【HX1P35A-移植适配】手动模式停止自动调节计时。
			if (r_auto_prev || (r_manual_prev != r_manual_sync)) begin
				case (r_manual_sync) //【HX1P35A-移植适配】手动模式保持原四档参数。
					2'd0: begin r_ae_set <= 16'd600;  r_ag_set <= 16'd16;  end //【HX1P35A-移植适配】EXP0：约 1x。
					2'd1: begin r_ae_set <= 16'd1200; r_ag_set <= 16'd48;  end //【HX1P35A-移植适配】EXP1：约 2x。
					2'd2: begin r_ae_set <= 16'd1990; r_ag_set <= 16'd80;  end //【HX1P35A-移植适配】EXP2：约 4x。
					default: begin r_ae_set <= 16'd1990; r_ag_set <= 16'd144; end //【HX1P35A-移植适配】EXP3：暗光高增益。
				endcase
			end
		end else if (!r_auto_prev) begin
			r_auto_frame_count <= 0; //【HX1P35A-移植适配】进入 AUTO 后先等待 16 帧再判断，避免沿用旧画面。
		end else if (w_new_luma) begin
			if (r_auto_frame_count != 4'hf) begin
				r_auto_frame_count <= r_auto_frame_count + 1'b1; //【HX1P35A-移植适配】降低调节频率，抑制闪烁。
			end else begin
				r_auto_frame_count <= 0; //【HX1P35A-移植适配】约 0.27 秒执行一次闭环调整。
				if (r_luma_sync < C_LUMA_DARK) begin
					if (r_ae_set < 16'd1990)
						r_ae_set <= (r_ae_set > 16'd1830) ? 16'd1990 : r_ae_set + 16'd160; //【HX1P35A-移植适配】暗时先延长曝光。
					else if (r_ag_set < 16'd176)
						r_ag_set <= (r_ag_set > 16'd168) ? 16'd176 : r_ag_set + 16'd8; //【HX1P35A-移植适配】曝光到顶后逐级增加增益。
				end else if (r_luma_sync > C_LUMA_BRIGHT) begin
					if (r_ag_set > 16'd16)
						r_ag_set <= (r_ag_set < 16'd24) ? 16'd16 : r_ag_set - 16'd8; //【HX1P35A-移植适配】过亮时先降低噪声更大的增益。
					else if (r_ae_set > 16'd300)
						r_ae_set <= (r_ae_set < 16'd460) ? 16'd300 : r_ae_set - 16'd160; //【HX1P35A-移植适配】最低增益后再缩短曝光。
				end
			end
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


	
