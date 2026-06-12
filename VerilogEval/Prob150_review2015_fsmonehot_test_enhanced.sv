`timescale 1 ps/1 ps
//==============================================================================
// Auto-generated enhanced TB — Prob150_review2015_fsmonehot
// Category : combinational
// Buckets  : B_steady, C_boundary, D_backtoback, F_longseq
// MaxCycles: 1000
// Generator: coevo/tb_gen/template.py
//==============================================================================

module testbench_enhanced;

    reg d = 1'b0;
    reg done_counting = 1'b0;
    reg ack = 1'b0;
    reg [9:0] state = 0;
    wire B3_next_dut;
    wire B3_next_ref;
    wire S_next_dut;
    wire S_next_ref;
    wire S1_next_dut;
    wire S1_next_ref;
    wire Count_next_dut;
    wire Count_next_ref;
    wire Wait_next_dut;
    wire Wait_next_ref;
    wire done_dut;
    wire done_ref;
    wire counting_dut;
    wire counting_ref;
    wire shift_ena_dut;
    wire shift_ena_ref;

    TopModule uut (
        .d(d),
        .done_counting(done_counting),
        .ack(ack),
        .state(state),
        .B3_next(B3_next_dut),
        .S_next(S_next_dut),
        .S1_next(S1_next_dut),
        .Count_next(Count_next_dut),
        .Wait_next(Wait_next_dut),
        .done(done_dut),
        .counting(counting_dut),
        .shift_ena(shift_ena_dut)
    );

    RefModule fg_gold (
        .d(d),
        .done_counting(done_counting),
        .ack(ack),
        .state(state),
        .B3_next(B3_next_ref),
        .S_next(S_next_ref),
        .S1_next(S1_next_ref),
        .Count_next(Count_next_ref),
        .Wait_next(Wait_next_ref),
        .done(done_ref),
        .counting(counting_ref),
        .shift_ena(shift_ena_ref)
    );

    localparam FG_N_BKT = 4;
    integer fg_bkt_tot  [0:3];
    integer fg_bkt_pass [0:3];
    integer fg_ff_cyc   [0:3];
    reg [12:0] fg_ff_in_v  [0:3];
    reg [7:0] fg_ff_dut_v [0:3];
    reg [7:0] fg_ff_ref_v [0:3];
    integer fg_w [0:3];

    integer fg_total  = 0;
    integer fg_passed = 0;
    integer fg_failed = 0;
    integer fg_cyc    = 0;
    integer fg_i;
    integer fg_seed = 32'h1357_BEEF;

    initial begin
        fg_bkt_tot[0]  = 0;
        fg_bkt_pass[0] = 0;
        fg_ff_cyc[0]   = -1;
        fg_bkt_tot[1]  = 0;
        fg_bkt_pass[1] = 0;
        fg_ff_cyc[1]   = -1;
        fg_bkt_tot[2]  = 0;
        fg_bkt_pass[2] = 0;
        fg_ff_cyc[2]   = -1;
        fg_bkt_tot[3]  = 0;
        fg_bkt_pass[3] = 0;
        fg_ff_cyc[3]   = -1;
        fg_w[0] = 3;   // B_steady
        fg_w[1] = 3;   // C_boundary
        fg_w[2] = 2;   // D_backtoback
        fg_w[3] = 3;   // F_longseq
    end

    initial begin
        #2000000;
        $display("[FORGE_RESULT] TIMEOUT TOTAL=%0d PASSED=%0d FAILED=%0d",
                 fg_total, fg_passed, fg_failed);
        $finish;
    end


    task fg_sample_bucket(input integer fg_b);
        begin
            #1; // settle
            fg_total = fg_total + 1;
            fg_cyc   = fg_cyc + 1;
            fg_bkt_tot[fg_b] = fg_bkt_tot[fg_b] + 1;
            if ({ B3_next_dut , S_next_dut , S1_next_dut , Count_next_dut , Wait_next_dut , done_dut , counting_dut , shift_ena_dut } === { B3_next_ref , S_next_ref , S1_next_ref , Count_next_ref , Wait_next_ref , done_ref , counting_ref , shift_ena_ref }) begin
                fg_passed         = fg_passed + 1;
                fg_bkt_pass[fg_b] = fg_bkt_pass[fg_b] + 1;
            end else begin
                fg_failed = fg_failed + 1;
                if (fg_ff_cyc[fg_b] < 0) begin
                    fg_ff_cyc[fg_b]   = fg_cyc;
                    fg_ff_in_v[fg_b]  = { d , done_counting , ack , state };
                    fg_ff_dut_v[fg_b] = { B3_next_dut , S_next_dut , S1_next_dut , Count_next_dut , Wait_next_dut , done_dut , counting_dut , shift_ena_dut };
                    fg_ff_ref_v[fg_b] = { B3_next_ref , S_next_ref , S1_next_ref , Count_next_ref , Wait_next_ref , done_ref , counting_ref , shift_ena_ref };
                end
            end
        end
    endtask


    task fg_step(input integer fg_b);
        begin #5; fg_sample_bucket(fg_b); end
    endtask


    initial begin
        // initial idle settle
        #1;

        //==== B_steady ====
        for (fg_i = 0; fg_i < 50; fg_i = fg_i + 1) begin
        d = $random(fg_seed);
        done_counting = $random(fg_seed);
        ack = $random(fg_seed);
        state = $random(fg_seed);
            fg_step(0);
        end

        //==== C_boundary ====
        // all-0
        d = 1'h0;
        done_counting = 1'h0;
        ack = 1'h0;
        state = 10'h0;
        fg_step(1); fg_step(1); fg_step(1);
        // all-1
        d = {1{1'b1}};
        done_counting = {1{1'b1}};
        ack = {1{1'b1}};
        state = {10{1'b1}};
        fg_step(1); fg_step(1); fg_step(1);
        // LSB only
        d = 1'h1;
        done_counting = 1'h1;
        ack = 1'h1;
        state = 10'h1;
        fg_step(1); fg_step(1); fg_step(1);
        // MSB only
        d = 1'b1;
        done_counting = 1'b1;
        ack = 1'b1;
        state = {1'b1, 9'h0};
        fg_step(1); fg_step(1); fg_step(1);
        // alternating
        d = 1'h5;
        done_counting = 1'h5;
        ack = 1'h5;
        state = {2{8'h55}};
        fg_step(1); fg_step(1); fg_step(1);

        //==== D_backtoback ====
        for (fg_i = 0; fg_i < 30; fg_i = fg_i + 1) begin
            if (fg_i[0] == 1'b0) begin
        d = 1'h0;
        done_counting = 1'h0;
        ack = 1'h0;
        state = 10'h0;
            end else begin
        d = $random(fg_seed);
        done_counting = $random(fg_seed);
        ack = $random(fg_seed);
        state = $random(fg_seed);
            end
            fg_step(2);
        end

        //==== F_longseq ====
        for (fg_i = 0; fg_i < 950; fg_i = fg_i + 1) begin
        d = $random(fg_seed);
        done_counting = $random(fg_seed);
        ack = $random(fg_seed);
        state = $random(fg_seed);

            fg_step(3);
        end

        #5;
        fg_report_and_finish;
    end

    task fg_report_and_finish;
        real    fg_score_w;
        real    fg_tot_w;
        integer fg_k;
        integer fg_scaled_pass;
        integer fg_scaled_total;
        integer fg_scaled_fail;
        begin
            fg_tot_w   = 0.0;
            fg_score_w = 0.0;
            for (fg_k = 0; fg_k < FG_N_BKT; fg_k = fg_k + 1) begin
                if (fg_bkt_tot[fg_k] > 0) begin
                    fg_score_w = fg_score_w + (fg_w[fg_k] * 1.0 * fg_bkt_pass[fg_k] / fg_bkt_tot[fg_k]);
                    fg_tot_w   = fg_tot_w + fg_w[fg_k];
                end
            end
            if (fg_tot_w > 0.0) fg_score_w = fg_score_w / fg_tot_w;

            fg_scaled_total = 10000;
            fg_scaled_pass  = $rtoi(fg_score_w * 10000.0 + 0.5);
            if (fg_scaled_pass < 0) fg_scaled_pass = 0;
            if (fg_scaled_pass > fg_scaled_total) fg_scaled_pass = fg_scaled_total;
            fg_scaled_fail = fg_scaled_total - fg_scaled_pass;

            $display("===================================================");
            $display("[FORGE_RESULT] TOTAL=%0d PASSED=%0d FAILED=%0d",
                     fg_scaled_total, fg_scaled_pass, fg_scaled_fail);
            $display("[FORGE_RAW] TOTAL=%0d PASSED=%0d FAILED=%0d",
                     fg_total, fg_passed, fg_failed);
            $display("[FORGE_SCORE_WEIGHTED] %0.4f", fg_score_w);
            $display("[FORGE_BUCKET] B_steady=%0d/%0d C_boundary=%0d/%0d D_backtoback=%0d/%0d F_longseq=%0d/%0d",
                     fg_bkt_pass[0],
                     fg_bkt_tot[0],
                     fg_bkt_pass[1],
                     fg_bkt_tot[1],
                     fg_bkt_pass[2],
                     fg_bkt_tot[2],
                     fg_bkt_pass[3],
                     fg_bkt_tot[3]);

            for (fg_k = 0; fg_k < FG_N_BKT; fg_k = fg_k + 1) begin
                if (fg_ff_cyc[fg_k] >= 0) begin
                    case (fg_k)
                  0: $display("[FORGE_FIRSTFAIL] bucket=B_steady       cyc=%0d in=%04h dut=%02h ref=%02h",
                       fg_ff_cyc[0], fg_ff_in_v[0], fg_ff_dut_v[0], fg_ff_ref_v[0]);
                  1: $display("[FORGE_FIRSTFAIL] bucket=C_boundary     cyc=%0d in=%04h dut=%02h ref=%02h",
                       fg_ff_cyc[1], fg_ff_in_v[1], fg_ff_dut_v[1], fg_ff_ref_v[1]);
                  2: $display("[FORGE_FIRSTFAIL] bucket=D_backtoback   cyc=%0d in=%04h dut=%02h ref=%02h",
                       fg_ff_cyc[2], fg_ff_in_v[2], fg_ff_dut_v[2], fg_ff_ref_v[2]);
                  3: $display("[FORGE_FIRSTFAIL] bucket=F_longseq      cyc=%0d in=%04h dut=%02h ref=%02h",
                       fg_ff_cyc[3], fg_ff_in_v[3], fg_ff_dut_v[3], fg_ff_ref_v[3]);
                    endcase
                end
            end

            if (fg_scaled_fail == 0)
                $display("[FORGE_STATUS] PASS SCORE=%0d/%0d", fg_scaled_pass, fg_scaled_total);
            else
                $display("[FORGE_STATUS] FAIL SCORE=%0d/%0d", fg_scaled_pass, fg_scaled_total);
            $display("===================================================");
            $finish;
        end
    endtask

endmodule

//==============================================================================
// Golden reference — verbatim from Prob150_review2015_fsmonehot_ref.sv
//==============================================================================
module RefModule (
  input d,
  input done_counting,
  input ack,
  input [9:0] state, // 10-bit one-hot current state
  output B3_next,
  output S_next,
  output S1_next,
  output Count_next,
  output Wait_next,
  output done,
  output counting,
  output shift_ena
);

  parameter S=0, S1=1, S11=2, S110=3, B0=4, B1=5, B2=6, B3=7, Count=8, Wait=9;

  assign B3_next = state[B2];
  assign S_next = state[S]&~d | state[S1]&~d | state[S110]&~d | state[Wait]&ack;
  assign S1_next = state[S]&d;
  assign Count_next = state[B3] | state[Count]&~done_counting;
  assign Wait_next = state[Count]&done_counting | state[Wait]&~ack;

  assign done = state[Wait];
  assign counting = state[Count];
  assign shift_ena = |state[B3:B0];

endmodule
