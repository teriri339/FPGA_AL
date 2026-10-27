`timescale 1ns/1ps
module tb_template_global_reacquire;
    // Non-multiple-of-16 limits exercise the clamped final row and column.
    localparam W=338,H=258;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,command=0,de=0,drop_pixel=0;
    reg [10:0] x=0,y=0;
    reg [7:0] luma=0,frozen[0:63];
    wire [2:0] status;wire [10:0] cx,cy;wire [3:0] reason;
    integer xx,yy,a,b,v,k,n,j,frames=0,checks=0,attempts,work_cycles=0,max_cycles=0;
    integer oldx,oldy,cursorx,cursory;
    // DISP_SMOOTH_SHIFT/DEADBAND=0：关闭显示框平滑，center_x 严格等于跟踪中心。
    hx_template_tracker #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),.FAST_REACQUIRE(0),
        .DISP_SMOOTH_SHIFT(0),.DISP_DEADBAND(0)) dut (
        .clk(clk),.rst_n(rst),.command(command),.de(de),.x(x),.y(y),.luma(luma),
        .status(status),.center_x(cx),.center_y(cy),.busy(),.debug_reason(reason),
        .debug_best(),.debug_margin(),.debug_misses()
    );
    always @(posedge clk)begin
        if(!rst || !dut.busy)work_cycles=0;
        else begin work_cycles=work_cycles+1;if(work_cycles>max_cycles)max_cycles=work_cycles;end
    end
    function integer texture(input integer px,py,kind);
        integer p,q;
        begin
            p=(px*3+py+2048)%47;q=(py*2-px+2048)%37;
            if(p>23)p=46-p;if(q>18)q=36-q;
            texture=40+4*p+3*q;if(kind==1)texture=240-texture;
        end
    endfunction
    task idle(input integer count);
        begin repeat(count)begin @(negedge clk);de=0;command=0;end end
    endtask
    task frame(input integer tx,ty,present,kind,blank);
        begin
            frames=frames+1;
            for(yy=0;yy<H;yy=yy+1)begin
                for(xx=0;xx<W;xx=xx+1)begin
                    @(negedge clk);de=1;x=xx;y=yy;luma=24;
                    a=xx-tx+32;b=yy-ty+32;
                    if(present && a>=0 && a<64 && b>=0 && b<64)luma=texture(a,b,kind);
                    if(kind==2)luma=60+120*((xx/8+yy/8)%2);
                    if(drop_pixel && xx==tx && yy==ty)de=0;
                end
                idle(20);
            end
            idle(blank);
        end
    endtask
    task state_is(input integer st);
        begin checks=checks+1;if(status!==st)$fatal(1,"Global frame %0d state %0d expected %0d R=%0d",frames,status,st,reason);end
    endtask
    task frozen_ok;
        begin for(j=0;j<64;j=j+1)if(frozen[j]!==dut.template_mem[j])$fatal(1,"Global changed frozen template");end
    endtask
    task learn;
        begin
            rst=0;idle(4);rst=1;idle(4);@(negedge clk);command=1;idle(1);
            frame(W/2,H/2,1,0,49500);state_is(2);
            for(j=0;j<64;j=j+1)frozen[j]=dut.template_mem[j];
        end
    endtask
    task missing;
        begin
            for(n=0;n<16;n=n+1)frame(0,0,0,0,49500);
            state_is(4);
            if(dut.global_warmup!=0 || dut.global_turn!=0 || dut.global_x!=32 || dut.global_y!=32)
                $fatal(1,"Global entry/reset cursor incorrect");
        end
    endtask
    task candidate_at(input integer tx,ty);
        begin
            attempts=0;oldx=dut.cx;oldy=dut.cy;
            while(status==4 && attempts<600)begin
                frame(tx,ty,1,0,49500);attempts=attempts+1;
                if(dut.cx!=oldx || dut.cy!=oldy)$fatal(1,"Global proposal moved reliable center");
            end
            state_is(6);
            if(reason!=9 || dut.confirm_count!=1 || !dut.recovery_slot_global)
                $fatal(1,"Far-away target did not come through global proposal/VERIFY");
            if(cx!=tx || cy!=ty)$fatal(1,"Global proposal localized incorrectly %0d,%0d != %0d,%0d",cx,cy,tx,ty);
            frozen_ok();
        end
    endtask
    task confirm_at(input integer tx,ty);
        begin
            frame(tx,ty,1,0,49500);state_is(6);
            frame(tx,ty,1,0,49500);state_is(2);
            if(cx!=tx || cy!=ty || reason!=10 || dut.global_warmup!=0 || dut.global_turn!=0 || dut.global_x!=32 || dut.global_y!=32)
                $fatal(1,"Global confirmation/reset failed");
            frozen_ok();
        end
    endtask
    initial begin
        learn();missing();candidate_at(32,32);if(attempts!=34)$fatal(1,"Warmup/local priority changed");confirm_at(32,32);
        learn();missing();candidate_at(W-32,32);confirm_at(W-32,32);
        learn();missing();candidate_at(32,H-32);confirm_at(32,H-32);
        learn();missing();candidate_at(W-32,H-32);confirm_at(W-32,H-32);
        learn();missing();candidate_at(32,32);
        cursorx=dut.global_x;cursory=dut.global_y;
        frame(0,0,0,0,49500);state_is(4);
        if(dut.confirm_count!=0 || dut.global_x!=cursorx || dut.global_y!=cursory || cursorx==32)
            $fatal(1,"Flashing proposal lost progress/starved global sweep");
        // Wait almost a whole global sweep: no hierarchical cursor injection.
        candidate_at(32,32);drop_pixel=1;frame(32,32,1,0,49500);drop_pixel=0;state_is(4);
        if(reason!=4 || dut.confirm_count!=0)$fatal(1,"Incomplete global VERIFY accepted");
        frame(32,32,1,0,5);@(negedge clk);de=1;x=0;y=0;idle(5);state_is(4);
        if(reason!=5 || !dut.template_valid)$fatal(1,"Global deadline lost template");
        for(k=0;k<40;k=k+1)begin frame(32,32,1,1,49500);state_is(4);end
        for(k=0;k<16;k=k+1)begin frame(0,0,0,2,49500);state_is(4);end
        candidate_at(W-32,H-32);confirm_at(W-32,H-32);
        @(negedge clk);command=1;idle(1);state_is(0);
        if(dut.template_valid || dut.global_warmup || dut.global_turn || dut.global_x!=32 || dut.global_y!=32)
            $fatal(1,"Cancel retained global search");
        for(k=0;k<4;k=k+1)frame(32,32,1,0,49500);state_is(0);
        if(max_cycles>=14000)$fatal(1,"Global compute budget exceeded");
        $display("PASS global reacquire: %0d complete frames %0d checks; four far corners, nonaligned limits, warmup, frozen template, VERIFY/flash/incomplete/deadline/wrong/ambiguous/cancel; max cycles=%0d",frames,checks,max_cycles);
        $finish;
    end
    initial begin #(64'd6000000000);$fatal(1,"Global timeout");end
endmodule

// Real 720p scheduler: synthetic sample learning followed by incomplete frames.
// This checks address coverage and arbitration, NOT image matching.
module tb_template_global_720p_schedule;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,command=0,de=0;reg [10:0] x=0,y=0;reg [7:0] luma=0;
    wire [2:0] status;
    integer k,i,j,gx,gy,globals=0,locals=0,checks=0;
    reg seen[0:3233];
    // DISP_SMOOTH_SHIFT/DEADBAND=0：关闭显示框平滑，center_x 严格等于跟踪中心。
    hx_template_tracker #(.FAST_REACQUIRE(0),
        .DISP_SMOOTH_SHIFT(0),.DISP_DEADBAND(0)) dut(.clk(clk),.rst_n(rst),.command(command),.de(de),.x(x),.y(y),.luma(luma),
        .status(status),.center_x(),.center_y(),.busy(),.debug_reason(),.debug_best(),.debug_margin(),.debug_misses());
    task idle(input integer n);begin repeat(n)begin @(negedge clk);de=0;command=0;end end endtask
    task reject_frame;
        begin
            @(negedge clk);de=1;x=0;y=0;luma=24;
            @(negedge clk);de=1;x=1279;y=719;luma=24;idle(4);
        end
    endtask
    initial begin
        idle(4);rst=1;idle(4);@(negedge clk);command=1;idle(1);
        @(negedge clk);de=1;x=0;y=0;
        for(j=0;j<8;j=j+1)for(i=0;i<8;i=i+1)begin
            @(negedge clk);de=1;x=610+i*8;y=330+j*8;luma=40+(i*73+j*151+i*j*37+19)%128;
        end
        @(negedge clk);de=1;x=1279;y=719;idle(500);
        if(status!=2)$fatal(1,"Schedule fixture learning failed");
        for(k=0;k<16;k=k+1)reject_frame();
        if(status!=4)$fatal(1,"Schedule fixture missing LOST");
        for(i=0;i<3234;i=i+1)seen[i]=0;
        gx=32;gy=32;
        for(k=0;k<32+4*3234;k=k+1)begin
            if(dut.global_active !== (k>=32 && k%2==1))$fatal(1,"720p arbitration slot %0d",k);
            if(dut.global_active)begin
                if(dut.search_x!=gx || dut.search_y!=gy)$fatal(1,"720p row-major cursor %0d",k);
                if(dut.far_active)$fatal(1,"Two search sources active");
                i=((gy-32)/16)*77+(gx-32)/16;
                if(globals<3234 && seen[i])$fatal(1,"Duplicate global tile");
                seen[i]=1;globals=globals+1;
                if(gx==1248)begin gx=32;gy=gy==688 ?32:gy+16;end else gx=gx+16;
            end else locals=locals+1;
            if(dut.search_x<32 || dut.search_x>1248 || dut.search_y<32 || dut.search_y>688 ||
                dut.next_roi_x>1200 || dut.next_roi_y>640)$fatal(1,"720p out-of-bounds tile");
            checks=checks+1;reject_frame();
            if(status!=4 || dut.debug_reason!=4)$fatal(1,"Schedule incomplete rejection changed");
        end
        if(globals!=6468 || locals!=6500 || gx!=32 || gy!=32)$fatal(1,"720p wrap/count");
        for(i=0;i<3234;i=i+1)if(!seen[i])$fatal(1,"720p tile omitted");
        // Every legal target center lies within the coarse +/-8 coverage of
        // a global tile, including the clamped edge ROIs. Check both axes.
        for(i=32;i<=1248;i=i+1)begin
            j=(i-32)/16;gx=32+j*16;
            if(i-gx>8)gx=gx+16;
            if(gx>1248 || i>gx+8 || i<gx-8)$fatal(1,"720p horizontal gap");
        end
        for(i=32;i<=688;i=i+1)begin
            j=(i-32)/16;gy=32+j*16;
            if(i-gy>8)gy=gy+16;
            if(gy>688 || i>gy+8 || i<gy-8)$fatal(1,"720p vertical gap");
        end
        $display("PASS global 720p schedule: %0d probes, %0d global tiles (two 3234-tile sweeps), %0d local slots; warmup/arbitration/bounds/coverage/wrap",checks,globals,locals);
        $finish;
    end
    initial begin #10000000;$fatal(1,"720p scheduler timeout");end
endmodule

module tb_template_far_equivalence;
    tb_template_far_reacquire stimulus();
    wire [2:0] status;wire [10:0] cx,cy;wire busy;wire [3:0] reason;
    wire [14:0] best,margin;wire [4:0] misses;
    integer compared=0;
    hx_template_tracker_far_ref #(.IMAGE_WIDTH(320),.IMAGE_HEIGHT(256)) reference_dut (
        .clk(stimulus.clk),.rst_n(stimulus.rst),.command(stimulus.command),.de(stimulus.de),
        .x(stimulus.x),.y(stimulus.y),.luma(stimulus.luma),.status(status),.center_x(cx),.center_y(cy),
        .busy(busy),.debug_reason(reason),.debug_best(best),.debug_margin(margin),.debug_misses(misses));
    always @(posedge stimulus.clk)begin
        #1;
        if(stimulus.rst)begin
            compared=compared+1;
            if({status,cx,cy,busy,reason,best,margin,misses} !==
               {stimulus.dut.status,stimulus.dut.center_x,stimulus.dut.center_y,stimulus.dut.busy,
                stimulus.dut.debug_reason,stimulus.dut.debug_best,stimulus.dut.debug_margin,stimulus.dut.debug_misses} ||
                reference_dut.phase!==stimulus.dut.phase || reference_dut.search_x!==stimulus.dut.search_x ||
                reference_dut.search_y!==stimulus.dut.search_y || reference_dut.retry_cadence!==stimulus.dut.retry_cadence ||
                reference_dut.far_x!==stimulus.dut.far_x || reference_dut.far_y!==stimulus.dut.far_y)
                $fatal(1,"GLOBAL_REACQUIRE=0 changed far-release behavior");
        end
    end
    final begin
        if(compared<100000000)$error("Far equivalence coverage insufficient");
        else $display("PASS far equivalence: %0d cycles; global disabled matches previous far release exactly",compared);
    end
endmodule
