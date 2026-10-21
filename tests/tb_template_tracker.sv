`timescale 1ns/1ps
module tb_template_tracker;
    localparam W=160,H=144;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,command=0,de=0;
    reg [10:0] x=0,y=0;
    reg [7:0] luma=0;
    wire [2:0] status;
    wire [10:0] cx,cy;
    wire busy;
    integer checks=0,frames=0,xx,yy,n;
    hx_template_tracker_legacy #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H)) dut (
        .clk(clk),.rst_n(rst),.command(command),.de(de),.x(x),.y(y),.luma(luma),
        .status(status),.center_x(cx),.center_y(cy),.busy(busy),
        .debug_reason(),.debug_best(),.debug_margin(),.debug_misses()
    );
    function integer texture(input integer a,b);
        integer z;
        begin z=(a*73+b*151+a*b*37+19)%128;texture=64+z;end
    endfunction
    task idle(input integer count);
        integer k;
        begin for(k=0;k<count;k=k+1)begin @(negedge clk);de=0;command=0;end end
    endtask
    task toggle;
        begin @(negedge clk);command=1;@(negedge clk);command=0;end
    endtask
    // kind 0=target, 1=flat, 2=missing, 3=ambiguous tiled texture.
    task frame(input integer dx,dy,brightness,kind,blank);
        integer a,b,v;
        begin
            frames=frames+1;
            for(yy=0;yy<H;yy=yy+1)begin
                for(xx=0;xx<W;xx=xx+1)begin
                    @(negedge clk);de=1;x=xx;y=yy;
                    a=xx/8-(6+dx/8);b=yy/8-(5+dy/8);
                    v=32+brightness;
                    if(kind==0 && a>=0 && a<8 && b>=0 && b<8)v=texture(a,b)+brightness;
                    if(kind==3)v=texture((xx/8-4)&7,(yy/8-2)&7)+brightness;
                    luma=v;
                end
                idle(20);
            end
            idle(blank);
        end
    endtask
    task expect_state(input integer st,ex,ey);
        begin
            #1;checks=checks+1;
            if(status!==st || cx!==ex || cy!==ey || busy)
                $fatal(1,"frame %0d: state=%0d center=%0d,%0d busy=%b expected %0d at %0d,%0d",frames,status,cx,cy,busy,st,ex,ey);
        end
    endtask
    initial begin
        idle(5);rst=1;idle(5);expect_state(0,80,72);
        toggle();frame(0,0,0,1,40000);expect_state(5,80,72); // Uniform target rejected.
        if(dut.debug_reason!=6)$fatal(1,"Flat diagnostic missing");
        toggle();frame(0,0,0,0,40000);expect_state(2,80,72);
        frame(16,-8,20,0,40000);expect_state(2,96,64); // Translation plus brightness step.
        frame(24,8,10,0,40000);expect_state(2,104,80);
        frame(0,0,0,3,40000);expect_state(3,104,80); // Equal best matches must not jump.
        if(dut.debug_reason!=3)$fatal(1,"Ambiguity diagnostic missing");
        frame(24,8,0,0,40000);expect_state(2,104,80);
        for(n=0;n<64;n=n+1)if(dut.template_mem[n]!==texture(n%8,n/8))$fatal(1,"Frozen template drifted");
        for(n=0;n<16;n=n+1)begin
            frame(0,0,0,2,40000);
            expect_state(n==15 ? 4 : 3,104,80);
        end
        toggle();frame(0,0,0,0,40000);expect_state(2,80,72); // Explicit centre reselection.
        frame(-16,-16,0,0,40000);expect_state(2,64,56);
        frame(-32,-32,0,0,40000);expect_state(2,48,40);
        frame(-48,-40,0,0,40000);expect_state(2,32,32);
        frame(-48,-40,0,0,40000);expect_state(2,32,32); // Tile includes first pixel (0,0).
        frame(-16,-8,0,0,40000);expect_state(2,64,64);
        frame(16,24,0,0,40000);expect_state(2,96,96);
        frame(48,40,0,0,40000);expect_state(2,128,112);
        frame(48,40,0,0,40000);expect_state(2,128,112); // Right/bottom clamp and repeated edge capture.
        toggle();expect_state(0,80,72); // Cancel resets to centre selection, not stale lock.
        toggle();frame(0,0,0,0,40000);expect_state(2,80,72);
        frame(48,0,0,0,40000);expect_state(3,80,72); // Outside local search range.
        frame(0,0,0,0,40000);expect_state(2,80,72);
        frame(0,0,0,0,5); // Deliberately violate vertical blanking budget.
        @(negedge clk);de=1;x=0;y=0;luma=0;
        idle(10);expect_state(3,80,72);
        frame(0,0,0,0,40000);expect_state(2,80,72);
        rst=0;idle(5);rst=1;idle(5);expect_state(0,80,72);
        $display("PASS template tracker: %0d frames %0d checks; texture rejection, local translation, brightness offset, ambiguity, HOLD16/LOST, borders, reselection, deadline, reset",frames,checks);
        $finish;
    end
    initial begin #100000000; $fatal(1,"Timeout");end
endmodule

// Characterize pixel-scale motion that the original 8-pixel-block tests omit.
module tb_template_diagnostics;
    localparam W=160,H=144;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,command=0,de=0;
    reg [10:0] x=0,y=0;
    reg [7:0] luma=0;
    wire [2:0] status;
    wire [3:0] reason;
    wire [14:0] best,margin;
    wire [4:0] misses;
    integer xx,yy,k,d,n,v,scene=0,motion_y=0;
    reg drop_pixel=0;
    integer work_cycles=0,max_work_cycles=0;
    hx_template_tracker #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),.AUTO_REACQUIRE(0)) dut (
        .clk(clk),.rst_n(rst),.command(command),.de(de),.x(x),.y(y),.luma(luma),
        .status(status),.center_x(),.center_y(),.busy(),
        .debug_reason(reason),.debug_best(best),.debug_margin(margin),.debug_misses(misses)
    );
    always @(posedge clk)begin
        if(!rst)work_cycles=0;
        else if(dut.busy)begin
            work_cycles=work_cycles+1;
            if(work_cycles>max_work_cycles)max_work_cycles=work_cycles;
        end else work_cycles=0;
    end
    function integer pattern(input integer a,b);
        integer p,q;
        begin
            p=(a*3+b+2048)%47;q=(b*2-a+2048)%37;
            if(p>23)p=46-p;
            if(q>18)q=36-q;
            pattern=40+4*p+3*q;
        end
    endfunction
    task idle(input integer cycles);
        begin repeat(cycles)begin @(negedge clk);de=0;command=0;end end
    endtask
    task frame(input integer dx,offset,gain,noise,blank);
        begin
            for(yy=0;yy<H;yy=yy+1)begin
                for(xx=0;xx<W;xx=xx+1)begin
                    @(negedge clk);de=1;x=xx;y=yy;
                    v=pattern(xx-dx,yy-motion_y)*gain/100+offset;
                    if(scene==1)v=60+120*((xx/8+yy/8)%2);
                    if(scene==2)v=96;
                    if(drop_pixel && xx==80 && yy==72)de=0;
                    if(noise!=0)v=v+((xx*13+yy*7)%9-4);
                    luma=v>255 ? 255 : v<0 ? 0 : v;
                end
                idle(20);
            end
            idle(blank);
        end
    endtask
    task learn;
        begin
            rst=0;idle(4);rst=1;idle(4);
            @(negedge clk);command=1;idle(1);
            frame(0,0,100,0,49500);
            if(status!=2 || reason!=8)$fatal(1,"Learning must be distinguished from a verified match");
        end
    endtask
    initial begin
        scene=2;rst=0;idle(4);rst=1;idle(4);
        @(negedge clk);command=1;idle(1);frame(0,0,100,0,49500);
        if(status!=5 || reason!=6)$fatal(1,"Uniform template must reject acquisition");
        scene=0;
        learn();frame(0,0,100,0,49500);
        if(status!=2 || best!=0 || reason!=1)$fatal(1,"Static self-match failed");
        frame(0,20,100,0,49500);
        if(status!=2 || reason!=1)$fatal(1,"Additive brightness match failed");
        frame(0,0,100,1,49500);
        if(status!=2 || reason!=1)$fatal(1,"Small deterministic noise failed");
        for(d=1;d<=8;d=d+1)begin
            learn();frame(d,0,100,0,49500);
            $display("DIAG pixel shift=%0d status=%0d reason=%0d best=%0d margin=%0d coarse=%0d,%0d center=%0d,%0d",d,status,reason,best,margin,dut.coarse_x,dut.coarse_y,dut.cx,dut.cy);
            if(status!=2 || reason!=1 || best!=0 || dut.cx!=80+d || dut.cy!=72)
                $fatal(1,"Fine search failed exact pixel shift %0d",d);
        end
        learn();
        for(d=1;d<=8;d=d+1)begin
            motion_y=d;frame(d,0,100,0,49500);
            if(status!=2 || dut.cx!=80+d || dut.cy!=72+d)$fatal(1,"Diagonal phase %0d failed",d);
        end
        for(d=7;d>=-8;d=d-1)begin
            motion_y=d;frame(d,0,100,0,49500);
            if(status!=2 || dut.cx!=80+d || dut.cy!=72+d)$fatal(1,"Reverse diagonal phase %0d failed",d);
        end
        motion_y=0;
        learn();frame(0,0,140,0,49500);
        $display("DIAG gain=140%% status=%0d reason=%0d best=%0d margin=%0d",status,reason,best,margin);
        learn();
        for(n=0;n<16;n=n+1)begin
            frame(4,0,100,0,49500);
            if(status!=2 || reason!=1)$fatal(1,"Fixed 4-pixel motion regressed to LOST");
        end
        for(d=5;d<=40;d=d+1)begin
            frame(d,0,100,0,49500);
            if(status!=2 || dut.cx!=80+d)$fatal(1,"Slow motion failed at %0d",d);
        end
        for(d=39;d>=-48;d=d-1)begin
            frame(d,0,100,0,49500);
            if(status!=2 || dut.cx!=80+d)$fatal(1,"Reverse/border motion failed at %0d",d);
        end
        for(d=-47;d<=48;d=d+1)begin
            frame(d,0,100,0,49500);
            if(status!=2 || dut.cx!=80+d)$fatal(1,"Right border motion failed at %0d",d);
        end
        learn();drop_pixel=1;frame(0,0,100,0,49500);drop_pixel=0;
        if(status!=3 || reason!=4)$fatal(1,"Incomplete dense tile not rejected");
        frame(0,0,100,0,49500);
        if(status!=2)$fatal(1,"Recovery during HOLD failed");
        for(n=0;n<16;n=n+1)frame(0,32,0,0,49500);
        if(status!=4 || reason!=2)$fatal(1,"Missing target must reach LOST");
        frame(0,0,100,0,49500);
        if(status!=4)$fatal(1,"LOST must not silently relearn background");
        learn();frame(0,0,100,0,49500);
        if(status!=2)$fatal(1,"Explicit reselection failed");
        scene=1;learn();frame(0,0,100,0,49500);
        if(status!=3 || reason!=3)$fatal(1,"Repeated texture must remain ambiguous");
        scene=0;
        learn();frame(0,0,100,0,5);
        @(negedge clk);de=1;x=0;y=0;
        idle(5);
        if(status!=3 || reason!=5)$fatal(1,"Deadline failure not separately identified");
        if(max_work_cycles>=14000)$fatal(1,"Fine search exceeded pipelined budget: %0d",max_work_cycles);
        $display("DIAG max work cycles=%0d (<14000, nominal 720p blanking 49500)",max_work_cycles);
        $display("PASS fine template diagnostics: static/noise/offset, all pixel phases, sustained shift, slow movement/borders, missing/ambiguous/incomplete targets, HOLD recovery, LOST/reselection, deadline");
        $finish;
    end
    initial begin #400000000; $fatal(1,"Diagnostic timeout");end
endmodule
