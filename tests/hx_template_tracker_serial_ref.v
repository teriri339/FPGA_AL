`timescale 1ns/1ps

// Dense local tile, stride-2 search + stride-1 refinement. No DDR access.
module hx_template_tracker_serial_ref #(
    parameter integer IMAGE_WIDTH=1280,IMAGE_HEIGHT=720,HOLD_FRAMES=16,
    parameter integer MAX_MEAN_ERROR=12,MIN_UNIQUENESS=64,MIN_TEXTURE=384,
    parameter integer AUTO_REACQUIRE=1,REACQUIRE_CONFIRM_FRAMES=3
) (
    input wire clk,rst_n,command,de,
    input wire [10:0] x,y,
    input wire [7:0] luma,
    output reg [2:0] status,
    output wire [10:0] center_x,center_y,
    output wire busy,
    output reg [3:0] debug_reason,
    output reg [14:0] debug_best,debug_margin,
    output wire [4:0] debug_misses
);
    localparam READY=0,LEARN=1,TRACK=2,HOLD=3,LOST=4,FLAT=5,VERIFY=6;
    localparam IDLE=0,ISSUE=1,WAIT_READ=2,ACC=3,NEXT=4,FINISH=5,
               CHECK_ISSUE=6,CHECK_WAIT=7,CHECK_ACC=8;
    localparam J_LEARN=0,J_MEAN=1,J_SCORE=2;
    reg [3:0] phase;
    reg [1:0] job;
    reg [10:0] cx,cy,roi_x,roi_y,best_x,best_y,coarse_x,coarse_y,second_x,second_y;
    reg armed,template_valid,collect,learn_frame,fine,fine_pass,checking_final;
    reg [4:0] misses;
    reg retry_center;
    reg [3:0] confirm_count;
    reg [10:0] pending_x,pending_y;
    reg [6:0] learn_count,index,check_index;
    reg [12:0] patch_count,patch_addr;
    reg [13:0] learn_sum,mean_sum;
    reg [7:0] learn_min,learn_max,template_mean,candidate_mean;
    reg [7:0] template_mem[0:63],patch_mem[0:6399];
    reg [14:0] coarse_scores[0:80];
    reg [14:0] coarse_q,score_sum,best,second_best;
    reg [14:0] pass_best,first_best;
    reg [10:0] pass_x,pass_y,first_x,first_y;
    reg [5:0] template_addr,sample;
    reg [7:0] template_q,patch_q;
    reg [3:0] candidate_x,candidate_y,check_x,check_y;
    wire frame_start=de && x==0 && y==0;
    wire frame_end=de && x==IMAGE_WIDTH-1 && y==IMAGE_HEIGHT-1;
    wire recovering=AUTO_REACQUIRE && (status==LOST || status==VERIFY);
    wire [10:0] search_x=status==VERIFY ? pending_x :
        (AUTO_REACQUIRE && status==LOST && retry_center) ? IMAGE_WIDTH/2 : cx;
    wire [10:0] search_y=status==VERIFY ? pending_y :
        (AUTO_REACQUIRE && status==LOST && retry_center) ? IMAGE_HEIGHT/2 : cy;
    wire [10:0] next_roi_x=search_x<40 ? 11'd0 : search_x>IMAGE_WIDTH-40 ? IMAGE_WIDTH-80 : search_x-40;
    wire [10:0] next_roi_y=search_y<40 ? 11'd0 : search_y>IMAGE_HEIGHT-40 ? IMAGE_HEIGHT-80 : search_y-40;
    wire [10:0] rx=frame_start ? next_roi_x : roi_x,ry=frame_start ? next_roi_y : roi_y;
    wire [10:0] tile_x=x-rx,tile_y=y-ry;
    wire take_patch=de && (frame_start ? template_valid : collect) && !busy &&
        x>=rx && x<rx+80 && y>=ry && y<ry+80;
    // Gaussian phase +2 avoids stale causal-window pixels at image borders.
    wire take_learn=de && learn_frame && x>=IMAGE_WIDTH/2-30 && x<IMAGE_WIDTH/2+34 &&
        y>=IMAGE_HEIGHT/2-30 && y<IMAGE_HEIGHT/2+34 &&
        x[2:0]==((IMAGE_WIDTH/2+2)%8) && y[2:0]==((IMAGE_HEIGHT/2+2)%8);
    wire [10:0] lx=x-(IMAGE_WIDTH/2-30),ly=y-(IMAGE_HEIGHT/2-30);
    wire [10:0] cand_cx=fine ? coarse_x-1+candidate_x : roi_x+32+{candidate_x,1'b0};
    wire [10:0] cand_cy=fine ? coarse_y-1+candidate_y : roi_y+32+{candidate_y,1'b0};
    wire candidate_valid=cand_cx>=32 && cand_cx<=IMAGE_WIDTH-32 && cand_cy>=32 && cand_cy<=IMAGE_HEIGHT-32;
    wire [6:0] read_x=cand_cx-30-roi_x+{sample[2:0],3'b000};
    wire [6:0] read_y=cand_cy-30-roi_y+{sample[5:3],3'b000};
    wire [12:0] read_address=({6'd0,read_y}<<6)+({6'd0,read_y}<<4)+read_x;
    wire [12:0] write_address=({6'd0,tile_y[6:0]}<<6)+({6'd0,tile_y[6:0]}<<4)+tile_x[6:0];
    wire signed [9:0] difference=job==J_LEARN ?
        $signed({2'b0,template_q})-$signed({2'b0,template_mean}) :
        $signed({2'b0,patch_q})-$signed({2'b0,candidate_mean})-
        $signed({2'b0,template_q})+$signed({2'b0,template_mean});
    wire [9:0] error_value=difference[9] ? $unsigned(-difference) : $unsigned(difference);
    wire [14:0] score_next=score_sum+{5'd0,error_value};
    wire [13:0] mean_next=mean_sum+{6'd0,patch_q};
    wire [10:0] check_cx=roi_x+32+{check_x,1'b0};
    wire [10:0] check_cy=roi_y+32+{check_y,1'b0};
    // A sparse 8-pixel descriptor has a broad local valley. Nearby positions
    // within six pixels are one peak, not independent look-alike objects.
    // Repeated peaks one sample pitch (8+) apart still reject as ambiguous.
    wire distinct_peak=check_cx+6<best_x || check_cx>best_x+6 || check_cy+6<best_y || check_cy>best_y+6;
    wire fine_peaks_distinct=first_x+6<pass_x || first_x>pass_x+6 || first_y+6<pass_y || first_y>pass_y+6;
    assign busy=phase!=IDLE;
    wire confirmation_consistent=best_x+12>=pending_x && best_x<=pending_x+12 &&
        best_y+12>=pending_y && best_y<=pending_y+12;
    assign center_x=status==VERIFY ? pending_x : cx;
    assign center_y=status==VERIFY ? pending_y : cy;
    assign debug_misses=misses;
    always @(posedge clk)begin
        template_q<=template_mem[template_addr];patch_q<=patch_mem[patch_addr];
        coarse_q<=coarse_scores[check_index];
        if(rst_n && take_learn)template_mem[{ly[5:3],lx[5:3]}]<=luma;
        if(rst_n && take_patch)patch_mem[write_address]<=luma;
        if(rst_n && phase==ACC && job==J_SCORE && sample==63 && !fine)coarse_scores[index]<=score_next;
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            status<=READY;phase<=IDLE;job<=J_LEARN;cx<=IMAGE_WIDTH/2;cy<=IMAGE_HEIGHT/2;
            roi_x<=0;roi_y<=0;coarse_x<=0;coarse_y<=0;best_x<=0;best_y<=0;second_x<=0;second_y<=0;
            armed<=0;template_valid<=0;collect<=0;learn_frame<=0;fine<=0;fine_pass<=0;checking_final<=0;misses<=0;
            retry_center<=0;confirm_count<=0;pending_x<=IMAGE_WIDTH/2;pending_y<=IMAGE_HEIGHT/2;
            learn_count<=0;patch_count<=0;learn_sum<=0;mean_sum<=0;
            learn_min<=255;learn_max<=0;template_mean<=0;candidate_mean<=0;
            template_addr<=0;patch_addr<=0;sample<=0;candidate_x<=0;candidate_y<=0;
            index<=0;check_index<=0;check_x<=0;check_y<=0;score_sum<=0;best<=32767;second_best<=32767;
            pass_best<=32767;first_best<=32767;pass_x<=0;pass_y<=0;first_x<=0;first_y<=0;
            debug_reason<=0;debug_best<=32767;debug_margin<=0;
        end else if(command)begin
            phase<=IDLE;collect<=0;learn_frame<=0;template_valid<=0;misses<=0;
            retry_center<=0;confirm_count<=0;
            cx<=IMAGE_WIDTH/2;cy<=IMAGE_HEIGHT/2;
            debug_reason<=(status==READY || status==LOST || status==FLAT) ? 0 : 7;
            debug_best<=32767;debug_margin<=0;
            if(status==READY || status==LOST || status==FLAT)begin armed<=1;status<=LEARN;end
            else begin armed<=0;status<=READY;end
        end else if(frame_start && busy)begin
            phase<=IDLE;collect<=0;learn_frame<=0;debug_reason<=5;
            if(job==J_LEARN)begin status<=FLAT;template_valid<=0;end
            else if(AUTO_REACQUIRE && (recovering || misses>=HOLD_FRAMES-1))begin
                status<=LOST;confirm_count<=0;retry_center<=recovering ? ~retry_center : 1'b0;
            end
            else if(misses>=HOLD_FRAMES-1)begin status<=LOST;template_valid<=0;end
            else begin status<=HOLD;misses<=misses+1'b1;end
        end else begin
            if(frame_start)begin
                roi_x<=next_roi_x;roi_y<=next_roi_y;collect<=template_valid;learn_frame<=armed;armed<=0;
                learn_count<=0;patch_count<=0;learn_sum<=0;learn_min<=255;learn_max<=0;
            end
            if(take_patch)patch_count<=frame_start ? 13'd1 : patch_count+1'b1;
            if(take_learn)begin
                learn_count<=learn_count+1'b1;learn_sum<=learn_sum+{6'd0,luma};
                if(luma<learn_min)learn_min<=luma;
                if(luma>learn_max)learn_max<=luma;
            end
            if(frame_end)begin
                collect<=0;learn_frame<=0;
                if(learn_frame)begin
                    if(learn_count==64)begin template_mean<=learn_sum[13:6];job<=J_LEARN;sample<=0;score_sum<=0;phase<=ISSUE;end
                    else begin status<=FLAT;template_valid<=0;debug_reason<=4;end
                end else if(collect)begin
                    // Bottom-right ROI includes the last active pixel. Count
                    // that same-cycle write before deciding tile completeness.
                    if(patch_count==6400 || (patch_count==6399 && take_patch))begin
                        candidate_x<=0;candidate_y<=0;sample<=0;mean_sum<=0;score_sum<=0;
                        best<=32767;second_best<=32767;job<=J_MEAN;phase<=ISSUE;fine<=0;index<=0;
                    end else begin
                        debug_reason<=4;
                        if(AUTO_REACQUIRE && (recovering || misses>=HOLD_FRAMES-1))begin
                            status<=LOST;confirm_count<=0;retry_center<=recovering ? ~retry_center : 1'b0;
                        end
                        else if(misses>=HOLD_FRAMES-1)begin status<=LOST;template_valid<=0;end
                        else begin status<=HOLD;misses<=misses+1'b1;end
                    end
                end
            end
            case(phase)
                ISSUE:begin
                    if(job!=J_LEARN && !candidate_valid)phase<=NEXT;
                    else begin template_addr<=sample;patch_addr<=read_address;phase<=WAIT_READ;end
                end
                WAIT_READ:phase<=ACC;
                ACC:begin
                    if(job==J_MEAN)begin
                        mean_sum<=mean_next;
                        if(sample==63)begin candidate_mean<=mean_next[13:6];sample<=0;score_sum<=0;job<=J_SCORE;phase<=ISSUE;end
                        else begin sample<=sample+1'b1;phase<=ISSUE;end
                    end else begin
                        score_sum<=score_next;
                        if(sample!=63)begin sample<=sample+1'b1;phase<=ISSUE;end
                        else if(job==J_LEARN)begin
                            phase<=IDLE;
                            if(learn_max-learn_min<24 || score_next<MIN_TEXTURE)begin status<=FLAT;template_valid<=0;debug_reason<=6;end
                            else begin status<=TRACK;template_valid<=1;misses<=0;debug_reason<=8;end
                        end else begin
                            if(fine && score_next<pass_best)begin pass_best<=score_next;pass_x<=cand_cx;pass_y<=cand_cy;end
                            if(score_next<best)begin
                                if(!fine)begin second_best<=best;second_x<=best_x;second_y<=best_y;end
                                best<=score_next;best_x<=cand_cx;best_y<=cand_cy;
                            end else if(!fine && score_next<second_best)begin
                                second_best<=score_next;second_x<=cand_cx;second_y<=cand_cy;
                            end
                            phase<=NEXT;
                        end
                    end
                end
                NEXT:begin
                    if(candidate_x==(fine ? 2 : 8) && candidate_y==(fine ? 2 : 8))begin
                        if(!fine)begin
                            coarse_x<=best_x;coarse_y<=best_y;
                            check_index<=0;check_x<=0;check_y<=0;second_best<=32767;checking_final<=0;phase<=CHECK_ISSUE;
                        end else if(!fine_pass)begin
                            first_best<=pass_best;first_x<=pass_x;first_y<=pass_y;pass_best<=32767;
                            coarse_x<=second_x;coarse_y<=second_y;fine_pass<=1;candidate_x<=0;candidate_y<=0;
                            sample<=0;mean_sum<=0;score_sum<=0;job<=J_MEAN;phase<=ISSUE;
                        end else begin
                            check_index<=0;check_x<=0;check_y<=0;
                            second_best<=fine_peaks_distinct ? (first_best>pass_best ? first_best : pass_best) : 32767;
                            checking_final<=1;phase<=CHECK_ISSUE;
                        end
                    end else begin
                        if(candidate_x==(fine ? 2 : 8))begin candidate_x<=0;candidate_y<=candidate_y+1'b1;end
                        else candidate_x<=candidate_x+1'b1;
                        index<=index+1'b1;job<=J_MEAN;mean_sum<=0;score_sum<=0;sample<=0;phase<=ISSUE;
                    end
                end
                CHECK_ISSUE:phase<=CHECK_WAIT;
                CHECK_WAIT:phase<=CHECK_ACC;
                CHECK_ACC:begin
                    if(distinct_peak && coarse_q<second_best)begin
                        second_best<=coarse_q;
                        if(!checking_final)begin second_x<=check_cx;second_y<=check_cy;end
                    end
                    if(check_index==80)begin
                        if(checking_final)phase<=FINISH;
                        else begin
                            fine<=1;fine_pass<=0;candidate_x<=0;candidate_y<=0;
                            pass_best<=32767;
                            sample<=0;mean_sum<=0;score_sum<=0;job<=J_MEAN;best<=32767;phase<=ISSUE;
                        end
                    end
                    else begin
                        check_index<=check_index+1'b1;
                        if(check_x==8)begin check_x<=0;check_y<=check_y+1'b1;end else check_x<=check_x+1'b1;
                        phase<=CHECK_ISSUE;
                    end
                end
                FINISH:begin
                    phase<=IDLE;debug_best<=best;debug_margin<=second_best>=best ? second_best-best : 0;
                    debug_reason<=best>MAX_MEAN_ERROR*64 ? 2 : ({1'b0,second_best}<{1'b0,best}+MIN_UNIQUENESS) ? 3 : 1;
                    if(best<=MAX_MEAN_ERROR*64 && {1'b0,second_best}>={1'b0,best}+MIN_UNIQUENESS)begin
                        if(recovering)begin
                            if(REACQUIRE_CONFIRM_FRAMES<=1 ||
                                (status==VERIFY && confirmation_consistent && confirm_count>=REACQUIRE_CONFIRM_FRAMES-1))begin
                                cx<=best_x;cy<=best_y;status<=TRACK;misses<=0;confirm_count<=0;retry_center<=0;debug_reason<=10;
                            end else begin
                                pending_x<=best_x;pending_y<=best_y;status<=VERIFY;debug_reason<=9;
                                confirm_count<=(status==VERIFY && confirmation_consistent) ? confirm_count+1'b1 : 4'd1;
                            end
                        end else begin cx<=best_x;cy<=best_y;status<=TRACK;misses<=0;confirm_count<=0;retry_center<=0;end
                    end else if(AUTO_REACQUIRE && (recovering || misses>=HOLD_FRAMES-1))begin
                        status<=LOST;confirm_count<=0;retry_center<=recovering ? ~retry_center : 1'b0;
                    end else if(misses>=HOLD_FRAMES-1)begin status<=LOST;template_valid<=0;end
                    else begin status<=HOLD;misses<=misses+1'b1;end
                end
                default:begin end
            endcase
        end
    end
endmodule
