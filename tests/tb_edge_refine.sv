`timescale 1ns/1ps
module tb_edge_refine #(
    parameter VECTOR_DIR = "D:/Downloads/qiansai/tmp/edge_refine_vectors_20261017_a",
    parameter W = 96, H = 80
);
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 0, de = 0, edge_in = 0;
    reg [10:0] x = 0, y = 0;
    wire out_de, out_edge;
    wire [10:0] out_x;
    hx_edge_binary_refine #(.IMAGE_WIDTH(W)) dut (
        .I_clk(clk), .I_rst_n(rst), .I_de(de), .I_x(x), .I_y(y), .I_edge(edge_in),
        .O_de(out_de), .O_x(out_x), .O_edge(out_edge)
    );
    reg [1:0] vectors [0:W*H-1];
    reg expected_in = 0;
    reg expected_de [0:1];
    reg expected_edge [0:1];
    reg [10:0] expected_x [0:1];
    integer i, j, frame_id, k, count = 0;
    string filename;
    always @(posedge clk) begin
        if (!rst) begin
            for (k=0; k<2; k=k+1) begin
                expected_de[k] = 0; expected_edge[k] = 0; expected_x[k] = 0;
            end
        end else begin
            expected_de[1] = expected_de[0];
            expected_edge[1] = expected_edge[0];
            expected_x[1] = expected_x[0];
            expected_de[0] = de && x < W;
            expected_edge[0] = expected_in;
            expected_x[0] = x;
            #1;
            if (out_de !== expected_de[1]) $fatal(1, "DE mismatch at frame=%0d x=%0d y=%0d", frame_id, x, y);
            if (out_de) begin
                if (out_edge !== expected_edge[1] || out_x !== expected_x[1]) begin
                    $display("clean (%0d,%0d)=%b window %b/%b/%b/%b/%b line=%b", dut.clean_x, dut.clean_y, dut.clean_edge,
                        dut.u_clean.w0, dut.u_clean.w1, dut.u_clean.w2, dut.u_clean.w3, dut.u_clean.w4, dut.u_clean.line_rd);
                    $display("bridge (%0d,%0d) window %b/%b/%b/%b/%b", dut.u_bridge.O_x, dut.u_bridge.O_y,
                        dut.u_bridge.w0, dut.u_bridge.w1, dut.u_bridge.w2, dut.u_bridge.w3, dut.u_bridge.w4);
                    $fatal(1, "Pixel mismatch frame=%0d input=(%0d,%0d) got=%b expected=%b out_x=%0d expected_x=%0d",
                           frame_id, x, y, out_edge, expected_edge[1], out_x, expected_x[1]);
                end
                count = count + 1;
            end
        end
    end
    task drive;
        input integer xx, yy;
        input bit valid, pixel_in, pixel_expected;
        begin
            // Address must be stable BEFORE the ERAM falling-edge pre-read.
            @(posedge clk); #2;
            x = xx; y = yy; de = valid; edge_in = pixel_in; expected_in = pixel_expected;
        end
    endtask
    initial begin
        repeat (4) @(negedge clk);
        #1; rst = 1;
        for (frame_id=0; frame_id<4; frame_id=frame_id+1) begin
            filename = $sformatf("%s/edge_%0d.mem", VECTOR_DIR, frame_id);
            $readmemh(filename, vectors);
            for (j=0; j<H; j=j+1) begin
                for (i=0; i<W; i=i+1) begin
                    // Exercise legal midline DE bubbles as well as continuous rows.
                    if (frame_id == 1 && i % 13 == 6) drive(i, j, 0, 1, 0);
                    drive(i, j, 1, vectors[j*W+i][1], vectors[j*W+i][0]);
                end
                if (frame_id != 2) begin
                    drive(W, j, 0, 1, 0);
                    drive(W+1, j, 1, 1, 0); // invalid address must not write/advance
                    drive(W+2, j, 0, 0, 0);
                end
            end
            if (frame_id == 0) begin
                drive(0, 0, 0, 0, 0);
                drive(0, 0, 0, 0, 0);
                @(negedge clk); #1; rst = 0;
                repeat (3) @(negedge clk);
                #1; rst = 1;
            end
        end
        repeat (5) drive(0, 0, 0, 0, 0);
        if (count != 4*W*H) $fatal(1, "Output count %0d expected %0d", count, 4*W*H);
        $display("PASS edge refinement: %0d pixels, four maps, DE gaps, invalid addresses, reset and consecutive frames", count);
        $finish;
    end
    initial begin #100000000; $fatal(1, "Timeout"); end
endmodule
