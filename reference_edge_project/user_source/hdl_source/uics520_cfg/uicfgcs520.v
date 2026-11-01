`timescale 1ns / 1ps

module uicfgcs520 #(
    parameter integer CLK_DIV = 16'd239
) (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_ae_req,
    input  wire [15:0] I_ae,
    input  wire [15:0] I_ag,
    output wire        O_cam_scl,
    inout  wire        IO_cam_sda,
    output reg         O_cfg_done,
    output reg         O_ae_cfg_done,
    output reg  [15:0] O_sensor_id,
    output reg         O_sensor_id_ok,
    output reg         O_iic_error,
    input  wire        I_applied_snapshot_ack,
    output reg         O_applied_snapshot_req,
    output reg  [15:0] O_applied_exposure_mailbox,
    output reg  [23:0] O_applied_gain_regs_mailbox,
    output reg  [1:0]  O_applied_status_mailbox,
    output reg         O_applied_has_value_mailbox
);
    localparam [7:0] CAM_ID = 8'h6c;

    localparam [3:0] ST_IDH_REQ  = 4'd0;
    localparam [3:0] ST_IDH_BUSY = 4'd1;
    localparam [3:0] ST_IDH_DONE = 4'd2;
    localparam [3:0] ST_IDL_REQ  = 4'd3;
    localparam [3:0] ST_IDL_BUSY = 4'd4;
    localparam [3:0] ST_IDL_DONE = 4'd5;
    localparam [3:0] ST_CHECK_ID = 4'd6;
    localparam [3:0] ST_IDLE     = 4'd7;
    localparam [3:0] ST_WR_REQ   = 4'd8;
    localparam [3:0] ST_WR_BUSY  = 4'd9;
    localparam [3:0] ST_WR_DONE  = 4'd10;
    localparam [3:0] ST_ERROR    = 4'd11;
    localparam [3:0] ST_RESET_WAIT = 4'd12;
    localparam [3:0] ST_WAIT_SNAPSHOT_ACK = 4'd13;
    localparam integer RESET_WAIT_CYCLES = 119048; // 5 ms at 23.809524 MHz
    localparam [1:0] APPLIED_WAIT = 2'd0, APPLIED_WRITING = 2'd1,
                     APPLIED_OK = 2'd2, APPLIED_ERROR = 2'd3;

    reg  [3:0]  state;
    reg         iic_req;
    reg         iic_mode;
    reg  [7:0]  wr_cnt;
    reg  [7:0]  rd_cnt;
    reg  [31:0] wr_data;
    reg  [8:0]  reg_index;
    reg  [16:0] reset_wait_cnt;
    reg         ae_table_active;
    reg         ae_req_pending;
    reg         ae_transaction_error;
    (* async_reg = "true" *) reg [1:0] snapshot_ack_sync;
    wire        snapshot_pending = O_applied_snapshot_req ^ snapshot_ack_sync[1];
    wire        iic_busy;
    wire        iic_bus_error;
    wire [7:0]  rd_data;

    wire [23:0] init_reg_data;
    wire [8:0]  init_reg_size;
    wire [23:0] ae_reg_data;
    wire [8:0]  ae_reg_size;
    wire [23:0] gain_value;
    wire [23:0] selected_reg_data = ae_table_active ? ae_reg_data : init_reg_data;
    wire [8:0]  selected_reg_size = ae_table_active ? ae_reg_size : init_reg_size;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            state            <= ST_IDH_REQ;
            iic_req          <= 1'b0;
            iic_mode         <= 1'b1;
            wr_cnt           <= 8'd3;
            rd_cnt           <= 8'd1;
            wr_data          <= 32'd0;
            reg_index        <= 9'd0;
            reset_wait_cnt   <= 17'd0;
            ae_table_active  <= 1'b0;
            ae_req_pending   <= 1'b0;
            ae_transaction_error <= 1'b0;
            snapshot_ack_sync <= 2'b00;
            O_applied_snapshot_req <= 1'b0;
            O_applied_exposure_mailbox <= 16'd0;
            O_applied_gain_regs_mailbox <= 24'd0;
            O_applied_status_mailbox <= APPLIED_WAIT;
            O_applied_has_value_mailbox <= 1'b0;
            O_cfg_done       <= 1'b0;
            O_ae_cfg_done    <= 1'b0;
            O_sensor_id      <= 16'd0;
            O_sensor_id_ok   <= 1'b0;
            O_iic_error      <= 1'b0;
        end else begin
            snapshot_ack_sync <= {snapshot_ack_sync[0], I_applied_snapshot_ack};
            if (I_ae_req) ae_req_pending <= 1'b1;
            if (ae_table_active && iic_bus_error) ae_transaction_error <= 1'b1;
            if (iic_bus_error)
                O_iic_error <= 1'b1;

            case (state)
                ST_IDH_REQ: if (!iic_busy) begin
                    wr_data <= {8'h00, 8'h07, 8'h31, CAM_ID};
                    wr_cnt <= 8'd3;
                    rd_cnt <= 8'd1;
                    iic_mode <= 1'b1;
                    iic_req <= 1'b1;
                    state <= ST_IDH_BUSY;
                end
                ST_IDH_BUSY: if (iic_busy) begin
                    iic_req <= 1'b0;
                    state <= ST_IDH_DONE;
                end
                ST_IDH_DONE: if (!iic_busy) begin
                    O_sensor_id[15:8] <= rd_data;
                    state <= ST_IDL_REQ;
                end
                ST_IDL_REQ: if (!iic_busy) begin
                    wr_data <= {8'h00, 8'h08, 8'h31, CAM_ID};
                    wr_cnt <= 8'd3;
                    rd_cnt <= 8'd1;
                    iic_mode <= 1'b1;
                    iic_req <= 1'b1;
                    state <= ST_IDL_BUSY;
                end
                ST_IDL_BUSY: if (iic_busy) begin
                    iic_req <= 1'b0;
                    state <= ST_IDL_DONE;
                end
                ST_IDL_DONE: if (!iic_busy) begin
                    O_sensor_id[7:0] <= rd_data;
                    state <= ST_CHECK_ID;
                end
                ST_CHECK_ID: begin
                    if ((O_sensor_id == 16'hee4b) ||
                        (O_sensor_id == 16'h9e4b)) begin
                        O_sensor_id_ok <= 1'b1;
                        reg_index <= 9'd0;
                        ae_table_active <= 1'b0;
                        state <= ST_IDLE;
                    end else begin
                        state <= ST_ERROR;
                    end
                end
                ST_IDLE: begin
                    if (!O_cfg_done) begin
                        if (reg_index == init_reg_size) begin
                            O_cfg_done <= 1'b1;
                            O_ae_cfg_done <= 1'b1;
                        end else begin
                            state <= ST_WR_REQ;
                        end
                    end else if (ae_table_active) begin
                        if (reg_index == ae_reg_size) begin
                            ae_table_active <= 1'b0;
                            O_ae_cfg_done <= 1'b1;
                            if (ae_transaction_error || iic_bus_error) begin
                                O_applied_status_mailbox <= APPLIED_ERROR;
                            end else begin
                                O_applied_exposure_mailbox <= I_ae;
                                O_applied_gain_regs_mailbox <= gain_value;
                                O_applied_has_value_mailbox <= 1'b1;
                                O_applied_status_mailbox <= APPLIED_OK;
                            end
                            O_applied_snapshot_req <= ~O_applied_snapshot_req;
                        end else begin
                            state <= ST_WR_REQ;
                        end
                    end else if (I_ae_req || ae_req_pending) begin
                        if (!snapshot_pending) begin
                            ae_req_pending <= 1'b0;
                            ae_table_active <= 1'b1;
                            ae_transaction_error <= 1'b0;
                            O_ae_cfg_done <= 1'b0;
                            reg_index <= 9'd0;
                            O_applied_status_mailbox <= APPLIED_WRITING;
                            O_applied_snapshot_req <= ~O_applied_snapshot_req;
                            state <= ST_WAIT_SNAPSHOT_ACK;
                        end else begin
                            ae_req_pending <= 1'b1;
                        end
                    end
                end
                ST_WAIT_SNAPSHOT_ACK: if (!snapshot_pending) begin
                    state <= ST_WR_REQ;
                end
                ST_WR_REQ: if (!iic_busy) begin
                    wr_data[7:0]   <= CAM_ID;
                    wr_data[15:8]  <= selected_reg_data[23:16];
                    wr_data[23:16] <= selected_reg_data[15:8];
                    wr_data[31:24] <= selected_reg_data[7:0];
                    wr_cnt <= 8'd4;
                    rd_cnt <= 8'd0;
                    iic_mode <= 1'b0;
                    iic_req <= 1'b1;
                    state <= ST_WR_BUSY;
                end
                ST_WR_BUSY: if (iic_busy) begin
                    iic_req <= 1'b0;
                    state <= ST_WR_DONE;
                end
                ST_WR_DONE: if (!iic_busy) begin
                    reg_index <= reg_index + 1'b1;
                    if (!ae_table_active && (reg_index == 9'd0)) begin
                        reset_wait_cnt <= 17'd0;
                        state <= ST_RESET_WAIT;
                    end else begin
                        state <= ST_IDLE;
                    end
                end
                ST_RESET_WAIT: begin
                    if (reset_wait_cnt == RESET_WAIT_CYCLES - 1) begin
                        state <= ST_IDLE;
                    end else begin
                        reset_wait_cnt <= reset_wait_cnt + 1'b1;
                    end
                end
                ST_ERROR: begin
                    iic_req <= 1'b0;
                    O_cfg_done <= 1'b0;
                    O_ae_cfg_done <= 1'b0;
                end
                default: state <= ST_ERROR;
            endcase
        end
    end

    hx_sc520_i2c_ce #(
        .WMEN_LEN(4),
        .RMEN_LEN(1),
        .CLK_DIV(CLK_DIV)
    ) u_i2c (
        .I_clk(I_clk),
        .I_rstn(I_rst_n),
        .O_iic_scl(O_cam_scl),
        .IO_iic_sda(IO_cam_sda),
        .I_wr_data(wr_data),
        .I_wr_cnt(wr_cnt),
        .O_rd_data(rd_data),
        .I_rd_cnt(rd_cnt),
        .I_iic_req(iic_req),
        .I_iic_mode(iic_mode),
        .O_iic_busy(iic_busy),
        .O_iic_bus_error(iic_bus_error),
        .IO_iic_sda_dg()
    );

    // SC520CS true 1280x720@60 mode.  This test keeps the factory 0x89 table
    // but clears register 0x3222 to verify Free-run operation.
    uics520reg_720p60 u_init_regs (
        .REG_INDEX(reg_index),
        .REG_DATA(init_reg_data),
        .REG_SIZE(init_reg_size)
    );

    SC520GainTbl u_gain (
        .I_AG(I_ag),
        .O(gain_value)
    );

    uics520regAE u_ae_regs (
        .REG_INDEX(reg_index),
        .REG_DATA(ae_reg_data),
        .REG_SIZE(ae_reg_size),
        .I_AE(I_ae),
        .I_AG(gain_value)
    );
endmodule

// SC520-only replacement for the legacy fabric-clock I2C controller.
// Every register uses I_clk. Divider phase is data, never a clock. The wire
// period remains 2*(floor(CLK_DIV/2)+1) source clocks and retains OFFSET.
// Request/data must remain stable until busy is observed, as in uii2c.
module hx_sc520_i2c_ce #(
    parameter integer WMEN_LEN=4,
    parameter integer RMEN_LEN=1,
    parameter integer CLK_DIV=237
) (
    input wire I_clk, I_rstn,
    output reg O_iic_scl=1'b1,
    inout wire IO_iic_sda,
    input wire [WMEN_LEN*8-1:0] I_wr_data,
    input wire [7:0] I_wr_cnt,
    output reg [RMEN_LEN*8-1:0] O_rd_data=0,
    input wire [7:0] I_rd_cnt,
    input wire I_iic_req, I_iic_mode,
    output reg O_iic_busy=0,
    output reg O_iic_bus_error=0,
    output wire IO_iic_sda_dg
);
    localparam integer HALF=CLK_DIV/2;
    localparam integer OFFSET=HALF-HALF/4;
    localparam [2:0] IDLE=0, START=1, W_WAIT=2, W_ACK=3,
                     R_WAIT=4, R_ACK=5, STOP1=6, STOP2=7;
    reg [15:0] divider=0;
    reg phase=0;
    reg [2:0] state=IDLE, bit_count=0;
    reg [7:0] write_count=0, read_count=0;
    reg read_request=0;
    reg [7:0] tx_shift=8'hff, rx_shift=0;
    (* async_reg="true" *) reg [1:0] sda_sync=2'b11;
    wire rise_ce=(divider==HALF) && !phase;
    wire fall_ce=(divider==HALF) && phase;
    wire scl_value=(state==IDLE || state==STOP1 || state==STOP2) ? 1'b1 : phase;
    wire sda_value=(state==START || state==STOP1 ||
                   (state==R_ACK && read_count!=I_rd_cnt)) ? 1'b0 :
                   (state==W_WAIT ? tx_shift[7] : 1'b1);
    assign IO_iic_sda=sda_value ? 1'bz : 1'b0;
    assign IO_iic_sda_dg=sda_sync[1];

    always @(posedge I_clk or negedge I_rstn) begin
        if(!I_rstn) begin
            divider<=0; phase<=0; state<=IDLE; bit_count<=0;
            write_count<=0; read_count<=0; read_request<=0;
            tx_shift<=8'hff; rx_shift<=0; O_rd_data<=0;
            O_iic_scl<=1; O_iic_busy<=0; O_iic_bus_error<=0;
            sda_sync<=2'b11;
        end else begin
            sda_sync<={sda_sync[0],IO_iic_sda};
            if(divider==HALF) begin divider<=0; phase<=!phase; end
            else divider<=divider+1'b1;
            if(divider==OFFSET) O_iic_scl<=scl_value;

            if(fall_ce) begin
                if(state==R_WAIT) rx_shift<={rx_shift[6:0],sda_sync[1]};
                else if(state==R_ACK) O_rd_data[(read_count-1'b1)*8 +: 8]<=rx_shift;
                else if(state==IDLE) rx_shift<=0;
                if(state==W_ACK && sda_sync[1]) O_iic_bus_error<=1;
                else if(!I_iic_req) O_iic_bus_error<=0;
            end

            if(rise_ce) begin
                if(state==W_ACK || state==START) begin
                    tx_shift<=I_wr_data[write_count*8 +: 8];
                    if(read_request) tx_shift<={I_wr_data[7:1],1'b1};
                end else if(state==W_WAIT) tx_shift<={tx_shift[6:0],1'b1};
                if(I_iic_req || read_request || O_iic_bus_error) O_iic_busy<=1;
                else if(state==IDLE) O_iic_busy<=0;
                case(state)
                    IDLE: if(I_iic_req || read_request) state<=START;
                          else begin write_count<=0; read_count<=0; end
                    START: begin bit_count<=7; state<=W_WAIT; end
                    W_WAIT: if(bit_count!=0) bit_count<=bit_count-1'b1;
                            else begin write_count<=write_count+1'b1; state<=W_ACK; end
                    W_ACK: begin
                        if(write_count<I_wr_cnt) begin bit_count<=7; state<=W_WAIT; end
                        else if(I_rd_cnt!=0) begin
                            if(!read_request && I_iic_mode) begin
                                read_request<=1; state<=IDLE;
                            end else state<=R_WAIT;
                            bit_count<=7;
                        end else state<=STOP1;
                    end
                    R_WAIT: begin
                        read_request<=0; bit_count<=bit_count-1'b1;
                        if(bit_count==0) begin
                            if(read_count<I_rd_cnt) read_count<=read_count+1'b1;
                            state<=R_ACK;
                        end
                    end
                    R_ACK: begin bit_count<=7; state<=(read_count<I_rd_cnt) ? R_WAIT : STOP1; end
                    STOP1: begin read_request<=0; state<=STOP2; end
                    STOP2: state<=IDLE;
                    default: state<=IDLE;
                endcase
            end
        end
    end
endmodule

