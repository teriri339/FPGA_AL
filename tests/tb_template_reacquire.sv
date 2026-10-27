`timescale 1ns/1ps
module tb_template_reacquire;
    localparam W=320,H=192;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,command=0,de=0;
    reg [10:0] x=0,y=0;
    reg [7:0] luma=0;
    wire [2:0] status;
    wire [10:0] cx,cy;
    wire [3:0] reason;
    integer xx,yy,k,n,v,a,b,frames=0,checks=0,work_cycles=0,max_work_cycles=0;
    reg [7:0] frozen[0:63];
    reg drop_pixel=0;
    // DISP_SMOOTH_SHIFT/DEADBAND=0：关闭显示框平滑，center_x 严格等于跟踪中心，
    // 本用例断言的是跟踪精度而非 OSD 观感。
    hx_template_tracker #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),.EXPANDED_REACQUIRE(0),.FAR_REACQUIRE(0),.GLOBAL_REACQUIRE(0),.FAST_REACQUIRE(0),
        .DISP_SMOOTH_SHIFT(0),.DISP_DEADBAND(0)) dut (
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
            if(p>23)p=46-p;
            if(q>18)q=36-q;
            texture=40+4*p+3*q;
            if(kind==1)texture=240-texture;
        end
    endfunction
    task idle(input integer cycles);
        begin repeat(cycles)begin @(negedge clk);de=0;command=0;end end
    endtask
    task toggle;
        begin @(negedge clk);command=1;idle(1);end
    endtask
    task frame(input integer tx,ty,present,kind,blank);
        begin
            frames=frames+1;
            for(yy=0;yy<H;yy=yy+1)begin
                for(xx=0;xx<W;xx=xx+1)begin
                    @(negedge clk);de=1;x=xx;y=yy;v=24;
                    a=xx-(tx-32);b=yy-(ty-32);
                    if(present && a>=0 && a<64 && b>=0 && b<64)v=texture(a,b,kind);
                    if(drop_pixel && xx==tx && yy==ty)de=0;
                    luma=v;
                end
                idle(20);
            end
            idle(blank);
        end
    endtask
    task expect_state(input integer st);
        begin checks=checks+1;if(status!==st)$fatal(1,"frame %0d status=%0d R=%0d expected=%0d count=%0d",frames,status,reason,st,dut.confirm_count);end
    endtask
    task missing;
        begin
            for(n=0;n<16;n=n+1)frame(0,0,0,0,49500);
            expect_state(4);
            if(!dut.template_valid || dut.confirm_count!=0)$fatal(1,"LOST must retain frozen template and clear confirmation");
        end
    endtask
    task check_frozen;
        begin
            for(k=0;k<64;k=k+1)if(dut.template_mem[k]!==frozen[k])$fatal(1,"Reacquisition changed template at %0d",k);
        end
    endtask
    initial begin
        idle(4);rst=1;idle(4);toggle();frame(160,96,1,0,49500);expect_state(2);
        frame(160,96,1,0,49500);expect_state(2);
        for(k=0;k<64;k=k+1)frozen[k]=dut.template_mem[k];
        for(k=1;k<=10;k=k+1)frame(160+k*8,96,1,0,49500);
        expect_state(2);if(cx!=240 || cy!=96)$fatal(1,"Move to noncentral last position failed");

        missing();check_frozen();
        for(k=0;k<8;k=k+1)begin frame(80,96,1,0,49500);expect_state(4);end
        check_frozen(); // Correct target elsewhere is outside this fast-recovery scope.
        frame(240,96,1,0,49500);expect_state(6);
        if(dut.cx!=240 || reason!=9 || dut.confirm_count!=1)$fatal(1,"First recovery candidate not pending");
        frame(240,96,1,0,49500);expect_state(6);
        frame(240,96,1,0,49500);expect_state(2);
        if(reason!=10 || cx!=240)$fatal(1,"Three-frame last-position recovery failed");

        missing();
        frame(160,96,1,0,49500);expect_state(4); // last window misses, central window next
        frame(160,96,1,0,49500);expect_state(6);
        if(dut.cx!=240 || cx!=160)$fatal(1,"Pending box must not overwrite last reliable position");
        frame(160,96,1,0,49500);expect_state(6);
        frame(160,96,1,0,49500);expect_state(2);
        if(cx!=160 || reason!=10)$fatal(1,"Central-window recovery failed");
        check_frozen();

        missing();frame(160,96,1,0,49500);expect_state(6);
        frame(0,0,0,0,49500);expect_state(4); // one-frame flash cannot relock
        if(dut.confirm_count!=0)$fatal(1,"Interrupted confirmation was retained");
        for(k=0;k<5;k=k+1)begin frame(160,96,1,1,49500);expect_state(4);end
        frame(160,96,1,0,49500);expect_state(6);
        frame(161,97,1,0,49500);expect_state(6);
        frame(162,98,1,0,49500);expect_state(2);
        if(cx!=162 || cy!=98)$fatal(1,"Slow movement during confirmation failed");
        check_frozen();

        missing();frame(160,96,1,0,49500);expect_state(6);
        drop_pixel=1;frame(160,96,1,0,49500);drop_pixel=0;expect_state(4);
        if(reason!=4 || dut.confirm_count!=0)$fatal(1,"Incomplete candidate must reset confirmation");
        frame(160,96,1,0,5);@(negedge clk);de=1;x=0;y=0;idle(5);expect_state(4);
        if(reason!=5 || !dut.template_valid)$fatal(1,"Timeout must retain original template without accepting candidate");
        check_frozen();
        frame(160,96,1,0,49500);expect_state(6);
        frame(160,96,1,0,49500);expect_state(6);
        frame(160,96,1,0,49500);expect_state(2);
        if(reason!=10)$fatal(1,"Automatic recovery after deadline failed");
        missing();

        toggle();frame(160,96,1,1,49500);expect_state(2); // manual override may learn a new target
        if(dut.template_mem[0]===frozen[0])$fatal(1,"Manual reselection did not replace template");
        toggle();expect_state(0); // explicit cancel must disable automatic recovery
        for(k=0;k<4;k=k+1)frame(160,96,1,1,49500);
        expect_state(0);if(dut.template_valid)$fatal(1,"Cancelled tracker reacquired");
        if(max_work_cycles>=14000)$fatal(1,"Reacquisition exceeded pipelined budget");
        $display("PASS template reacquire: %0d frames %0d checks, last/central search, 3-frame confirmation, frozen template, distractors, flash/missing/incomplete/timeout, manual override/cancel, max cycles=%0d",frames,checks,max_work_cycles);
        $finish;
    end
    initial begin #400000000;$fatal(1,"Reacquisition test timeout");end
endmodule
