`timescale 1ns/1ps
module tb_template_far_reacquire;
    localparam W=320,H=256;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,command=0,de=0,drop_pixel=0;
    reg [10:0] x=0,y=0;
    reg [7:0] luma=0,frozen[0:63];
    wire [2:0] status;
    wire [10:0] cx,cy;
    wire [3:0] reason;
    integer xx,yy,a,b,v,k,n,j,frames=0,checks=0,work_cycles=0,max_work_cycles=0,attempts;
    integer ns,gx,gy,ga,step_no,dir_no,ex,ey;
    integer dx[0:7],dy[0:7];
    hx_template_tracker #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),.GLOBAL_REACQUIRE(0),.FAST_REACQUIRE(0)) dut (
        .clk(clk),.rst_n(rst),.command(command),.de(de),.x(x),.y(y),.luma(luma),
        .status(status),.center_x(cx),.center_y(cy),.busy(),.debug_reason(reason),
        .debug_best(),.debug_margin(),.debug_misses()
    );
    always @(posedge clk)begin
        if(!rst)work_cycles=0;
        else if(dut.busy)begin work_cycles=work_cycles+1;if(work_cycles>max_work_cycles)max_work_cycles=work_cycles;end
        else work_cycles=0;
    end
    function integer texture(input integer px,py,kind);
        integer p,q;
        begin
            p=(px*3+py+2048)%47;q=(py*2-px+2048)%37;
            if(p>23)p=46-p;if(q>18)q=36-q;
            texture=40+4*p+3*q;if(kind==1)texture=240-texture;
        end
    endfunction
    task idle(input integer cycles);
        begin repeat(cycles)begin @(negedge clk);de=0;command=0;end end
    endtask
    task frame(input integer tx,ty,present,kind,blank);
        begin
            frames=frames+1;
            for(yy=0;yy<H;yy=yy+1)begin
                for(xx=0;xx<W;xx=xx+1)begin
                    @(negedge clk);de=1;x=xx;y=yy;v=24;
                    a=xx-(tx-32);b=yy-(ty-32);
                    if(present && a>=0 && a<64 && b>=0 && b<64)v=texture(a,b,kind);
                    if(present && kind==2)v=60+120*((xx/8+yy/8)%2);
                    if(drop_pixel && xx==tx && yy==ty)de=0;
                    luma=v;
                end
                idle(20);
            end
            idle(blank);
        end
    endtask
    task expect_state(input integer st);
        begin checks=checks+1;if(status!==st)$fatal(1,"Far frame %0d status=%0d expected=%0d R=%0d",frames,status,st,reason);end
    endtask
    task learn;
        begin
            rst=0;idle(4);rst=1;idle(4);@(negedge clk);command=1;idle(1);
            frame(W/2,H/2,1,0,49500);expect_state(2);
            for(j=0;j<64;j=j+1)frozen[j]=dut.template_mem[j];
        end
    endtask
    task frozen_ok;
        begin for(j=0;j<64;j=j+1)if(frozen[j]!==dut.template_mem[j])$fatal(1,"Far recovery rewrote template");end
    endtask
    task missing;
        begin
            for(n=0;n<16;n=n+1)frame(0,0,0,0,49500);
            expect_state(4);
            if(dut.retry_cadence!=0 || dut.far_x!=0 || dut.far_y!=0 || dut.far_center!=0)$fatal(1,"Far cursor did not reset on LOST entry");
        end
    endtask
    task candidate_at(input integer tx,ty,old_x,old_y);
        begin
            attempts=0;
            while(status==4 && attempts<576)begin
                frame(tx,ty,1,0,49500);attempts=attempts+1;
                if(dut.cx!=old_x || dut.cy!=old_y)$fatal(1,"Proposal changed reliable center");
            end
            expect_state(6);
            if(reason!=9 || dut.confirm_count!=1)$fatal(1,"Far proposal bypassed VERIFY");
        end
    endtask
    task finish_recovery(input integer tx,ty);
        begin
            frame(tx,ty,1,0,49500);expect_state(6);
            frame(tx,ty,1,0,49500);expect_state(2);
            if(cx!=tx || cy!=ty || reason!=10 || dut.retry_cadence!=0 || dut.far_x!=0 || dut.far_y!=0)
                $fatal(1,"Far recovery failed %0d,%0d -> %0d,%0d",tx,ty,cx,cy);
            frozen_ok();
        end
    endtask
    initial begin
        dx[0]=1;dy[0]=0;dx[1]=-1;dy[1]=0;dx[2]=0;dy[2]=1;dx[3]=0;dy[3]=-1;
        dx[4]=1;dy[4]=1;dx[5]=-1;dy[5]=1;dx[6]=1;dy[6]=-1;dx[7]=-1;dy[7]=-1;
        learn();missing();ns=0;gx=0;gy=0;ga=0;
        // Incomplete-frame rejection uses the same cursor update as SAD failure;
        // cheaply audit two complete 576-slot sweeps and independent coordinates.
        for(k=0;k<1152;k=k+1)begin
            ex=W/2;ey=H/2;
            if(k%4==3)begin ex=ex+(gx-4)*16;ey=ey+(gy-4)*16;end
            else begin
                step_no=(ns/2)%16;
                if(step_no%2)begin dir_no=step_no/2;ex=ex+16*dx[dir_no];ey=ey+16*dy[dir_no];end
            end
            if(dut.search_x!=ex || dut.search_y!=ey || dut.far_active!=(k%4==3))$fatal(1,"Far schedule mismatch slot %0d",k);
            if(k%4==3 && (dut.far_x!=gx || dut.far_y!=gy || dut.far_center!=ga))$fatal(1,"Far grid/anchor mismatch");
            checks=checks+1;
            @(negedge clk);de=1;x=0;y=0;luma=24;
            @(negedge clk);de=1;x=W-1;y=H-1;luma=24;
            idle(4);expect_state(4);
            if(reason!=4)$fatal(1,"Probe must reject incomplete frame");
            if(k%4==3)begin
                if(ga==1)begin
                    if(gx==8)begin gx=0;gy=(gy+1)%9;end else gx=gx+1;
                    if(gy>=3 && gy<=5 && gx==3)gx=6;
                end
                ga=1-ga;
            end else ns=(ns+1)%32;
        end
        if(gx!=0 || gy!=0 || ga!=0 || ns!=0)$fatal(1,"Sweep coverage/wrap incomplete");
        learn();missing();candidate_at(184,128,160,128);
        if(attempts!=3)$fatal(1,"Near priority regressed");finish_recovery(184,128);
        learn();missing();candidate_at(96,64,160,128);
        if(attempts!=4)$fatal(1,"First far window timing incorrect");finish_recovery(96,64);
        learn();missing();candidate_at(224,192,160,128);finish_recovery(224,192);
        learn();
        for(k=1;k<=16;k=k+1)frame(160+k*8,k<=12 ? 128+k*8 : 224,1,0,49500);
        expect_state(2);if(cx!=288 || cy!=224)$fatal(1,"Move to edge failed");
        missing();candidate_at(224,160,288,224);finish_recovery(224,160);
        learn();missing();
        for(k=0;k<32;k=k+1)begin frame(64,32,1,0,49500);expect_state(4);end
        for(k=0;k<32;k=k+1)begin frame(96,64,1,1,49500);expect_state(4);end
        candidate_at(96,64,160,128);frame(0,0,0,0,49500);expect_state(4);
        if(dut.confirm_count!=0)$fatal(1,"Far flash retained confirmation");
        candidate_at(96,64,160,128);drop_pixel=1;frame(96,64,1,0,49500);drop_pixel=0;expect_state(4);
        if(reason!=4 || dut.confirm_count!=0)$fatal(1,"Incomplete VERIFY accepted");
        frame(96,64,1,0,5);@(negedge clk);de=1;x=0;y=0;idle(5);expect_state(4);
        if(reason!=5 || !dut.template_valid)$fatal(1,"Far deadline failed");
        candidate_at(96,64,160,128);finish_recovery(96,64);
        @(negedge clk);command=1;idle(1);expect_state(0);
        for(k=0;k<4;k=k+1)frame(96,64,1,0,49500);
        expect_state(0);if(dut.template_valid)$fatal(1,"Cancel allowed far relock");
        if(max_work_cycles>=14000)$fatal(1,"Far search exceeded frame compute budget");
        $display("PASS far reacquire: %0d full frames %0d checks; 1152 schedule probes, priority/72-grid/two-anchor/wrap, far corners, edge clamp, template/VERIFY/failure/deadline/cancel; max cycles=%0d",frames,checks,max_work_cycles);
        $finish;
    end
    initial begin #(64'd3000000000);$fatal(1,"Far reacquire timeout");end
endmodule
