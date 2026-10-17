`timescale 1ns/1ps
module tb_white_field_selfcal #(parameter WIDTH=320,HEIGHT=180,RUN_FAILURES=1);
    reg clk=0;always #5 clk=~clk;
    reg rst=0,de=0,user=0,last=0,vs=0,hs=0,request=0,invalidate=0;
    reg [23:0] rgb=0;
    wire busy,valid,error,ode,ouser,olast,ovs,ohs;
    wire [23:0] output_rgb;
    reg [35:0] expected_gains[0:143];
    reg [28:0] pipeline[0:5];
    reg [23:0] expected_rgb;
    integer input_x=0,input_y=0,writes=0,pixels=0;
    integer x,y,f,n,c,k,wx,wy,px,py,sr,sg,sb,mr,mg,mb,gr,gg,gb;
    integer ux,uy,nx,ny,fx,fy,t0,t1,gain,p;
    hx_pixel_stream_adapter #(.LSC_ENABLE(1),.SELF_CALIBRATION(1),
        .IMAGE_WIDTH(WIDTH),.IMAGE_HEIGHT(HEIGHT)) dut (
        .I_clk(clk),.I_rst_n(rst),.I_vsync(vs),.I_hsync(hs),.I_de(de),
        .I_user(user),.I_last(last),.I_rgb(rgb),.I_calibrate(request),
        .I_invalidate_calibration(invalidate),.O_cal_busy(busy),.O_cal_valid(valid),.O_cal_error(error),
        .O_vsync(ovs),.O_hsync(ohs),.O_de(ode),.O_user(ouser),.O_last(olast),.O_rgb(output_rgb));
    function integer value;
        input integer channel,xx,yy,kind;
        begin
            if(kind==1)value=12;
            else if(kind==2)value=255;
            else if(kind==3)value=(xx*17+yy*11+channel*61)%256;
            else case(channel)
                0:value=110+40*xx/(WIDTH-1);
                1:value=140+45*(xx<WIDTH/2 ? xx : WIDTH-1-xx)/(WIDTH/2);
                2:value=130+30*yy/(HEIGHT-1);
            endcase
        end
    endfunction
    function integer mix;
        input integer a,b,weight;
        begin mix=(a*(256-weight)+b*weight+128)/256;end
    endfunction
    always @(posedge clk)begin
        if(!rst)begin
            input_x=0;input_y=0;
            for(k=0;k<6;k=k+1)pipeline[k]=0;
        end else begin
            if(user)begin input_x=0;input_y=0;end
            expected_rgb=0;
            if(de)begin
                expected_rgb=rgb;
                if(valid)begin
                    ux=input_x*15*256/(WIDTH-1);uy=input_y*8*256/(HEIGHT-1);
                    nx=(ux/256<15)?ux/256:14;ny=(uy/256<8)?uy/256:7;
                    fx=ux-nx*256;fy=uy-ny*256;
                    for(c=0;c<3;c=c+1)begin
                        t0=mix(expected_gains[ny*16+nx][(2-c)*12+:12],expected_gains[ny*16+nx+1][(2-c)*12+:12],fx);
                        t1=mix(expected_gains[(ny+1)*16+nx][(2-c)*12+:12],expected_gains[(ny+1)*16+nx+1][(2-c)*12+:12],fx);
                        gain=mix(t0,t1,fy);p=(rgb[(2-c)*8+:8]*gain+128)/256;
                        expected_rgb[(2-c)*8+:8]=(p>255)?255:p;
                    end
                end
                if(input_x==WIDTH-1)begin input_x=0;input_y=(input_y==HEIGHT-1)?0:input_y+1;end
                else input_x=input_x+1;
                pixels=pixels+1;
            end
            for(k=5;k>0;k=k-1)pipeline[k]=pipeline[k-1];
            pipeline[0]={vs,hs,de,user,last,expected_rgb};
            if(dut.gain_we)begin
                if(dut.gain_addr!==writes[7:0] || dut.gain_data!==expected_gains[writes])
                    $fatal(1,"Gain mismatch node %0d: addr=%0d got=%h expected=%h",writes,dut.gain_addr,dut.gain_data,expected_gains[writes]);
                writes=writes+1;
            end
        end
        #1;
        if({ovs,ohs,ode,ouser,olast,output_rgb} !== pipeline[5])
            $fatal(1,"Pixel/timing mismatch after %0d inputs valid=%b got=%h expected=%h",pixels,valid,output_rgb,pipeline[5][23:0]);
    end
    task blank;
        begin @(negedge clk);de=0;user=0;last=0;hs=1;rgb=0;end
    endtask
    task frame;
        input integer kind;
        integer xx,yy;
        begin
            for(yy=0;yy<HEIGHT;yy=yy+1)begin
                for(xx=0;xx<WIDTH;xx=xx+1)begin
                    @(negedge clk);de=1;user=(xx==0&&yy==0);last=(xx==WIDTH-1);hs=0;vs=0;
                    rgb={8'(value(0,xx,yy,kind)),8'(value(1,xx,yy,kind)),8'(value(2,xx,yy,kind))};
                end
                repeat(8)blank();
            end
            vs=1;repeat(10)blank();vs=0;
        end
    endtask
    task trigger;
        begin blank();request=1;blank();request=0;writes=0;end
    endtask
    task clear_profile;
        begin blank();invalidate=1;blank();invalidate=0;repeat(8)blank();
            if(valid || busy || error)$fatal(1,"Exposure change did not invalidate calibration");end
    endtask
    initial begin
        // Independently calculate all 144 patch means and expected divider results.
        for(n=0;n<144;n=n+1)begin
            wx=((n%16)*(WIDTH-1)+7)/15-4;
            wy=((n/16)*(HEIGHT-1)+4)/8-4;
            if(wx<0)wx=0;if(wx>WIDTH-8)wx=WIDTH-8;
            if(wy<0)wy=0;if(wy>HEIGHT-8)wy=HEIGHT-8;
            sr=0;sg=0;sb=0;
            for(py=0;py<8;py=py+1)for(px=0;px<8;px=px+1)begin
                sr=sr+value(0,wx+px,wy+py,0);sg=sg+value(1,wx+px,wy+py,0);sb=sb+value(2,wx+px,wy+py,0);
            end
            mr=(sr*16+512)/1024;mg=(sg*16+512)/1024;mb=(sb*16+512)/1024;
            gr=(40960+mr/2)/mr;gg=(40960+mg/2)/mg;gb=(40960+mb/2)/mb;
            expected_gains[n]={12'(gr),12'(gg),12'(gb)};
        end
        repeat(3)blank();rst=1;
        frame(0);if(valid||busy||writes!=0)$fatal(1,"Calibration started without request");
        trigger();
        for(f=0;f<28 && !valid && !error;f=f+1)frame(0);
        if(!valid || busy || error || writes!=144)$fatal(1,"White-field calibration failed: valid=%b error=%b writes=%0d",valid,error,writes);
        frame(0);frame(3);
        if(writes!=144)$fatal(1,"Normal scene overwrote the calibration");
        clear_profile();frame(3);
        if(RUN_FAILURES)begin
            trigger();for(f=0;f<28 && !error;f=f+1)frame(1);
            if(!error||busy||valid||writes!=0)$fatal(1,"Dark white-field capture was not rejected");
            trigger();for(f=0;f<28 && !error;f=f+1)frame(2);
            if(!error||busy||valid||writes!=0)$fatal(1,"Clipped white-field capture was not rejected");
            trigger();for(f=0;f<28 && !valid && !error;f=f+1)frame(0);
            if(!valid||error||writes!=144)$fatal(1,"Recalibration after failure did not recover");
            frame(0);
        end
        repeat(10)blank();
        $display("PASS: on-board calibration %0dx%0d, all 144 RGB gains, 16-frame patch accumulation, raw-before-ready, frame-boundary apply, invalidation, failures=%0d (%0d inputs)",WIDTH,HEIGHT,RUN_FAILURES,pixels);
        $finish;
    end
endmodule
