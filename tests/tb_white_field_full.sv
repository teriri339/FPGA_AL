`timescale 1ns/1ps
module tb_white_field_full #(parameter VECTOR_DIR="",BLACK_LEVEL=4,USE_PRESET=0);
    reg clk=0;
    always #5 clk=~clk;
    reg rst=0, vs=0, hs=0, de=0, user=0, last=0;
    reg [23:0] rgb=0, wanted=0;
    wire ovs,ohs,ode,ouser,olast;
    wire [23:0] result;
    reg [47:0] vectors[0:921599];
    reg [28:0] expected[0:5];
    integer n, x, y, f, k, checked=0;
    hx_pixel_stream_adapter #(.LSC_ENABLE(1),.LSC_BLACK_LEVEL(BLACK_LEVEL),.SOFT_PRESET(USE_PRESET),
        .LSC_GAIN_FILE(USE_PRESET ? "" : {VECTOR_DIR,"/verification.mem"})) dut (
        .I_clk(clk),.I_rst_n(rst),.I_vsync(vs),.I_hsync(hs),
        .I_de(de),.I_user(user),.I_last(last),.I_rgb(rgb),
        .I_calibrate(1'b0),.I_invalidate_calibration(1'b0),.O_cal_busy(),.O_cal_valid(),.O_cal_error(),
        .O_vsync(ovs),.O_hsync(ohs),.O_de(ode),.O_user(ouser),.O_last(olast),.O_rgb(result));
    always @(posedge clk) begin
        if(!rst) begin for(k=0;k<6;k=k+1)expected[k]=0;end
        else begin
            for(k=5;k>0;k=k-1)expected[k]=expected[k-1];
            expected[0]={vs,hs,de,user,last,de?wanted:24'd0};
        end
        #1;
        if({ovs,ohs,ode,ouser,olast,result} !== expected[5])
            $fatal(1,"Full frame mismatch after %0d checked pixels: got %h expected %h",
                checked,{ovs,ohs,ode,ouser,olast,result},expected[5]);
        if(ode) checked=checked+1;
    end
    task blank;
        begin @(negedge clk);de=0;user=0;last=0;hs=1;rgb=24'habcdef;wanted=0;end
    endtask
    task pixel;
        input integer index;
        begin
            @(negedge clk);de=1;user=(index==0);last=(index%1280==1279);hs=0;vs=0;
            rgb=vectors[index][47:24];wanted=vectors[index][23:0];
        end
    endtask
    initial begin
        $readmemh({VECTOR_DIR,"/field_vectors.mem"},vectors);
        repeat(3) blank();rst=1;
        // Assert asynchronous reset while valid pixels are in flight.
        for(n=0;n<123;n=n+1)pixel(n);
        @(negedge clk);rst=0;de=0;user=0;last=0;
        #1;
        if({ovs,ohs,ode,ouser,olast,result} !== 29'd0) $fatal(1,"Async reset failed");
        repeat(3) blank();rst=1;
        for(f=0;f<2;f=f+1) begin
            if(f==1)$readmemh({VECTOR_DIR,"/scene_vectors.mem"},vectors);
            for(y=0;y<720;y=y+1) begin
                for(x=0;x<1280;x=x+1) begin
                    if(x==701 && y%31==0)blank();
                    pixel(y*1280+x);
                end
                repeat(8)blank();
            end
            vs=1;repeat(12)blank();vs=0;
        end
        repeat(8)blank();
        if(checked != 1843318) $fatal(1,"Wrong pixel count %0d",checked);
        $display("PASS: two 1280x720 frames, generated LUT, independent vectors, sharp scene, mid-stream reset, all timing flags (%0d pixels)",checked);
        $finish;
    end
endmodule
