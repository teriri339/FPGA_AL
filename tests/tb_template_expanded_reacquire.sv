`timescale 1ns/1ps
module tb_template_expanded_reacquire;
    localparam W=192,H=160;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,command=0,de=0,drop_pixel=0,check_sweep=0;
    reg [10:0] x=0,y=0;
    reg [7:0] luma=0,frozen[0:63];
    wire [2:0] status;
    wire [10:0] cx,cy;
    wire [3:0] reason;
    integer xx,yy,a,b,v,k,n,d,j,frames=0,checks=0,work_cycles=0,max_work_cycles=0;
    integer directions_x[0:7],directions_y[0:7],expected_slot=0,ex,ey,step_no,dir_no;
    hx_template_tracker #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),.FAR_REACQUIRE(0),.GLOBAL_REACQUIRE(0),.FAST_REACQUIRE(0)) dut (
        .clk(clk),.rst_n(rst),.command(command),.de(de),.x(x),.y(y),.luma(luma),
        .status(status),.center_x(cx),.center_y(cy),.busy(),.debug_reason(reason),
        .debug_best(),.debug_margin(),.debug_misses()
    );
    always @(posedge clk)begin
        if(!rst)work_cycles=0;
        else if(dut.busy)begin work_cycles=work_cycles+1;if(work_cycles>max_work_cycles)max_work_cycles=work_cycles;end
        else work_cycles=0;
        if(rst && check_sweep && de && x==0 && y==0)begin
            step_no=(expected_slot/2)%16;ex=W/2;ey=H/2;
            if(step_no%2)begin dir_no=step_no/2;ex=ex+16*directions_x[dir_no];ey=ey+16*directions_y[dir_no];end
            if(dut.search_x!=ex || dut.search_y!=ey || dut.retry_center!=expected_slot%2)
                $fatal(1,"Sweep slot %0d expected %0d,%0d got %0d,%0d",expected_slot,ex,ey,dut.search_x,dut.search_y);
            checks=checks+1;
        end
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
        begin checks=checks+1;if(status!==st)$fatal(1,"Frame %0d status=%0d expected=%0d reason=%0d",frames,status,st,reason);end
    endtask
    task learn;
        begin
            rst=0;idle(4);rst=1;idle(4);@(negedge clk);command=1;idle(1);
            frame(W/2,H/2,1,0,49500);expect_state(2);
            for(j=0;j<64;j=j+1)frozen[j]=dut.template_mem[j];
        end
    endtask
    task missing;
        begin
            for(n=0;n<16;n=n+1)frame(0,0,0,0,49500);
            expect_state(4);
            if(dut.retry_step!=0 || dut.retry_center!=0)$fatal(1,"Recovery cursor must restart at fast anchors");
        end
    endtask
    task recover_at(input integer tx,ty,old_x,old_y);
        integer attempts;
        begin
            attempts=0;
            while(status==4 && attempts<32)begin
                frame(tx,ty,1,0,49500);attempts=attempts+1;
                if(dut.cx!=old_x || dut.cy!=old_y)$fatal(1,"Unconfirmed candidate changed reliable position");
            end
            expect_state(6);
            if(reason!=9 || dut.confirm_count!=1)$fatal(1,"Candidate bypassed verification");
            frame(tx,ty,1,0,49500);expect_state(6);
            frame(tx,ty,1,0,49500);expect_state(2);
            if(reason!=10 || cx!=tx || cy!=ty || dut.retry_step!=0)$fatal(1,"Expanded recovery failed at %0d,%0d",tx,ty);
            for(j=0;j<64;j=j+1)if(dut.template_mem[j]!==frozen[j])$fatal(1,"Template changed during expanded search");
        end
    endtask
    initial begin
        directions_x[0]=1;directions_y[0]=0;directions_x[1]=-1;directions_y[1]=0;
        directions_x[2]=0;directions_y[2]=1;directions_x[3]=0;directions_y[3]=-1;
        directions_x[4]=1;directions_y[4]=1;directions_x[5]=-1;directions_y[5]=1;
        directions_x[6]=1;directions_y[6]=-1;directions_x[7]=-1;directions_y[7]=-1;
        learn();missing();check_sweep=1;
        for(k=0;k<64;k=k+1)begin expected_slot=k;frame(0,0,0,0,49500);expect_state(4);end
        check_sweep=0;
        for(d=0;d<8;d=d+1)begin
            learn();missing();recover_at(W/2+24*directions_x[d],H/2+24*directions_y[d],W/2,H/2);
        end
        learn();
        for(k=1;k<=6;k=k+1)frame(W/2+k*8,H/2,1,0,49500);
        missing();recover_at(120,H/2,144,H/2); // Last position and central anchor differ.
        learn();missing();
        for(k=0;k<40;k=k+1)begin frame(160,H/2,1,0,49500);expect_state(4);end // Outside all neighbourhoods.
        for(k=0;k<40;k=k+1)begin frame(120,H/2,1,1,49500);expect_state(4);end // Wrong appearance.
        // One expanded candidate cannot relock, even when it disappears again.
        k=0;while(status==4 && k<32)begin frame(120,H/2,1,0,49500);k=k+1;end
        expect_state(6);frame(0,0,0,0,49500);expect_state(4);
        if(dut.confirm_count!=0)$fatal(1,"Flash retained confirmation");
        recover_at(120,H/2,W/2,H/2);
        // VERIFY is local to the candidate; incomplete and deadline-aborted
        // samples must not count toward the three complete matching frames.
        missing();k=0;while(status==4 && k<32)begin frame(96,H/2,1,0,49500);k=k+1;end
        expect_state(6);drop_pixel=1;frame(96,H/2,1,0,49500);drop_pixel=0;expect_state(4);
        if(reason!=4 || dut.confirm_count!=0)$fatal(1,"Incomplete expanded confirmation accepted");
        frame(96,H/2,1,0,5);@(negedge clk);de=1;x=0;y=0;idle(5);expect_state(4);
        if(reason!=5 || !dut.template_valid || dut.confirm_count!=0)$fatal(1,"Deadline did not reset expanded confirmation");
        recover_at(96,H/2,120,H/2); // Fast central revisit still works.
        @(negedge clk);command=1;idle(1);expect_state(0);
        for(k=0;k<4;k=k+1)frame(120,H/2,1,0,49500);
        expect_state(0);if(dut.template_valid)$fatal(1,"Cancel failed");
        learn();
        for(k=1;k<=8;k=k+1)frame(96-k*8,k<=6 ? 80-k*8 : 32,1,0,49500);
        expect_state(2);if(cx!=32 || cy!=32)$fatal(1,"Top-left reliable position failed");
        missing();recover_at(56,56,32,32);
        learn();
        for(k=1;k<=8;k=k+1)frame(96+k*8,k<=6 ? 80+k*8 : 128,1,0,49500);
        expect_state(2);if(cx!=160 || cy!=128)$fatal(1,"Bottom-right reliable position failed");
        missing();recover_at(136,104,160,128);
        @(negedge clk);command=1;idle(1); // Cancel old target.
        @(negedge clk);command=1;idle(1); // Explicitly learn repeated texture.
        frame(W/2,H/2,1,2,49500);expect_state(2);
        for(k=0;k<16;k=k+1)frame(W/2,H/2,1,2,49500);
        expect_state(4);
        for(k=0;k<40;k=k+1)begin frame(W/2,H/2,1,2,49500);expect_state(4);end
        if(reason!=3)$fatal(1,"Expanded sweep must reject non-unique repeated texture");
        if(max_work_cycles>=14000)$fatal(1,"Expanded scan exceeded single-frame budget");
        $display("PASS expanded reacquire: %0d frames %0d checks; 32-window schedule/wrap, eight directions, distinct anchors, frozen template, 3-frame verification, distractors/flash/outside/cancel; max cycles=%0d",frames,checks,max_work_cycles);
        $finish;
    end
    initial begin #1000000000;$fatal(1,"Expanded reacquire timeout");end
endmodule
