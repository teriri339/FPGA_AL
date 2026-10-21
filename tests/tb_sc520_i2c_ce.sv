`timescale 1ns/1ps
module hx_test_i2c_slave #(parameter [7:0] READ_VALUE=8'ha5)(
    input wire rst_n, scl, input integer nack_index, inout wire sda,
    output integer byte_count=0, output integer starts=0, stops=0
);
    reg pull_low=0, active=0, reading=0, addr_phase=1, pending_read=0;
    integer bits=0;
    reg [7:0] shift=0;
    reg [7:0] bytes[0:31];
    assign sda=pull_low ? 1'b0 : 1'bz;
    always @(negedge rst_n) begin
        active=0; reading=0; addr_phase=1; pending_read=0;
        bits=0; shift=0; pull_low=0; byte_count=0; starts=0; stops=0;
    end
    always @(negedge sda) if(rst_n && scl===1'b1) begin
        active=1; reading=0; pending_read=0; addr_phase=1;
        bits=0; shift=0; starts=starts+1;
    end
    always @(posedge sda) if(rst_n && scl===1'b1 && active) begin
        active=0; reading=0; pull_low=0; stops=stops+1;
    end
    always @(posedge scl) if(rst_n && active) begin
        if(bits<8) begin
            if(!reading) shift={shift[6:0],sda};
            bits=bits+1;
            if(bits==8 && !reading) begin
                if(byte_count>=32) $fatal(1,"Slave log overflow");
                bytes[byte_count]=shift; byte_count=byte_count+1;
                if(addr_phase) begin pending_read=shift[0]; addr_phase=0; end
            end
        end else begin
            bits=0;
            if(pending_read) begin reading=1; pending_read=0; end
            else if(reading && sda===1'b1) reading=0; // Master NACK ends read.
        end
    end
    always @(negedge scl) if(rst_n && active) begin
        if(bits==8) pull_low=!reading && (nack_index!=byte_count-1);
        else if(reading) pull_low=!READ_VALUE[7-bits];
        else pull_low=0;
    end
endmodule

module tb_sc520_i2c_ce;
    parameter integer DIV=237;
    reg clk=0; always #21 clk=~clk;
    reg rst_n=0, req=0;
    reg [31:0] wr_data=32'h00073160;
    reg [7:0] wr_count=3, rd_count=0;
    integer nack_index=-1;
    wire scl_ce, scl_ref, busy_ce, busy_ref, err_ce, err_ref;
    wire [7:0] rd_ce, rd_ref;
    tri1 sda_ce, sda_ref;
    wire [31:0] bytes_ce, bytes_ref, starts_ce, starts_ref, stops_ce, stops_ref;
    reg seen_error_ce=0, seen_error_ref=0;
    integer cases=0, k;
    integer period_checks=0;
    time last_rise=0;
    reg last_data_edge=0;
    hx_sc520_i2c_ce #(.CLK_DIV(DIV)) dut(
        .I_clk(clk),.I_rstn(rst_n),.O_iic_scl(scl_ce),.IO_iic_sda(sda_ce),
        .I_wr_data(wr_data),.I_wr_cnt(wr_count),.O_rd_data(rd_ce),.I_rd_cnt(rd_count),
        .I_iic_req(req),.I_iic_mode(1'b1),.O_iic_busy(busy_ce),
        .O_iic_bus_error(err_ce),.IO_iic_sda_dg());
    uii2c #(.WMEN_LEN(4),.RMEN_LEN(1),.CLK_DIV(DIV)) legacy(
        .I_clk(clk),.I_rstn(rst_n),.O_iic_scl(scl_ref),.IO_iic_sda(sda_ref),
        .I_wr_data(wr_data),.I_wr_cnt(wr_count),.O_rd_data(rd_ref),.I_rd_cnt(rd_count),
        .I_iic_req(req),.I_iic_mode(1'b1),.O_iic_busy(busy_ref),
        .O_iic_bus_error(err_ref),.IO_iic_sda_dg());
    hx_test_i2c_slave slave_ce(rst_n,scl_ce,nack_index,sda_ce,bytes_ce,starts_ce,stops_ce);
    hx_test_i2c_slave slave_ref(rst_n,scl_ref,nack_index,sda_ref,bytes_ref,starts_ref,stops_ref);
    always @(posedge clk) if(rst_n) begin
        if(err_ce) seen_error_ce<=1;
        if(err_ref) seen_error_ref<=1;
    end
    always @(negedge rst_n) begin last_data_edge=0; last_rise=0; end
    always @(posedge scl_ce) if(rst_n) begin
        if(dut.state==2 || dut.state==4) begin
            if(last_data_edge) begin
                if(($time-last_rise)!==42*(2*(DIV/2+1)))
                    $fatal(1,"I2C SCL wire period changed: got %0t expected %0d ns",$time-last_rise,42*(2*(DIV/2+1)));
                period_checks=period_checks+1;
            end
            last_data_edge=1; last_rise=$time;
        end else last_data_edge=0;
    end
    task reset_bus;
        begin
            @(negedge clk); rst_n=0; req=0;
            repeat(DIV*3+10) @(negedge clk);
            seen_error_ce=0; seen_error_ref=0;
            rst_n=1;
            repeat(DIV*3+10) @(negedge clk);
        end
    endtask
    task transfer(input bit read_en, input integer nack_byte);
        begin
            rd_count=read_en ? 1 : 0; nack_index=nack_byte;
            reset_bus();
            @(negedge clk); req=1;
            wait(busy_ce && busy_ref);
            @(negedge clk); req=0;
            wait(!busy_ce && !busy_ref);
            repeat(DIV*2+10) @(negedge clk);
            if(bytes_ce!==(read_en ? 4 : 3) || bytes_ce!==bytes_ref)
                $fatal(1,"Byte count CE=%0d reference=%0d",bytes_ce,bytes_ref);
            for(k=0;k<bytes_ce;k=k+1)
                if(slave_ce.bytes[k]!==slave_ref.bytes[k])
                    $fatal(1,"Wire byte %0d CE=%h reference=%h",k,slave_ce.bytes[k],slave_ref.bytes[k]);
            if(slave_ce.bytes[0]!==8'h60 || slave_ce.bytes[1]!==8'h31 || slave_ce.bytes[2]!==8'h07)
                $fatal(1,"Wire write order changed");
            if(starts_ce!==(read_en ? 2 : 1) || starts_ce!==starts_ref || stops_ce!==1 || stops_ref!==1)
                $fatal(1,"START/repeated START/STOP mismatch CE=%0d/%0d ref=%0d/%0d",starts_ce,stops_ce,starts_ref,stops_ref);
            if(read_en && (rd_ce!==8'ha5 || rd_ce!==rd_ref || slave_ce.bytes[3]!==8'h61))
                $fatal(1,"Repeated START read mismatch CE=%h reference=%h",rd_ce,rd_ref);
            if(seen_error_ce!==(nack_byte>=0) || seen_error_ce!==seen_error_ref)
                $fatal(1,"ACK/NACK status mismatch CE=%b ref=%b",seen_error_ce,seen_error_ref);
            cases=cases+1;
        end
    endtask
    initial begin
        transfer(0,-1);
        transfer(0,0);
        transfer(0,1);
        transfer(0,2);
        transfer(1,-1);
        // Abort a real on-wire transfer, then ensure the next write recovers.
        reset_bus(); @(negedge clk); rd_count=0; req=1;
        wait(busy_ce && busy_ref);
        repeat(DIV*5) @(negedge clk);
        transfer(0,-1);
        if(period_checks<10) $fatal(1,"Too few SCL period checks");
        $display("PASS SC520 I2C CE: DIV=%0d, %0d real bus transactions, %0d wire period checks, write byte order, address/data ACK/NACK, repeated START read and reset recovery match legacy",DIV,cases,period_checks);
        $finish;
    end
    initial begin #10000000; $fatal(1,"I2C bus test timeout CE state=%0d reference=%0d",dut.state,legacy.IIC_S); end
endmodule
