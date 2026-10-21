`timescale 1ns/1ps
module tb_coarse_720p;
    localparam W=1280,H=720;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,de=0,learn=0,accepted=0,search=0;
    reg [10:0] x=0,y=0;reg [7:0] luma=0;
    wire valid;wire [10:0] px,py;
    integer xx,yy,a,b,k,frames=0,scan_cycles=0,jobs=0,max_cycles=0,all_cycles=0,first_proposal=0;
    hx_template_coarse_proposer dut(.clk(clk),.rst_n(rst),.command(1'b0),.de(de),.x(x),.y(y),.luma(luma),
        .learn_start(learn),.template_accepted(accepted),.search_allowed(search),.proposal_ack(1'b0),
        .proposal_valid(valid),.proposal_x(px),.proposal_y(py));
    always @(posedge clk)begin
        if(rst)begin
            all_cycles=all_cycles+1;
            if(dut.phase>=4)begin scan_cycles=scan_cycles+1;if(scan_cycles>max_cycles)max_cycles=scan_cycles;end
            else scan_cycles=0;
            if(dut.phase==7)jobs=jobs+1;
            if(valid && first_proposal==0)first_proposal=all_cycles;
        end
    end
    task idle(input integer n);begin repeat(n)begin @(negedge clk);de=0;end end endtask
    task frame(input integer tx,ty);
        begin
            frames=frames+1;
            for(yy=0;yy<H;yy=yy+1)begin
                for(xx=0;xx<W;xx=xx+1)begin
                    @(negedge clk);de=1;x=xx;y=yy;luma=24;
                    a=xx-tx+32;b=yy-ty+32;
                    if(a>=0 && a<64 && b>=0 && b<64)luma=64+(a/8*73+b/8*151+a/8*(b/8)*37+19)%128;
                end
                idle(370);
            end
            idle(49500);
        end
    endtask
    initial begin
        idle(4);rst=1;idle(4);learn=1;frame(640,360);learn=0;accepted=1;
        if(!dut.tpl_ok)$fatal(1,"720p coarse template rejected");
        search=1;
        for(k=0;k<24 && !valid;k=k+1)frame(1120,560);
        if(!valid || px!=1120 || py!=560)$fatal(1,"720p coarse proposal mismatch %0d,%0d",px,py);
        if(jobs!=50325 || max_cycles!=19375126)$fatal(1,"720p scan coverage/budget jobs=%0d cycles=%0d",jobs,max_cycles);
        if(first_proposal>24*1237500)$fatal(1,"720p proposal took too many frames");
        $display("PASS 720p coarse: %0d full frames at 1650x750 clocks; 50325 candidates, %0d scan clocks (~260.94ms at 74.25MHz), exact far proposal %0d,%0d; first proposal cycle=%0d",frames,max_cycles,px,py,first_proposal);
        $finish;
    end
    initial begin #(64'd400000000);$fatal(1,"720p coarse timeout");end
endmodule
