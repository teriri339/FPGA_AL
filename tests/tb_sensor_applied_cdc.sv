`timescale 1ns/1ps
module tb_sensor_applied_cdc;
    reg src_running=1, dst_running=1;
    reg src_clk=0; always #21 if(src_running) src_clk=~src_clk; else src_clk=0;
    reg dst_clk=0; always #7 if(dst_running) dst_clk=~dst_clk; else dst_clk=0;
    reg src_rst_n=0;
    reg dst_rst_n=0;
    reg req=0;
    reg [15:0] src_exp=0;
    reg [23:0] src_gain=0;
    reg [1:0] src_status=0;
    reg src_valid=0;
    wire ack;
    wire [15:0] dst_exp;
    wire [23:0] dst_gain;
    wire [1:0] dst_status;
    wire dst_valid, update_toggle;
    reg [1:0] ack_sync=0;
    integer updates=0;
    reg last_toggle=0;

    hx_sensor_applied_cdc dut (
        .src_req_toggle(req), .src_exposure(src_exp), .src_gain_regs(src_gain),
        .src_status(src_status), .src_has_value(src_valid), .dst_clk(dst_clk), .dst_rst_n(dst_rst_n),
        .src_ack_toggle(ack), .dst_exposure(dst_exp), .dst_gain_regs(dst_gain),
        .dst_status(dst_status), .dst_has_value(dst_valid), .dst_update_toggle(update_toggle)
    );

    always @(posedge src_clk or negedge src_rst_n)
        if(!src_rst_n) ack_sync <= 0;
        else ack_sync <= {ack_sync[0],ack};
    always @(posedge dst_clk) begin
        #1;
        if(!dst_rst_n) last_toggle=0;
        else if(update_toggle!=last_toggle) begin
            last_toggle=update_toggle;
            updates=updates+1;
        end
    end

    task send_snapshot(input [15:0] e, input [23:0] g, input [1:0] st, input v);
        begin
            @(negedge src_clk);
            src_exp=e; src_gain=g; src_status=st; src_valid=v;
            req=~req;
            wait(ack_sync[1]==req);
            repeat(2) @(posedge dst_clk);
            #2;
            if(dst_exp!==e || dst_gain!==g || dst_status!==st || dst_valid!==v)
                $fatal(1,"CDC mailbox tore payload: got %h/%h/%d/%b expected %h/%h/%d/%b",dst_exp,dst_gain,dst_status,dst_valid,e,g,st,v);
        end
    endtask

    // The actual top level asserts both sides from the same global reset.
    // Source release is delayed by camera power-up; independent unilateral
    // resets are not a supported contract for this two-phase mailbox.
    task common_reset(input integer src_release_delay);
        begin
            @(negedge dst_clk);
            dst_rst_n=0; src_rst_n=0; req=0;
            src_exp=0; src_gain=0; src_status=0; src_valid=0;
            repeat(5) @(negedge dst_clk);
            dst_rst_n=1;
            repeat(src_release_delay) @(negedge src_clk);
            src_rst_n=1;
            repeat(3) @(negedge src_clk);
            if(ack!==0 || dst_valid!==0 || dst_exp!==0)
                $fatal(1,"Common reset did not clear mailbox");
        end
    endtask

    integer phase;
    integer before_stall_updates;
    reg before_stall_ack;

    initial begin
        common_reset(4);
        send_snapshot(16'd1990,24'h0f0080,2'd1,1'b0);
        send_snapshot(16'd1200,24'h090080,2'd2,1'b1);
        send_snapshot(16'd1200,24'h090080,2'd3,1'b1);
        if(updates!=3) $fatal(1,"Expected 3 coherent mailbox updates, got %0d",updates);

        // Shift data/control launch relative to the destination clock.
        for(phase=0; phase<28; phase=phase+1) begin
            #(phase%14);
            send_snapshot(16'h8123 ^ (phase*37),24'habcdef ^ (phase*991),phase%4,phase%2);
        end

        // With the receiver stopped, request and payload remain pending and
        // no acknowledgment is invented. Restart must deliver exactly once.
        @(negedge dst_clk); dst_running=0;
        before_stall_updates=updates; before_stall_ack=ack;
        fork
            send_snapshot(16'hcafe,24'h123456,2'd2,1'b1);
            begin
                repeat(12) @(negedge src_clk);
                if(ack!==before_stall_ack || updates!=before_stall_updates)
                    $fatal(1,"Stopped receiver acknowledged a pending request");
                dst_running=1;
            end
        join
        if(updates!=before_stall_updates+1) $fatal(1,"Receiver restart duplicated/dropped payload");

        // Lose global lock/reset while a request is pending: both sides are
        // invalidated, then delayed source release must restart cleanly.
        @(negedge dst_clk); dst_running=0;
        @(negedge src_clk); req=~req; src_exp=16'hdead;
        repeat(2) @(negedge src_clk);
        dst_rst_n=0; src_rst_n=0; req=0;
        src_exp=0; src_gain=0; src_status=0; src_valid=0;
        dst_running=1;
        common_reset(7);
        send_snapshot(16'hbeef,24'h998877,2'd2,1'b1);
        common_reset(2);
        send_snapshot(16'h1200,24'h080080,2'd3,1'b1);
        $display("PASS sensor status CDC: baseline, 28 phase launches, receiver clock stall/restart and common in-flight reset with staggered release; no tearing");
        $finish;
    end
    initial begin #1000000; $fatal(1,"Timeout"); end
endmodule
