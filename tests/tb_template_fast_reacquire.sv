`timescale 1ns/1ps
module tb_coarse_pyramid;
    localparam W=164,H=148,CW=W/4,CH=H/4;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,command=0,de=0,learn=0,accepted=0,search=0,ack=0,drop=0;
    reg [10:0] x=0,y=0;reg [7:0] luma=0;
    wire valid;wire [10:0] px,py;
    integer xx,yy,i,j,k,a,b,sum,checks=0,cycles=0;
    reg [7:0] snapshot[0:CW*CH-1],frozen[0:63];
    hx_template_coarse_proposer #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H)) dut (
        .clk(clk),.rst_n(rst),.command(command),.de(de),.x(x),.y(y),.luma(luma),
        .learn_start(learn),.template_accepted(accepted),.search_allowed(search),.proposal_ack(ack),
        .proposal_valid(valid),.proposal_x(px),.proposal_y(py));
    function integer pixel(input integer xx,yy,tx,ty,kind);
        integer a,b;
        begin
            a=xx-tx+32;b=yy-ty+32;pixel=24;
            if(kind==2)pixel=(xx*11+yy*19+xx*yy)%256;
            else if(a>=0 && a<64 && b>=0 && b<64)begin
                pixel=64+((a/8)*73+(b/8)*151+(a/8)*(b/8)*37+19)%128;
                if(kind==1)pixel=240-pixel;
            end
        end
    endfunction
    task idle(input integer n);begin repeat(n)begin @(negedge clk);de=0;command=0;ack=0;end end endtask
    task frame(input integer tx,ty,kind,blank);
        begin
            for(yy=0;yy<H;yy=yy+1)begin
                for(xx=0;xx<W;xx=xx+1)begin
                    @(negedge clk);de=1;x=xx;y=yy;luma=pixel(xx,yy,tx,ty,kind);
                    if(drop && xx==W/2 && yy==H/2)de=0;
                end
                idle(8);
            end
            idle(blank);
        end
    endtask
    task frozen_ok;begin for(i=0;i<64;i=i+1)if(dut.tpl_mem[i]!==frozen[i])$fatal(1,"Coarse template changed");end endtask
    initial begin
        idle(4);rst=1;idle(4);learn=1;frame(W/2,H/2,2,500);learn=0;accepted=1;
        if(!dut.tpl_ok)$fatal(1,"Coarse learning failed");
        for(j=0;j<CH;j=j+1)for(i=0;i<CW;i=i+1)begin
            sum=0;for(a=0;a<4;a=a+1)for(b=0;b<4;b=b+1)sum=sum+pixel(i*4+a,j*4+b,W/2,H/2,2);
            if(dut.g_image.read_byte(j*CW+i) !== (sum/16))$fatal(1,"Box mean mismatch at %0d,%0d got %0d expected %0d",i,j,dut.g_image.read_byte(j*CW+i),sum/16);
            checks=checks+1;
        end
        for(i=0;i<64;i=i+1)frozen[i]=dut.tpl_mem[i];
        search=1;frame(W/2,H/2,2,2);
        for(i=0;i<CW*CH;i=i+1)snapshot[i]=dut.g_image.read_byte(i);
        if(dut.phase<4)$fatal(1,"Coarse scan not started");
        frame(32,32,0,2);
        for(i=0;i<CW*CH;i=i+1)if(snapshot[i]!==dut.g_image.read_byte(i))$fatal(1,"Coarse buffer torn during scan");
        cycles=0;while(!valid && cycles<400000)begin idle(1);cycles=cycles+1;end
        if(!valid || px<32 || px>W-32 || py<32 || py>H-32)$fatal(1,"Coarse proposal invalid");
        frozen_ok();
        // Both input and proposal queue may change; old snapshot must stay stable.
        for(k=0;k<12;k=k+1)frame(32,32,0,2);
        if(valid)$fatal(1,"Stale proposals did not expire");
        command=1;idle(1);if(valid || dut.tpl_ok || dut.collect || dut.phase!=0)$fatal(1,"Coarse cancel failed");
        learn=1;drop=1;frame(W/2,H/2,2,500);learn=0;drop=0;
        if(dut.tpl_ok)$fatal(1,"Incomplete learning accepted");
        learn=1;frame(W/2,H/2,0,500);learn=0;
        if(!dut.tpl_ok)$fatal(1,"Second coarse learning failed");
        search=1;drop=1;frame(32,32,0,500);drop=0;
        if(dut.phase!=0 || valid)$fatal(1,"Incomplete coarse snapshot accepted");
        search=0;accepted=0;
        $display("PASS coarse pyramid: %0d exact box means; immutable snapshot/template, two-peak queue/bounds/expiry, command, incomplete learn/search",checks);
        $finish;
    end
    initial begin #20000000;$fatal(1,"Coarse pyramid timeout");end
endmodule

module tb_template_fast_reacquire #(parameter integer W=320,H=256,ROW_IDLE=20,ONLY_720P=0,ONLY_PHASES=0);
    reg clk=0;always #5 clk=~clk;
    reg rst=0,command=0,de=0,drop=0;reg [10:0] x=0,y=0;reg [7:0] luma=0;
    wire [2:0] status;wire [10:0] cx,cy;wire [3:0] reason;
    integer xx,yy,a,b,v,k,n,j,frames=0,checks=0,attempts,latest=0,work=0,max_work=0,fast_slots=0;
    integer phase_x,phase_y;
    reg [7:0] frozen[0:63],coarse_frozen[0:63];
    // DISP_SMOOTH_SHIFT/DEADBAND=0：关闭显示框平滑，center_x 严格等于跟踪中心。
    hx_template_tracker #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),
        .DISP_SMOOTH_SHIFT(0),.DISP_DEADBAND(0)) dut(
        .clk(clk),.rst_n(rst),.command(command),.de(de),.x(x),.y(y),.luma(luma),
        .status(status),.center_x(cx),.center_y(cy),.busy(),.debug_reason(reason),.debug_best(),.debug_margin(),.debug_misses());
    always @(posedge clk)begin
        if(!rst || !dut.busy)work=0;else begin work=work+1;if(work>max_work)max_work=work;end
        if(rst && dut.frame_start && dut.fast_active)fast_slots=fast_slots+1;
    end
    function integer texture(input integer px,py,kind);
        integer p,q;
        begin
            p=(px*3+py+2048)%47;q=(py*2-px+2048)%37;
            if(p>23)p=46-p;if(q>18)q=36-q;
            texture=40+4*p+3*q;if(kind==1)texture=240-texture;
        end
    endfunction
    task idle(input integer n);begin repeat(n)begin @(negedge clk);de=0;command=0;end end endtask
    task frame(input integer tx,ty,present,kind);
        begin
            frames=frames+1;
            for(yy=0;yy<H;yy=yy+1)begin
                for(xx=0;xx<W;xx=xx+1)begin
                    @(negedge clk);de=1;x=xx;y=yy;luma=24;
                    a=xx-tx+32;b=yy-ty+32;
                    if(present && a>=0 && a<64 && b>=0 && b<64)luma=texture(a,b,kind);
                    if(kind==2)luma=60+120*((xx/8+yy/8)%2);
                    if(drop && xx==W/2 && yy==H/2)de=0;
                end
                idle(ROW_IDLE);
            end
            idle(49500);
        end
    endtask
    task state_is(input integer st);begin checks=checks+1;if(status!==st)$fatal(1,"Fast frame %0d state=%0d expected=%0d R=%0d",frames,status,st,reason);end endtask
    task learn;
        begin
            rst=0;idle(4);rst=1;idle(4);command=1;idle(1);frame(W/2,H/2,1,0);state_is(2);
            if(!dut.g_fast.u_proposer.tpl_ok)$fatal(1,"Main accepted but coarse template missing");
            for(j=0;j<64;j=j+1)begin frozen[j]=dut.template_mem[j];coarse_frozen[j]=dut.g_fast.u_proposer.tpl_mem[j];end
        end
    endtask
    task frozen_ok;
        begin for(j=0;j<64;j=j+1)if(frozen[j]!==dut.template_mem[j] || coarse_frozen[j]!==dut.g_fast.u_proposer.tpl_mem[j])$fatal(1,"Fast modified template");end
    endtask
    task missing;begin for(n=0;n<16;n=n+1)frame(0,0,0,0);state_is(4);end endtask
    task recover(input integer tx,ty);
        begin
            attempts=0;
            while(status==4 && attempts<48)begin frame(tx,ty,1,0);attempts=attempts+1;end
            state_is(6);
            if(!dut.recovery_slot_fast || reason!=9 || dut.confirm_count!=1)$fatal(1,"Fast proposal did not use fine VERIFY");
            if(dut.cx!=W/2 || dut.cy!=H/2)$fatal(1,"Fast proposal changed reliable center early");
            frame(tx,ty,1,0);state_is(6);frame(tx,ty,1,0);state_is(2);
            if(cx!=tx || cy!=ty || reason!=10)$fatal(1,"Fast localization incorrect %0d,%0d target=%0d,%0d",cx,cy,tx,ty);
            if(attempts>latest)latest=attempts;
            frozen_ok();
            $display("FAST recovered %0d,%0d proposal after %0d frames",tx,ty,attempts);
        end
    endtask
    initial begin
        if(ONLY_PHASES)begin
            for(phase_y=0;phase_y<4;phase_y=phase_y+1)for(phase_x=0;phase_x<4;phase_x=phase_x+1)begin
                learn();missing();recover(32+phase_x,32+phase_y);
                if(attempts>16)$fatal(1,"Fresh pixel-phase candidate too late");
            end
            $display("PASS fast pixel phases: all 16 sub-quarter-pixel phases through coarse proposal and full-resolution three-frame confirmation; frames=%0d max proposal frames=%0d",frames,latest);
            $finish;
        end
        if(ONLY_720P)begin
            learn();missing();
            for(k=0;k<3;k=k+1)frame(0,0,0,0);
            if(dut.g_fast.u_proposer.phase<4)$fatal(1,"720p test must return during old background scan");
            recover(1120,560);
            if(latest>42 || max_work>=14000 || fast_slots==0)$fatal(1,"720p fast recovery budget exceeded");
            $display("PASS 720p fast recovery: returning during busy background scan, proposal after %0d frames +2 confirmation at 720p60 timing; total frames=%0d fine cycles=%0d",latest,frames,max_work);
            $finish;
        end
        learn();missing();recover(32,32);
        learn();missing();recover(W-32,32);
        learn();missing();recover(32,H-32);
        learn();missing();recover(W-32,H-32);
        learn();missing();recover(35,35);
        learn();missing();drop=1;for(k=0;k<8;k=k+1)begin frame(32,32,1,0);state_is(4);end;drop=0;
        recover(32,32);
        learn();missing();for(k=0;k<8;k=k+1)begin frame(32,32,1,1);state_is(4);end
        for(k=0;k<8;k=k+1)begin frame(0,0,0,2);state_is(4);end
        recover(W-32,H-32);
        @(negedge clk);command=1;idle(1);state_is(0);
        for(k=0;k<4;k=k+1)frame(32,32,1,0);state_is(0);
        if(dut.template_valid || dut.g_fast.u_proposer.tpl_ok || dut.fast_available)$fatal(1,"Fast cancel left candidate/template");
        if(max_work>=14000 || fast_slots==0)$fatal(1,"Fast coverage/timing failed");
        $display("PASS fast reacquire: %0d full frames %0d checks; corners/pixel phase/incomplete/wrong/ambiguous/cancel, frozen templates and fine 3-frame confirmation; max proposal frames=%0d, fine cycles=%0d, fast slots=%0d",frames,checks,latest,max_work,fast_slots);
        $finish;
    end
    initial begin #(64'd1500000000);$fatal(1,"Fast reacquire timeout");end
endmodule

module tb_template_global_equivalence;
    tb_template_global_720p_schedule stimulus();
    wire [2:0] status;wire [10:0] cx,cy;wire busy;wire [3:0] reason;wire [14:0] best,margin;wire [4:0] misses;
    integer compared=0;
    hx_template_tracker_global_ref reference_dut(.clk(stimulus.clk),.rst_n(stimulus.rst),.command(stimulus.command),
        .de(stimulus.de),.x(stimulus.x),.y(stimulus.y),.luma(stimulus.luma),.status(status),.center_x(cx),.center_y(cy),.busy(busy),
        .debug_reason(reason),.debug_best(best),.debug_margin(margin),.debug_misses(misses));
    always @(posedge stimulus.clk)begin
        #1;
        if(stimulus.rst)begin
            compared=compared+1;
            if({status,cx,cy,busy,reason,best,margin,misses} !==
                {stimulus.dut.status,stimulus.dut.center_x,stimulus.dut.center_y,stimulus.dut.busy,
                 stimulus.dut.debug_reason,stimulus.dut.debug_best,stimulus.dut.debug_margin,stimulus.dut.debug_misses} ||
                reference_dut.search_x!==stimulus.dut.search_x || reference_dut.search_y!==stimulus.dut.search_y ||
                reference_dut.global_x!==stimulus.dut.global_x || reference_dut.global_y!==stimulus.dut.global_y ||
                reference_dut.retry_step!==stimulus.dut.retry_step || reference_dut.global_turn!==stimulus.dut.global_turn)
                $fatal(1,"FAST_REACQUIRE=0 changed original global scheduler");
        end
    end
    final begin
        if(compared<70000)$error("Global equivalence coverage insufficient");
        else $display("PASS global equivalence: %0d cycles across two real-720p sweeps, exact observable state/coordinates/scores/schedule with fast disabled",compared);
    end
endmodule
