`timescale 1ns/1ps

// Dense local tile, stride-2 search + stride-1 refinement. No DDR access.
// Continuous accumulation/valid scheduling inspired by Yiğit Bektaş Gürsoy's
// MIT-licensed Motion_Estimation_Hardware_Verilog (ProcessingElements.v).
// Independently implemented synchronous-RAM prefetch; retains zero-mean SAD.
// Provenance and differences: docs/TEMPLATE_SAD_PIPELINE.md.
module hx_template_tracker #(
    parameter integer IMAGE_WIDTH=1280,IMAGE_HEIGHT=720,HOLD_FRAMES=16,
    parameter integer MAX_MEAN_ERROR=12,MIN_UNIQUENESS=64,MIN_TEXTURE=384,
    parameter integer AUTO_REACQUIRE=1,REACQUIRE_CONFIRM_FRAMES=3,
    parameter integer EXPANDED_REACQUIRE=1,FAR_REACQUIRE=1,
    parameter integer GLOBAL_REACQUIRE=1,FAST_REACQUIRE=1
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
    localparam SEARCH_RADIUS=8;
    localparam TILE_SIZE=64+2*SEARCH_RADIUS;
    localparam TILE_PIXELS=TILE_SIZE*TILE_SIZE;
    localparam COARSE_LAST=(SEARCH_RADIUS+1)*(SEARCH_RADIUS+1)-1;
    reg [3:0] phase;
    reg [1:0] job;
    reg [10:0] cx,cy,roi_x,roi_y,best_x,best_y,coarse_x,coarse_y,second_x,second_y;
    reg armed,template_valid,collect,learn_frame,fine,fine_pass,checking_final;
    reg [4:0] misses;
    reg retry_center;
    // Even pairs revisit the two anchors; odd pairs visit one neighbouring
    // window. Each frame still captures/computes exactly one 80x80 tile.
    reg [3:0] retry_step;
    reg [1:0] retry_cadence;
    reg [3:0] far_x,far_y;
    reg far_center,recovery_slot_far;
    // Preserve the first 32 failed local searches, then alternate local/global.
    // Global centers step by 16, including a clamped last row/column.
    reg [5:0] global_warmup;
    reg global_turn,recovery_slot_global;
    reg [10:0] global_x,global_y;
    reg fast_turn,recovery_slot_fast;
    reg [3:0] confirm_count;
    reg [10:0] pending_x,pending_y;
    reg [6:0] learn_count;
    reg [6:0] index,check_index;
    reg [12:0] patch_count,patch_addr;
    reg [13:0] learn_sum,mean_sum;
    reg [7:0] learn_min,learn_max,template_mean,candidate_mean;
    reg [7:0] template_mem[0:63];
    // Keep the dense search tile in dedicated ERAM, not distributed LUT RAM.
    // 6400 bytes and 81 scores need only 13-bit and 7-bit addresses respectively.
    (* ram_style="bram" *) reg [7:0] patch_mem[0:TILE_PIXELS-1];
    reg [14:0] coarse_scores[0:COARSE_LAST];
    reg [14:0] coarse_q,score_sum,best,second_best;
    reg [14:0] pass_best,first_best;
    reg [10:0] pass_x,pass_y,first_x,first_y;
    reg [5:0] template_addr,sample;
    reg [7:0] template_q,patch_q;
    reg [3:0] candidate_x,candidate_y,check_x,check_y;
    wire frame_start=de && x==0 && y==0;
    wire frame_end=de && x==IMAGE_WIDTH-1 && y==IMAGE_HEIGHT-1;
    wire recovering=AUTO_REACQUIRE && (status==LOST || status==VERIFY);
    wire [10:0] anchor_x=retry_center ? IMAGE_WIDTH/2 : cx;
    wire [10:0] anchor_y=retry_center ? IMAGE_HEIGHT/2 : cy;
    reg [1:0] retry_dx,retry_dy; // 0=none, 1=+16, 2=-16.
    always @* begin
        retry_dx=0;retry_dy=0;
        if(EXPANDED_REACQUIRE && retry_step[0])begin
            case(retry_step[3:1])
                0:retry_dx=1;
                1:retry_dx=2;
                2:retry_dy=1;
                3:retry_dy=2;
                4:begin retry_dx=1;retry_dy=1;end
                5:begin retry_dx=2;retry_dy=1;end
                6:begin retry_dx=1;retry_dy=2;end
                7:begin retry_dx=2;retry_dy=2;end
            endcase
        end
    end
    function [10:0] shifted_center;
        input [10:0] position;
        input [1:0] direction;
        input integer limit;
        begin
            if(direction==1)shifted_center=position+16>limit-32 ? limit-32 : position+16;
            else if(direction==2)shifted_center=position<48 ? 32 : position-16;
            else shifted_center=position;
        end
    endfunction
    // Three near windows retain priority; every fourth failed local search visits
    // one far tile. The 9x9, 16-pixel grid skips the already-covered inner 3x3.
    wire fast_available;
    wire [10:0] fast_x,fast_y;
    wire fast_active=AUTO_REACQUIRE && FAST_REACQUIRE && status==LOST && fast_available && fast_turn;
    generate if(FAST_REACQUIRE && AUTO_REACQUIRE)begin : g_fast
        hx_template_coarse_proposer #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT)) u_proposer (
            .clk(clk),.rst_n(rst_n),.command(command),.de(de),.x(x),.y(y),.luma(luma),
            .learn_start(armed),.template_accepted(template_valid),.search_allowed(recovering),
            .proposal_ack(frame_start && !busy && fast_active),
            .proposal_valid(fast_available),.proposal_x(fast_x),.proposal_y(fast_y)
        );
    end else begin : g_no_fast
        assign fast_available=0;assign fast_x=0;assign fast_y=0;
    end endgenerate
    wire global_active=AUTO_REACQUIRE && GLOBAL_REACQUIRE && status==LOST && global_warmup==32 && global_turn && !fast_active;
    wire far_active=AUTO_REACQUIRE && EXPANDED_REACQUIRE && FAR_REACQUIRE && status==LOST && retry_cadence==3 && !global_active && !fast_active;
    wire [10:0] far_anchor_x=far_center ? IMAGE_WIDTH/2 : cx;
    wire [10:0] far_anchor_y=far_center ? IMAGE_HEIGHT/2 : cy;
    wire signed [12:0] far_trial_x=$signed({2'b0,far_anchor_x})+$signed({5'b0,far_x,4'b0})-13'sd64;
    wire signed [12:0] far_trial_y=$signed({2'b0,far_anchor_y})+$signed({5'b0,far_y,4'b0})-13'sd64;
    wire [10:0] far_search_x=far_trial_x<13'sd32 ? 11'd32 : far_trial_x>IMAGE_WIDTH-32 ? IMAGE_WIDTH-32 : far_trial_x[10:0];
    wire [10:0] far_search_y=far_trial_y<13'sd32 ? 11'd32 : far_trial_y>IMAGE_HEIGHT-32 ? IMAGE_HEIGHT-32 : far_trial_y[10:0];
    wire [3:0] far_x_after=far_x==8 ? 0 : (far_y>=3 && far_y<=5 && far_x==2) ? 6 : far_x+1'b1;
    wire [3:0] far_y_after=far_x==8 ? (far_y==8 ? 0 : far_y+1'b1) : far_y;
    wire retry_center_next=!recovering ? 1'b0 : (recovery_slot_far || recovery_slot_global || recovery_slot_fast) ? retry_center : ~retry_center;
    wire [3:0] retry_step_next=!recovering ? 0 : (!recovery_slot_far && !recovery_slot_global && !recovery_slot_fast && retry_center) ? retry_step+1'b1 : retry_step;
    wire [1:0] cadence_next=FAR_REACQUIRE && recovering ? ((recovery_slot_global || recovery_slot_fast) ? retry_cadence : retry_cadence+1'b1) : 0;
    wire far_center_next=!recovering ? 1'b0 : recovery_slot_far ? ~far_center : far_center;
    wire [3:0] far_x_next=!recovering ? 0 : (recovery_slot_far && far_center) ? far_x_after : far_x;
    wire [3:0] far_y_next=!recovering ? 0 : (recovery_slot_far && far_center) ? far_y_after : far_y;
    wire [5:0] global_warmup_next=!GLOBAL_REACQUIRE || !recovering ? 0 : recovery_slot_fast ? global_warmup : global_warmup<32 ? global_warmup+1'b1 : global_warmup;
    wire global_turn_next=GLOBAL_REACQUIRE && recovering && global_warmup==32 ? (recovery_slot_fast ? global_turn : ~global_turn) : 1'b0;
    wire fast_turn_next=FAST_REACQUIRE && recovering ? ~fast_turn : 1'b0;
    wire [10:0] global_x_after=global_x==IMAGE_WIDTH-32 ? 11'd32 : global_x+16>IMAGE_WIDTH-32 ? IMAGE_WIDTH-32 : global_x+11'd16;
    wire [10:0] global_y_after=global_x!=IMAGE_WIDTH-32 ? global_y : global_y==IMAGE_HEIGHT-32 ? 11'd32 : global_y+16>IMAGE_HEIGHT-32 ? IMAGE_HEIGHT-32 : global_y+11'd16;
    wire [10:0] global_x_next=!recovering ? 11'd32 : recovery_slot_global ? global_x_after : global_x;
    wire [10:0] global_y_next=!recovering ? 11'd32 : recovery_slot_global ? global_y_after : global_y;
    wire [10:0] search_x=status==VERIFY ? pending_x :
        (AUTO_REACQUIRE && status==LOST) ? (fast_active ? fast_x : global_active ? global_x : far_active ? far_search_x : shifted_center(anchor_x,retry_dx,IMAGE_WIDTH)) : cx;
    wire [10:0] search_y=status==VERIFY ? pending_y :
        (AUTO_REACQUIRE && status==LOST) ? (fast_active ? fast_y : global_active ? global_y : far_active ? far_search_y : shifted_center(anchor_y,retry_dy,IMAGE_HEIGHT)) : cy;
    wire [10:0] next_roi_x=search_x<TILE_SIZE/2 ? 11'd0 : search_x>IMAGE_WIDTH-TILE_SIZE/2 ? IMAGE_WIDTH-TILE_SIZE : search_x-TILE_SIZE/2;
    wire [10:0] next_roi_y=search_y<TILE_SIZE/2 ? 11'd0 : search_y>IMAGE_HEIGHT-TILE_SIZE/2 ? IMAGE_HEIGHT-TILE_SIZE : search_y-TILE_SIZE/2;
    wire [10:0] rx=frame_start ? next_roi_x : roi_x,ry=frame_start ? next_roi_y : roi_y;
    wire [10:0] tile_x=x-rx,tile_y=y-ry;
    wire take_patch=de && (frame_start ? template_valid : collect) && !busy &&
        x>=rx && x<rx+TILE_SIZE && y>=ry && y<ry+TILE_SIZE;
    // Gaussian phase +2 avoids stale causal-window pixels at image borders.
    wire take_learn=de && learn_frame && x>=IMAGE_WIDTH/2-30 && x<IMAGE_WIDTH/2+34 &&
        y>=IMAGE_HEIGHT/2-30 && y<IMAGE_HEIGHT/2+34 &&
        x[2:0]==((IMAGE_WIDTH/2+2)%8) && y[2:0]==((IMAGE_HEIGHT/2+2)%8);
    wire [10:0] lx=x-(IMAGE_WIDTH/2-30),ly=y-(IMAGE_HEIGHT/2-30);
    wire [10:0] cand_cx=fine ? coarse_x-1+candidate_x : roi_x+32+{candidate_x,1'b0};
    wire [10:0] cand_cy=fine ? coarse_y-1+candidate_y : roi_y+32+{candidate_y,1'b0};
    wire candidate_valid=cand_cx>=32 && cand_cx<=IMAGE_WIDTH-32 && cand_cy>=32 && cand_cy<=IMAGE_HEIGHT-32;
    // RAM consumes the address one edge after ISSUE. WAIT prefetches sample 1;
    // ACC consumes sample n while issuing n+2, hence no inter-pixel bubbles.
    wire [5:0] read_sample=phase==WAIT_READ ? 6'd1 : phase==ACC ? sample+6'd2 : sample;
    wire [6:0] read_x=cand_cx-30-roi_x+{read_sample[2:0],3'b000};
    wire [6:0] read_y=cand_cy-30-roi_y+{read_sample[5:3],3'b000};
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
            retry_center<=0;retry_step<=0;confirm_count<=0;pending_x<=IMAGE_WIDTH/2;pending_y<=IMAGE_HEIGHT/2;
            retry_cadence<=0;far_x<=0;far_y<=0;far_center<=0;recovery_slot_far<=0;
            global_warmup<=0;global_turn<=0;global_x<=32;global_y<=32;recovery_slot_global<=0;
            fast_turn<=0;recovery_slot_fast<=0;
            learn_count<=0;patch_count<=0;learn_sum<=0;mean_sum<=0;
            learn_min<=255;learn_max<=0;template_mean<=0;candidate_mean<=0;
            template_addr<=0;patch_addr<=0;sample<=0;candidate_x<=0;candidate_y<=0;
            index<=0;check_index<=0;check_x<=0;check_y<=0;score_sum<=0;best<=32767;second_best<=32767;
            pass_best<=32767;first_best<=32767;pass_x<=0;pass_y<=0;first_x<=0;first_y<=0;
            debug_reason<=0;debug_best<=32767;debug_margin<=0;
        end else if(command)begin
            phase<=IDLE;collect<=0;learn_frame<=0;template_valid<=0;misses<=0;
            retry_center<=0;retry_step<=0;confirm_count<=0;
            retry_cadence<=0;far_x<=0;far_y<=0;far_center<=0;recovery_slot_far<=0;
            global_warmup<=0;global_turn<=0;global_x<=32;global_y<=32;recovery_slot_global<=0;
            fast_turn<=0;recovery_slot_fast<=0;
            cx<=IMAGE_WIDTH/2;cy<=IMAGE_HEIGHT/2;
            debug_reason<=(status==READY || status==LOST || status==FLAT) ? 0 : 7;
            debug_best<=32767;debug_margin<=0;
            if(status==READY || status==LOST || status==FLAT)begin armed<=1;status<=LEARN;end
            else begin armed<=0;status<=READY;end
        end else if(frame_start && busy)begin
            phase<=IDLE;collect<=0;learn_frame<=0;debug_reason<=5;
            if(job==J_LEARN)begin status<=FLAT;template_valid<=0;end
            else if(AUTO_REACQUIRE && (recovering || misses>=HOLD_FRAMES-1))begin
                status<=LOST;confirm_count<=0;retry_center<=retry_center_next;retry_step<=retry_step_next;
                retry_cadence<=cadence_next;far_x<=far_x_next;far_y<=far_y_next;far_center<=far_center_next;
                global_warmup<=global_warmup_next;global_turn<=global_turn_next;global_x<=global_x_next;global_y<=global_y_next;
                fast_turn<=fast_turn_next;
            end
            else if(misses>=HOLD_FRAMES-1)begin status<=LOST;template_valid<=0;end
            else begin status<=HOLD;misses<=misses+1'b1;end
        end else begin
            if(frame_start)begin
                recovery_slot_far<=far_active;
                recovery_slot_global<=global_active;
                recovery_slot_fast<=fast_active;
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
                    if(patch_count==TILE_PIXELS || (patch_count==TILE_PIXELS-1 && take_patch))begin
                        candidate_x<=0;candidate_y<=0;sample<=0;mean_sum<=0;score_sum<=0;
                        best<=32767;second_best<=32767;job<=J_MEAN;phase<=ISSUE;fine<=0;index<=0;
                    end else begin
                        debug_reason<=4;
                        if(AUTO_REACQUIRE && (recovering || misses>=HOLD_FRAMES-1))begin
                            status<=LOST;confirm_count<=0;retry_center<=retry_center_next;retry_step<=retry_step_next;
                            retry_cadence<=cadence_next;far_x<=far_x_next;far_y<=far_y_next;far_center<=far_center_next;
                            global_warmup<=global_warmup_next;global_turn<=global_turn_next;global_x<=global_x_next;global_y<=global_y_next;
                            fast_turn<=fast_turn_next;
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
                WAIT_READ:begin template_addr<=1;patch_addr<=read_address;phase<=ACC;end
                ACC:begin
                    if(sample!=63)begin template_addr<=sample+6'd2;patch_addr<=read_address;end
                    if(job==J_MEAN)begin
                        mean_sum<=mean_next;
                        if(sample==63)begin candidate_mean<=mean_next[13:6];sample<=0;score_sum<=0;job<=J_SCORE;phase<=ISSUE;end
                        else sample<=sample+1'b1;
                    end else begin
                        score_sum<=score_next;
                        if(sample!=63)sample<=sample+1'b1;
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
                    if(candidate_x==(fine ? 2 : SEARCH_RADIUS) && candidate_y==(fine ? 2 : SEARCH_RADIUS))begin
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
                        if(candidate_x==(fine ? 2 : SEARCH_RADIUS))begin candidate_x<=0;candidate_y<=candidate_y+1'b1;end
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
                    if(check_index==COARSE_LAST)begin
                        if(checking_final)phase<=FINISH;
                        else begin
                            fine<=1;fine_pass<=0;candidate_x<=0;candidate_y<=0;
                            pass_best<=32767;
                            sample<=0;mean_sum<=0;score_sum<=0;job<=J_MEAN;best<=32767;phase<=ISSUE;
                        end
                    end
                    else begin
                        check_index<=check_index+1'b1;
                        if(check_x==SEARCH_RADIUS)begin check_x<=0;check_y<=check_y+1'b1;end else check_x<=check_x+1'b1;
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
                                cx<=best_x;cy<=best_y;status<=TRACK;misses<=0;confirm_count<=0;retry_center<=0;retry_step<=0;debug_reason<=10;
                                retry_cadence<=0;far_x<=0;far_y<=0;far_center<=0;
                                global_warmup<=0;global_turn<=0;global_x<=32;global_y<=32;
                                fast_turn<=0;
                            end else begin
                                pending_x<=best_x;pending_y<=best_y;status<=VERIFY;debug_reason<=9;
                                confirm_count<=(status==VERIFY && confirmation_consistent) ? confirm_count+1'b1 : 4'd1;
                                // Do not let a flashing global proposal starve the sweep.
                                // VERIFY uses pending_x/y; a rejected proposal resumes at
                                // the next global tile instead of retrying it forever.
                                if(recovery_slot_global)begin global_x<=global_x_after;global_y<=global_y_after;end
                            end
                        end else begin
                            cx<=best_x;cy<=best_y;status<=TRACK;misses<=0;confirm_count<=0;retry_center<=0;retry_step<=0;
                            retry_cadence<=0;far_x<=0;far_y<=0;far_center<=0;
                            global_warmup<=0;global_turn<=0;global_x<=32;global_y<=32;
                            fast_turn<=0;
                        end
                    end else if(AUTO_REACQUIRE && (recovering || misses>=HOLD_FRAMES-1))begin
                        status<=LOST;confirm_count<=0;retry_center<=retry_center_next;retry_step<=retry_step_next;
                        retry_cadence<=cadence_next;far_x<=far_x_next;far_y<=far_y_next;far_center<=far_center_next;
                        global_warmup<=global_warmup_next;global_turn<=global_turn_next;global_x<=global_x_next;global_y<=global_y_next;
                        fast_turn<=fast_turn_next;
                    end else if(misses>=HOLD_FRAMES-1)begin status<=LOST;template_valid<=0;end
                    else begin status<=HOLD;misses<=misses+1'b1;end
                end
                default:begin end
            endcase
        end
    end
endmodule

// One-level image pyramid candidate proposer. Independently written RTL;
// coarse-to-fine candidate architecture reference: DennisLiu1993/
// Fastest_Image_Pattern_Matching (BSD-2-Clause). Not an NCC/OpenCV port.
// 4x4 box mean -> quarter-resolution ERAM -> 64-point zero-mean SAD.
// Original-resolution tracking alone decides acceptance; no template updates.
module hx_template_coarse_proposer #(
    parameter integer IMAGE_WIDTH=1280,IMAGE_HEIGHT=720,
    parameter integer MAX_COARSE_ERROR=24,MAX_QUEUE_AGE=12
) (
    input wire clk,rst_n,command,de,
    input wire [10:0] x,y,
    input wire [7:0] luma,
    input wire learn_start,template_accepted,search_allowed,proposal_ack,
    output wire proposal_valid,
    output wire [10:0] proposal_x,proposal_y
);
    localparam CW=IMAGE_WIDTH/4,CH=IMAGE_HEIGHT/4,N=CW*CH;
    localparam AW=$clog2(N),PW=$clog2(IMAGE_WIDTH*IMAGE_HEIGHT+1);
    localparam IDLE=0,L_ISSUE=1,L_WAIT=2,L_ACC=3,S_ISSUE=4,S_WAIT=5,S_ACC=6,S_END=7,PUBLISH=8;
    reg [3:0] phase;
    reg collect,learning,bad_frame,tpl_ok;
    reg [10:0] expected_x,expected_y;
    reg [PW-1:0] pixel_count;
    reg [AW:0] cell_count;
    reg [9:0] horizontal_sum;
    // A small row accumulator fits distributed RAM; reserve ERAM for snapshots.
    (* ram_style="distributed" *) reg [11:0] column_sum[0:CW-1];
    reg [11:0] column_q;
    wire [7:0] image_q;
    reg [7:0] tpl_mem[0:63],tpl_q,tpl_mean,candidate_mean;
    reg [AW-1:0] read_addr;
    reg [6:0] learn_count;
    reg [13:0] learn_sum,mean_sum;
    reg [7:0] learn_min,learn_max;
    reg [5:0] sample;
    reg score_pass;
    reg [14:0] score;
    reg [8:0] candidate_x,candidate_y,best_x[0:1],best_y[0:1];
    reg [14:0] best_score[0:1];
    reg [1:0] queue_count;
    reg queue_index;
    reg [3:0] queue_age;
    wire frame_start=de && x==0 && y==0;
    wire frame_end=de && x==IMAGE_WIDTH-1 && y==IMAGE_HEIGHT-1;
    wire begin_capture=phase==IDLE && (learn_start ||
        (search_allowed && template_accepted && tpl_ok && queue_count==0));
    wire taking=frame_start ? begin_capture : collect;
    wire is_learning=frame_start ? learn_start : learning;
    wire [8:0] col=x[10:2],row=y[10:2];
    wire [9:0] row_sum=x[1:0]==0 ? {2'b0,luma} : horizontal_sum+{2'b0,luma};
    wire [11:0] cell_sum=y[1:0]==0 ? {2'b0,row_sum} : column_q+{2'b0,row_sum};
    wire [7:0] cell_value=cell_sum[11:4];
    wire in_cells=x<CW*4 && y<CH*4;
    wire cell_end=de && taking && in_cells && x[1:0]==3;
    wire emit_cell=cell_end && y[1:0]==3;
    wire [AW-1:0] write_addr=row*CW+col;
    wire [8:0] tx=col-((IMAGE_WIDTH/2)/4-8),ty=row-((IMAGE_HEIGHT/2)/4-8);
    wire take_template=emit_cell && is_learning &&
        col>=(IMAGE_WIDTH/2)/4-8 && col<(IMAGE_WIDTH/2)/4+8 &&
        row>=(IMAGE_HEIGHT/2)/4-8 && row<(IMAGE_HEIGHT/2)/4+8 && !tx[0] && !ty[0];
    wire [8:0] read_x=candidate_x-8+{sample[2:0],1'b0};
    wire [8:0] read_y=candidate_y-8+{sample[5:3],1'b0};
    wire [AW-1:0] sample_addr=read_y*CW+read_x;
    // Five full-precision pixels per 40-bit word. The read/write phases do
    // not overlap, and ISSUE/WAIT/ACC timing remains exactly as before.
    localparam WORDS_PER_ROW=(CW+4)/5,WORD_COUNT=WORDS_PER_ROW*CH;
    localparam WORD_AW=$clog2(WORD_COUNT);
    function [WORD_AW-1:0] word_row_offset;
        input [8:0] line;
        integer bit_index;
        begin
            word_row_offset=0;
            for(bit_index=0;bit_index<9;bit_index=bit_index+1)
                if((WORDS_PER_ROW>>bit_index)&1)
                    word_row_offset=word_row_offset+(line<<bit_index);
        end
    endfunction
    wire [WORD_AW-1:0] word_write_addr=word_row_offset(row)+col/5;
    wire [2:0] word_write_lane=col%5;
    reg [WORD_AW-1:0] word_read_addr;
    reg [2:0] word_read_lane;
    generate begin : g_image
        (* ram_style="bram" *) reg [39:0] words[0:WORD_COUNT-1];
        reg [39:0] write_word,read_word;
        reg [2:0] read_lane;
        reg [39:0] next_word;
        always @* begin
            next_word=word_write_lane==0 ? 40'd0 : write_word;
            case(word_write_lane)
                0:next_word[7:0]=cell_value;
                1:next_word[15:8]=cell_value;
                2:next_word[23:16]=cell_value;
                3:next_word[31:24]=cell_value;
                default:next_word[39:32]=cell_value;
            endcase
        end
        always @(posedge clk)begin
            read_word<=words[word_read_addr];read_lane<=word_read_lane;
            if(rst_n && !command && emit_cell)begin
                write_word<=next_word;
                if(word_write_lane==4 || col==CW-1)words[word_write_addr]<=next_word;
            end
        end
        assign image_q=read_word>>(read_lane*8);
        // Used only by simulation scoreboards; no production read port.
        function [7:0] read_byte;
            input integer address;
            begin read_byte=words[(address/CW)*WORDS_PER_ROW+(address%CW)/5]>>(((address%CW)%5)*8);end
        endfunction
    end endgenerate
    wire coordinate_bad=de && !frame_start && (x!=expected_x || y!=expected_y);
    wire signed [9:0] difference=phase==L_ACC ?
        $signed({2'b0,tpl_q})-$signed({2'b0,tpl_mean}) :
        $signed({2'b0,image_q})-$signed({2'b0,candidate_mean})-
        $signed({2'b0,tpl_q})+$signed({2'b0,tpl_mean});
    wire [9:0] error_value=difference[9] ? $unsigned(-difference) : $unsigned(difference);
    wire [14:0] score_next=score+{5'd0,error_value};
    wire [13:0] mean_next=mean_sum+{6'd0,image_q};
    wire near0=best_x[0]+4>=candidate_x && best_x[0]<=candidate_x+4 && best_y[0]+4>=candidate_y && best_y[0]<=candidate_y+4;
    wire near1=best_x[1]+4>=candidate_x && best_x[1]<=candidate_x+4 && best_y[1]+4>=candidate_y && best_y[1]<=candidate_y+4;
    wire two_peaks=best_x[0]+4<best_x[1] || best_x[1]+4<best_x[0] || best_y[0]+4<best_y[1] || best_y[1]+4<best_y[0];
    assign proposal_valid=queue_count!=0 && queue_age<MAX_QUEUE_AGE && search_allowed && template_accepted && tpl_ok;
    assign proposal_x={best_x[queue_index],2'b00};
    assign proposal_y={best_y[queue_index],2'b00};
    // Separate synchronous RAM process: no reset on image/column arrays.
    always @(posedge clk)begin
        tpl_q<=tpl_mem[sample];
        if(de && taking && in_cells && x[1:0]==0)column_q<=column_sum[col];
        if(rst_n && !command && cell_end)column_sum[col]<=cell_sum;
        if(rst_n && !command && take_template)tpl_mem[{ty[3:1],tx[3:1]}]<=cell_value;
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            phase<=IDLE;collect<=0;learning<=0;bad_frame<=0;tpl_ok<=0;
            expected_x<=0;expected_y<=0;pixel_count<=0;cell_count<=0;
            horizontal_sum<=0;read_addr<=0;word_read_addr<=0;word_read_lane<=0;
            learn_count<=0;learn_sum<=0;learn_min<=255;learn_max<=0;
            tpl_mean<=0;candidate_mean<=0;sample<=0;score_pass<=0;mean_sum<=0;score<=0;
            candidate_x<=8;candidate_y<=8;best_score[0]<=32767;best_score[1]<=32767;
            best_x[0]<=8;best_x[1]<=8;best_y[0]<=8;best_y[1]<=8;
            queue_count<=0;queue_index<=0;queue_age<=0;
        end else if(command)begin
            phase<=IDLE;collect<=0;learning<=0;tpl_ok<=0;queue_count<=0;queue_index<=0;queue_age<=0;
            bad_frame<=0;pixel_count<=0;cell_count<=0;learn_count<=0;
        end else begin
            if(frame_start)begin
                collect<=begin_capture;learning<=learn_start;bad_frame<=0;
                expected_x<=1;expected_y<=0;pixel_count<=1;cell_count<=0;
                horizontal_sum<={2'b0,luma};
                if(learn_start)begin learn_count<=0;learn_sum<=0;learn_min<=255;learn_max<=0;tpl_ok<=0;end
                if(queue_count!=0)begin
                    if(queue_age>=MAX_QUEUE_AGE-1)queue_count<=0;
                    else queue_age<=queue_age+1'b1;
                end
            end else if(de && collect)begin
                pixel_count<=pixel_count+1'b1;
                if(coordinate_bad)bad_frame<=1;
                if(x==IMAGE_WIDTH-1)begin expected_x<=0;expected_y<=y+1'b1;end
                else begin expected_x<=x+1'b1;expected_y<=y;end
                horizontal_sum<=row_sum;
            end
            if(emit_cell)cell_count<=cell_count+1'b1;
            if(take_template)begin
                learn_count<=learn_count+1'b1;learn_sum<=learn_sum+{6'd0,cell_value};
                if(cell_value<learn_min)learn_min<=cell_value;
                if(cell_value>learn_max)learn_max<=cell_value;
            end
            if(proposal_ack && proposal_valid)begin queue_count<=queue_count-1'b1;queue_index<=1;end
            if(frame_end && collect)begin
                collect<=0;
                if(!bad_frame && !coordinate_bad && pixel_count==IMAGE_WIDTH*IMAGE_HEIGHT-1 &&
                    (cell_count==N || (cell_count==N-1 && emit_cell)))begin
                    sample<=0;score<=0;mean_sum<=0;
                    if(learning && learn_count==64)begin tpl_mean<=learn_sum[13:6];phase<=L_ISSUE;end
                    else if(!learning && tpl_ok && template_accepted && search_allowed)begin
                        candidate_x<=8;candidate_y<=8;score_pass<=0;
                        best_score[0]<=32767;best_score[1]<=32767;phase<=S_ISSUE;
                    end
                end
            end
            case(phase)
                L_ISSUE:phase<=L_WAIT;
                L_WAIT:phase<=L_ACC;
                L_ACC:begin
                    score<=score_next;
                    if(sample==63)begin tpl_ok<=learn_max-learn_min>=12 && score_next>=256;phase<=IDLE;end
                    else begin sample<=sample+1'b1;phase<=L_ISSUE;end
                end
                S_ISSUE:begin
                    read_addr<=sample_addr;
                    word_read_addr<=word_row_offset(read_y)+read_x/5;
                    word_read_lane<=read_x%5;
                    phase<=S_WAIT;
                end
                S_WAIT:phase<=S_ACC;
                S_ACC:begin
                    if(!score_pass)begin
                        mean_sum<=mean_next;
                        if(sample==63)begin candidate_mean<=mean_next[13:6];sample<=0;score<=0;score_pass<=1;end
                        else sample<=sample+1'b1;
                        phase<=S_ISSUE;
                    end else begin
                        score<=score_next;
                        if(sample==63)phase<=S_END;
                        else begin sample<=sample+1'b1;phase<=S_ISSUE;end
                    end
                end
                S_END:begin
                    // Two spatially distinct peaks; proposals never bypass fine validation.
                    if(score<=MAX_COARSE_ERROR*64)begin
                        if(near0 && best_score[0]!=32767)begin
                            if(score<best_score[0])begin best_score[0]<=score;best_x[0]<=candidate_x;best_y[0]<=candidate_y;end
                        end else if(near1 && best_score[1]!=32767)begin
                            if(score<best_score[1])begin
                                if(score<best_score[0])begin
                                    best_score[1]<=best_score[0];best_x[1]<=best_x[0];best_y[1]<=best_y[0];
                                    best_score[0]<=score;best_x[0]<=candidate_x;best_y[0]<=candidate_y;
                                end else begin best_score[1]<=score;best_x[1]<=candidate_x;best_y[1]<=candidate_y;end
                            end
                        end else if(score<best_score[0])begin
                            best_score[1]<=best_score[0];best_x[1]<=best_x[0];best_y[1]<=best_y[0];
                            best_score[0]<=score;best_x[0]<=candidate_x;best_y[0]<=candidate_y;
                        end else if(score<best_score[1])begin best_score[1]<=score;best_x[1]<=candidate_x;best_y[1]<=candidate_y;end
                    end
                    if(candidate_x==CW-8 && candidate_y==CH-8)phase<=PUBLISH;
                    else begin
                        if(candidate_x==CW-8)begin candidate_x<=8;candidate_y<=candidate_y+1'b1;end
                        else candidate_x<=candidate_x+1'b1;
                        sample<=0;score<=0;mean_sum<=0;score_pass<=0;phase<=S_ISSUE;
                    end
                end
                PUBLISH:begin
                    phase<=IDLE;queue_index<=0;queue_age<=0;
                    if(best_score[0]<=MAX_COARSE_ERROR*64)
                        queue_count<=(best_score[1]<=MAX_COARSE_ERROR*64 && two_peaks) ? 2 : 1;
                end
                default:begin end
            endcase
            // Keep proposals across VERIFY, but cancel all search work on TRACK,
            // READY/FLAT or a rejected original template. Learning is independent.
            if(!search_allowed)begin
                queue_count<=0;queue_age<=0;
                if(phase>=S_ISSUE)phase<=IDLE;
                if(collect && !learning)collect<=0;
            end
            if(frame_start && queue_count!=0 && queue_age>=MAX_QUEUE_AGE-1)queue_count<=0;
        end
    end
endmodule
