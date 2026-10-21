`timescale 1ns/1ps
// Frozen 8x8 luma template, 8-pixel sampling pitch, 9x9 local ZM-SAD search.
// Only a 16x16 search tile is retained; no full frame or DDR access.
module hx_template_tracker_legacy #(
    parameter integer IMAGE_WIDTH=1280, IMAGE_HEIGHT=720,
    parameter integer HOLD_FRAMES=16,
    parameter integer MAX_MEAN_ERROR=12, MIN_UNIQUENESS=64,
    parameter integer MIN_TEXTURE=384
) (
    input wire clk,rst_n,command,
    input wire de,
    input wire [10:0] x,y,
    input wire [7:0] luma,
    output reg [2:0] status,
    output wire [10:0] center_x,center_y,
    output wire busy,
    // Last completed decision, retained in LOST for diagnosis. No threshold changes.
    // 0=waiting, 1=accepted, 2=error, 3=ambiguous, 4=incomplete,
    // 5=deadline, 6=flat, 7=cancelled, 8=template learned (not yet matched).
    output reg [3:0] debug_reason,
    output reg [14:0] debug_best,debug_margin,
    output wire [4:0] debug_misses
);
    localparam READY=0, LEARN=1, TRACK=2, HOLD=3, LOST=4, FLAT=5;
    localparam P_IDLE=0, P_ISSUE=1, P_WAIT=2, P_ACC=3, P_NEXT=4, P_FINISH=5;
    localparam J_LEARN=0,J_MEAN=1,J_SCORE=2;
    reg [3:0] phase;
    reg [1:0] job;
    reg [7:0] cx,cy,roi_x,roi_y;
    reg armed,template_valid,collect,learn_frame;
    reg [4:0] misses;
    reg [6:0] learn_count;
    reg [8:0] patch_count;
    reg [13:0] learn_sum,mean_sum;
    reg [7:0] learn_min,learn_max,template_mean,candidate_mean;
    reg [7:0] template_mem[0:63],patch_mem[0:255];
    reg [5:0] template_addr,sample;
    reg [7:0] patch_addr,template_q,patch_q;
    reg [3:0] candidate_x,candidate_y;
    reg [14:0] score_sum,best,second_best;
    reg [7:0] best_x,best_y;
    wire frame_start=de && x==0 && y==0;
    wire frame_end=de && x==IMAGE_WIDTH-1 && y==IMAGE_HEIGHT-1;
    // Sample inside each cell: x/y>=2 guarantees the shared 3x3 Gaussian
    // window contains this frame's pixels, including tiles touching (0,0).
    wire sampled=de && x[2:0]==2 && y[2:0]==2;
    wire [7:0] cell_x=x[10:3],cell_y=y[10:3];
    wire [7:0] next_roi_x=(cx<8) ? 8'd0 : (cx>IMAGE_WIDTH/8-8) ? IMAGE_WIDTH/8-16 : cx-8;
    wire [7:0] next_roi_y=(cy<8) ? 8'd0 : (cy>IMAGE_HEIGHT/8-8) ? IMAGE_HEIGHT/8-16 : cy-8;
    wire [7:0] rx=frame_start ? next_roi_x : roi_x;
    wire [7:0] ry=frame_start ? next_roi_y : roi_y;
    wire [7:0] tile_x=cell_x-rx,tile_y=cell_y-ry;
    wire take_patch=sampled && !busy && (frame_start ? template_valid : collect) &&
        cell_x>=rx && cell_x<rx+16 && cell_y>=ry && cell_y<ry+16;
    wire take_learn=sampled && learn_frame &&
        cell_x>=IMAGE_WIDTH/16-4 && cell_x<IMAGE_WIDTH/16+4 &&
        cell_y>=IMAGE_HEIGHT/16-4 && cell_y<IMAGE_HEIGHT/16+4;
    wire [7:0] lx=cell_x-(IMAGE_WIDTH/16-4),ly=cell_y-(IMAGE_HEIGHT/16-4);
    wire [3:0] read_x=candidate_x+{1'b0,sample[2:0]};
    wire [3:0] read_y=candidate_y+{1'b0,sample[5:3]};
    wire signed [9:0] difference = job==J_LEARN ?
        $signed({2'b0,template_q})-$signed({2'b0,template_mean}) :
        $signed({2'b0,patch_q})-$signed({2'b0,candidate_mean})-
        $signed({2'b0,template_q})+$signed({2'b0,template_mean});
    wire [9:0] error_value=difference[9] ? $unsigned(-difference) : $unsigned(difference);
    wire [14:0] score_next=score_sum+{5'd0,error_value};
    wire [13:0] mean_next=mean_sum+{6'd0,patch_q};
    assign busy=phase!=P_IDLE;
    assign center_x={cx,3'b000};
    assign center_y={cy,3'b000};
    assign debug_misses=misses;

    // Synchronous read ports: ISSUE -> WAIT -> ACC provides a full clock for
    // each memory read and a separate full clock for the arithmetic.
    always @(posedge clk) begin
        template_q<=template_mem[template_addr];
        patch_q<=patch_mem[patch_addr];
        if(rst_n && take_learn)template_mem[{ly[2:0],lx[2:0]}]<=luma;
        if(rst_n && take_patch)patch_mem[{tile_y[3:0],tile_x[3:0]}]<=luma;
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            status<=READY;phase<=P_IDLE;job<=J_LEARN;
            cx<=IMAGE_WIDTH/16;cy<=IMAGE_HEIGHT/16;roi_x<=0;roi_y<=0;
            armed<=0;template_valid<=0;collect<=0;learn_frame<=0;misses<=0;
            learn_count<=0;patch_count<=0;learn_sum<=0;mean_sum<=0;
            learn_min<=255;learn_max<=0;template_mean<=0;candidate_mean<=0;
            template_addr<=0;patch_addr<=0;sample<=0;candidate_x<=0;candidate_y<=0;
            score_sum<=0;best<=32767;second_best<=32767;best_x<=0;best_y<=0;
            debug_reason<=0;debug_best<=32767;debug_margin<=0;
        end else if(command) begin
            phase<=P_IDLE;collect<=0;learn_frame<=0;template_valid<=0;misses<=0;
            cx<=IMAGE_WIDTH/16;cy<=IMAGE_HEIGHT/16;
            debug_reason<=(status==READY || status==LOST || status==FLAT) ? 0 : 7;
            debug_best<=32767;debug_margin<=0;
            if(status==READY || status==LOST || status==FLAT)begin armed<=1;status<=LEARN;end
            else begin armed<=0;status<=READY;end
        end else if(frame_start && busy) begin
            // Reject a missed blanking deadline; never match a tile while the
            // next frame overwrites it. No late/stale position publication.
            phase<=P_IDLE;collect<=0;learn_frame<=0;
            debug_reason<=5;
            if(job==J_LEARN)begin status<=FLAT;template_valid<=0;end
            else if(misses>=HOLD_FRAMES-1)begin status<=LOST;template_valid<=0;end
            else begin status<=HOLD;misses<=misses+1'b1;end
        end else begin
            if(frame_start)begin
                roi_x<=next_roi_x;roi_y<=next_roi_y;
                collect<=template_valid;learn_frame<=armed;armed<=0;
                learn_count<=0;patch_count<=0;learn_sum<=0;learn_min<=255;learn_max<=0;
            end
            if(take_patch)patch_count<=frame_start ? 9'd1 : patch_count+1'b1;
            if(take_learn)begin
                learn_count<=learn_count+1'b1;learn_sum<=learn_sum+{6'd0,luma};
                if(luma<learn_min)learn_min<=luma;
                if(luma>learn_max)learn_max<=luma;
            end
            if(frame_end)begin
                collect<=0;learn_frame<=0;
                if(learn_frame)begin
                    if(learn_count==64)begin
                        template_mean<=learn_sum[13:6];job<=J_LEARN;sample<=0;score_sum<=0;phase<=P_ISSUE;
                    end else begin status<=FLAT;template_valid<=0;debug_reason<=4;end
                end else if(collect)begin
                    if(patch_count==256)begin
                        candidate_x<=0;candidate_y<=0;sample<=0;mean_sum<=0;score_sum<=0;
                        best<=32767;second_best<=32767;job<=J_MEAN;phase<=P_ISSUE;
                    end else begin
                        debug_reason<=4;
                        if(misses>=HOLD_FRAMES-1)begin status<=LOST;template_valid<=0;end
                        else begin status<=HOLD;misses<=misses+1'b1;end
                    end
                end
            end
            case(phase)
                P_ISSUE:begin template_addr<=sample;patch_addr<={read_y,read_x};phase<=P_WAIT;end
                P_WAIT:phase<=P_ACC;
                P_ACC:begin
                    if(job==J_MEAN)begin
                        mean_sum<=mean_next;
                        if(sample==63)begin candidate_mean<=mean_next[13:6];sample<=0;score_sum<=0;job<=J_SCORE;phase<=P_ISSUE;end
                        else begin sample<=sample+1'b1;phase<=P_ISSUE;end
                    end else begin
                        score_sum<=score_next;
                        if(sample!=63)begin sample<=sample+1'b1;phase<=P_ISSUE;end
                        else if(job==J_LEARN)begin
                            phase<=P_IDLE;
                            if(learn_max-learn_min<24 || score_next<MIN_TEXTURE)begin status<=FLAT;template_valid<=0;debug_reason<=6;end
                            else begin status<=TRACK;template_valid<=1;misses<=0;debug_reason<=8;end
                        end else begin
                            if(score_next<best)begin
                                second_best<=best;best<=score_next;
                                best_x<=roi_x+candidate_x+4;best_y<=roi_y+candidate_y+4;
                            end else if(score_next<second_best)second_best<=score_next;
                            phase<=P_NEXT;
                        end
                    end
                end
                P_NEXT:begin
                    if(candidate_x==8 && candidate_y==8)phase<=P_FINISH;
                    else begin
                        if(candidate_x==8)begin candidate_x<=0;candidate_y<=candidate_y+1'b1;end
                        else candidate_x<=candidate_x+1'b1;
                        job<=J_MEAN;mean_sum<=0;score_sum<=0;sample<=0;phase<=P_ISSUE;
                    end
                end
                P_FINISH:begin
                    phase<=P_IDLE;
                    debug_best<=best;debug_margin<=second_best-best;
                    debug_reason<=best>MAX_MEAN_ERROR*64 ? 2 :
                        ({1'b0,second_best}<{1'b0,best}+MIN_UNIQUENESS) ? 3 : 1;
                    if(best<=MAX_MEAN_ERROR*64 && {1'b0,second_best}>={1'b0,best}+MIN_UNIQUENESS)begin
                        cx<=best_x;cy<=best_y;status<=TRACK;misses<=0;
                    end else if(misses>=HOLD_FRAMES-1)begin status<=LOST;template_valid<=0;end
                    else begin status<=HOLD;misses<=misses+1'b1;end
                end
                default:begin end
            endcase
        end
    end
endmodule
