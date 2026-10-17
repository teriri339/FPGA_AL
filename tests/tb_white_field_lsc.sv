`timescale 1ns/1ps
module tb_white_field_lsc #(parameter GAIN_FILE="");
    reg clk=0;
    always #5 clk=~clk;
    reg rst=0, vs=0, hs=0, de=0, user=0, last=0;
    reg [23:0] rgb=0;
    wire ovs, ohs, ode, ouser, olast;
    wire [23:0] out_rgb;
    wire bvs,bhs,bde,buser,blast;
    wire [23:0] bypass_rgb;
    // Small frame exercises every endpoint, ascending and descending interpolation.
    hx_white_field_lsc #(.IMAGE_WIDTH(19),.IMAGE_HEIGHT(11),
        .BLACK_LEVEL(10),.GAIN_FILE(GAIN_FILE)) dut (
        .I_clk(clk),.I_rst_n(rst),.I_vsync(vs),.I_hsync(hs),.I_de(de),
        .I_user(user),.I_last(last),.I_rgb(rgb),
        .I_gain_we(1'b0),.I_gain_addr(8'd0),.I_gain_data(36'd0),.I_correction_enable(1'b1),
        .O_vsync(ovs),.O_hsync(ohs),.O_de(ode),.O_user(ouser),
        .O_last(olast),.O_rgb(out_rgb));
    hx_pixel_stream_adapter bypass (
        .I_clk(clk),.I_rst_n(rst),.I_vsync(vs),.I_hsync(hs),.I_de(de),
        .I_user(user),.I_last(last),.I_rgb(rgb),
        .I_calibrate(1'b0),.I_invalidate_calibration(1'b0),.O_cal_busy(),.O_cal_valid(),.O_cal_error(),
        .O_vsync(bvs),.O_hsync(bhs),.O_de(bde),.O_user(buser),
        .O_last(blast),.O_rgb(bypass_rgb));
    reg [4:0] expected_ctrl[0:5];
    reg [23:0] expected_rgb[0:5];
    integer frame_no=0, sx=0, sy=0, count=0, k, i, r,g,b;
    integer ux,uy,nx,ny,fx,fy,a00,a10,a01,a11,t0,t1,gain,p;
    reg [23:0] expected;
    function integer mix;
        input integer a,b,f;
        begin mix=(a*256+(b-a)*f+128) >>> 8; end
    endfunction
    function integer node;
        input integer channel,xx,yy,frame_id;
        begin
            case(frame_id)
            0: node=256;
            1: case(channel)
                0: node=128+xx*12+yy*4;
                1: node=500-xx*9-yy*11;
                2: node=128+xx*5+yy*18;
               endcase
            2: node=1024;
            default: node=(channel*757+xx*1511+yy*911)%4096;
            endcase
        end
    endfunction
    // Independent integer reference and a six-stage control/pixel scoreboard.
    always @(posedge clk) begin
        if (!rst) begin
            sx=0;sy=0;
            for(k=0;k<6;k=k+1) begin expected_ctrl[k]=0;expected_rgb[k]=0;end
        end else begin
            for(k=5;k>0;k=k-1) begin
                expected_ctrl[k]=expected_ctrl[k-1];expected_rgb[k]=expected_rgb[k-1];
            end
            if(user) begin sx=0;sy=0;end
            expected=0;
            if(de) begin
                ux=sx*15*256/18;uy=sy*8*256/10;
                nx=ux/256;ny=uy/256;fx=ux%256;fy=uy%256;
                if(nx==15) begin nx=14;fx=256;end
                if(ny==8) begin ny=7;fy=256;end
                for(i=0;i<3;i=i+1) begin
                    a00=node(i,nx,ny,frame_no);a10=node(i,nx+1,ny,frame_no);
                    a01=node(i,nx,ny+1,frame_no);a11=node(i,nx+1,ny+1,frame_no);
                    t0=mix(a00,a10,fx);t1=mix(a01,a11,fx);gain=mix(t0,t1,fy);
                    p=rgb[(2-i)*8+:8]; p=(p>10)?p-10:0;
                    p=(p*gain+128)/256; if(p>255)p=255;
                    expected[(2-i)*8+:8]=p;
                end
                if(sx==18) begin sx=0;sy=(sy==10)?0:sy+1;end else sx=sx+1;
                count=count+1;
            end
            expected_ctrl[0]={vs,hs,de,user,last};expected_rgb[0]=expected;
        end
        #1;
        if({ovs,ohs,ode,ouser,olast} !== expected_ctrl[5] || out_rgb !== expected_rgb[5])
            $fatal(1,"Mismatch frame=%0d count=%0d rgb=%h expected=%h ctrl=%b/%b",
                frame_no,count,out_rgb,expected_rgb[5],{ovs,ohs,ode,ouser,olast},expected_ctrl[5]);
        if({bvs,bhs,bde,buser,blast,bypass_rgb} !== {vs,hs,de,user,last,rgb})
            $fatal(1,"Bypass changed stream");
    end
    integer f,x,y,j;
    task blank;
        begin @(negedge clk);de=0;user=0;last=0;hs=1;rgb=24'hfedcba;end
    endtask
    initial begin
        repeat(3) @(negedge clk);rst=1;
        for(f=0;f<4;f=f+1) begin
            repeat(7) blank();
            frame_no=f;
            if(f!=0 || GAIN_FILE=="")
                for(j=0;j<144;j=j+1)
                    dut.gains[j]={12'(node(0,j%16,j/16,f)),12'(node(1,j%16,j/16,f)),12'(node(2,j%16,j/16,f))};
            for(y=0;y<11;y=y+1) begin
                for(x=0;x<19;x=x+1) begin
                    // DE holes ensure coordinates follow valid pixels, not clocks.
                    if(x==7) blank();
                    @(negedge clk);de=1;user=(x==0 && y==0);last=(x==18);hs=0;vs=0;
                    rgb={(8'(x*13)),(8'(y*25)),(8'((x+y)*19))};
                end
                repeat(3) blank();
            end
        end
        repeat(8) blank();
        // Check reset output state after the frame sequence.
        @(negedge clk);rst=0;
        repeat(3) @(negedge clk);
        if(count!=836) $fatal(1,"Missing pixels: %0d",count);
        $display("PASS: 836 pixels, 4 LUTs including full 12-bit range, black clamp, saturation, borders, DE gaps, timing and bypass");
        $finish;
    end
endmodule
