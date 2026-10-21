`timescale 1ns/1ps
module tb_uics520_applied_status;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0;
    reg ae_req=0;
    reg [15:0] ae=16'd1200;
    reg [15:0] ag=16'd48;
    reg snapshot_ack=0;
    reg fake_busy=0, fake_error=0;
    tri1 sda;
    wire scl, cfg_done, ae_done, sensor_ok, iic_error, snapshot_req;
    wire [15:0] sensor_id, applied_ae;
    wire [23:0] applied_gain;
    wire [1:0] applied_status;
    wire applied_has_value;

    uicfgcs520 #(.CLK_DIV(8)) dut (
        .I_clk(clk), .I_rst_n(rst_n), .I_ae_req(ae_req), .I_ae(ae), .I_ag(ag),
        .O_cam_scl(scl), .IO_cam_sda(sda), .O_cfg_done(cfg_done), .O_ae_cfg_done(ae_done),
        .O_sensor_id(sensor_id), .O_sensor_id_ok(sensor_ok), .O_iic_error(iic_error),
        .I_applied_snapshot_ack(snapshot_ack), .O_applied_snapshot_req(snapshot_req),
        .O_applied_exposure_mailbox(applied_ae), .O_applied_gain_regs_mailbox(applied_gain),
        .O_applied_status_mailbox(applied_status), .O_applied_has_value_mailbox(applied_has_value)
    );

    task acknowledge_snapshot;
        begin
            wait(snapshot_req != snapshot_ack);
            @(negedge clk); snapshot_ack=snapshot_req;
            repeat(4) @(posedge clk);
        end
    endtask

    task fake_sensor_write(input integer fail_ack);
        begin
            wait(dut.state==4'd8); // ST_WR_REQ
            @(posedge clk); #1; // request becomes busy
            @(negedge clk); fake_busy=1; fake_error=fail_ack!=0;
            @(posedge clk); #1; // ST_WR_BUSY observes an active transaction
            @(negedge clk); fake_busy=0; fake_error=0;
            @(posedge clk); #1; // ST_WR_DONE advances register index
        end
    endtask

    task complete_ae_table(input integer error_index);
        integer n;
        begin
            for(n=0;n<8;n=n+1) fake_sensor_write((n==error_index));
            wait(dut.state==4'd7 && dut.reg_index==8); // ST_IDLE, all 8 table entries returned
            @(posedge clk); #1; // completion status is published only after final write
        end
    endtask

    task request_ae(input integer error_index);
        begin
            @(negedge clk); ae_req=1;
            @(negedge clk); ae_req=0;
            acknowledge_snapshot(); // WRITING status
            complete_ae_table(error_index);
            acknowledge_snapshot(); // final success/error snapshot
        end
    endtask

    initial begin
        repeat(4) @(posedge clk); rst_n=1; repeat(3) @(posedge clk);
        // This test bypasses the long power-up/init table and emulates only the
        // controller's busy/ACK observations. It does not drive a physical sensor.
        dut.state=4'd7; dut.O_cfg_done=1'b1; dut.O_ae_cfg_done=1'b1;
        dut.ae_table_active=1'b0; dut.ae_req_pending=1'b0; dut.reg_index=0;
        force dut.iic_busy=fake_busy;
        force dut.iic_bus_error=fake_error;

        request_ae(-1);
        if(applied_status!==2'd2 || !applied_has_value || applied_ae!==16'd1200 || applied_gain!==24'h080080 || !ae_done)
            $fatal(1,"Successful completion did not publish confirmed SC520 values: status=%0d valid=%b E=%0d G=%h",applied_status,applied_has_value,applied_ae,applied_gain);

        ae=16'd600; ag=16'd16;
        request_ae(3);
        if(applied_status!==2'd3 || !applied_has_value || applied_ae!==16'd1200 || applied_gain!==24'h080080) begin
            $display("DEBUG status=%0d has=%b E=%0d G=%h ae_done=%b txn_err=%b reg=%0d",applied_status,applied_has_value,applied_ae,applied_gain,ae_done,dut.ae_transaction_error,dut.reg_index);
            $fatal(1,"I2C error published an unconfirmed request or lost last good snapshot");
        end

        release dut.iic_busy;
        release dut.iic_bus_error;
        $display("PASS SC520 applied status: output waits through write table, reports completed values, and preserves last confirmed values on NACK");
        $finish;
    end
    initial begin #2000000; $fatal(1,"Timeout"); end
endmodule
