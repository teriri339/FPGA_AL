`timescale 1ns/1ps
// Compile ONLY with the untouched a7676fb adapter/pipeline, not today's RTL.
module tb_history_raw_compare;
    localparam W=1280,H=720;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,de=0,user=0,last=0,vs=0,hs=0;
    reg [23:0] rgb=0;
    reg [1:0] mode=0;
    wire [4:0] adapted,shown;
    wire [23:0] adapted_rgb,shown_rgb;
    hx_pixel_stream_adapter adapter(
        .I_clk(clk),.I_rst_n(rst),.I_de(de),.I_user(user),.I_last(last),.I_vsync(vs),.I_hsync(hs),.I_rgb(rgb),
        .O_vsync(adapted[4]),.O_hsync(adapted[3]),.O_de(adapted[2]),.O_user(adapted[1]),.O_last(adapted[0]),.O_rgb(adapted_rgb));
    hx_vision_pipeline dut(
        .I_clk(clk),.I_rst_n(rst),.I_de(adapted[2]),.I_user(adapted[1]),.I_last(adapted[0]),
        .I_vsync(adapted[4]),.I_hsync(adapted[3]),.I_rgb(adapted_rgb),.I_mode(mode),
        .I_exposure_level(2'd1),.I_auto_exposure(1'b0),
        .O_vsync(shown[4]),.O_hsync(shown[3]),.O_de(shown[2]),.O_user(shown[1]),.O_last(shown[0]),.O_rgb(shown_rgb),
        .O_target_found(),.O_target_pixels(),.O_frame_luma(),.O_frame_highlights(),.O_frame_shadows(),.O_frame_luma_toggle());
    reg [4:0] cq[0:1];reg [23:0] pq[0:1];
    integer xq[0:1],yq[0:1],sx=0,sy=0,k,xx,yy,f,g,checked=0,plain=0;
    always @(posedge clk)begin
        if(!rst)begin
            for(k=0;k<2;k=k+1)begin cq[k]=0;pq[k]=0;xq[k]=0;yq[k]=0;end
        end else begin
            if(adapted!=={vs,hs,de,user,last}||adapted_rgb!==rgb)$fatal(1,"Historical adapter is not direct");
            cq[1]=cq[0];pq[1]=pq[0];xq[1]=xq[0];yq[1]=yq[0];
            cq[0]={vs,hs,de,user,last};xq[0]=sx;yq[0]=sy;
            g=(77*rgb[23:16]+150*rgb[15:8]+29*rgb[7:0])/256;
            pq[0]=mode==0?rgb:g*24'h010101;
            #1;
            if(shown!==cq[1])$fatal(1,"Historical two-register video alignment changed");
            if(shown[2])begin
                checked=checked+1;
                if(!(xq[1]<432&&yq[1]<32))begin
                    plain=plain+1;
                    if(shown_rgb!==pq[1])$fatal(1,"Historical RAW/GRAY mismatch at %d,%d",xq[1],yq[1]);
                end
            end else if(shown_rgb!==0)$fatal(1,"Nonzero historical blanking");
        end
    end
    task idle;begin @(posedge clk);#2;de=0;user=0;last=0;vs=0;hs=0;end endtask
    initial begin
        repeat(5)idle();rst=1;
        for(f=0;f<2;f=f+1)begin
            mode=f;repeat(8)idle();
            for(yy=0;yy<H;yy=yy+1)begin
                for(xx=0;xx<W;xx=xx+1)begin
                    @(posedge clk);#2;sx=xx;sy=yy;
                    de=1;user=(xx==0&&yy==0);last=(xx==W-1);vs=(yy==0);hs=(xx<3);
                    rgb={8'(xx+yy),8'(xx*3+yy*7),8'(xx*11+yy)};
                end
                repeat(5)idle();
            end
        end
        repeat(8)idle();
        if(checked!=2*W*H||plain!=2*(W*H-432*32))$fatal(1,"Pixel count mismatch");
        $display("PASS historical a7676fb: %d pixels, %d RAW/GRAY pixels outside original OSD; unchanged adapter and two-cycle alignment",checked,plain);
        $finish;
    end
endmodule
