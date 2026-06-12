`timescale 1 ps/1 ps
//==============================================================================
// Auto-generated enhanced TB — Prob155_lemmings4
// Category : sequential
// Buckets  : A_reset, B_steady, C_boundary, D_backtoback, F_longseq
// MaxCycles: 1000
// Generator: coevo/tb_gen/template.py
//==============================================================================

module testbench_enhanced;

    reg clk = 1'b0;
    reg areset = 1'b0;
    reg bump_left = 1'b0;
    reg bump_right = 1'b0;
    reg ground = 1'b0;
    reg dig = 1'b0;
    wire walk_left_dut;
    wire walk_left_ref;
    wire walk_right_dut;
    wire walk_right_ref;
    wire aaah_dut;
    wire aaah_ref;
    wire digging_dut;
    wire digging_ref;

    always #5 clk = ~clk;
    TopModule uut (
        .clk(clk),
        .areset(areset),
        .bump_left(bump_left),
        .bump_right(bump_right),
        .ground(ground),
        .dig(dig),
        .walk_left(walk_left_dut),
        .walk_right(walk_right_dut),
        .aaah(aaah_dut),
        .digging(digging_dut)
    );

    RefModule fg_gold (
        .clk(clk),
        .areset(areset),
        .bump_left(bump_left),
        .bump_right(bump_right),
        .ground(ground),
        .dig(dig),
        .walk_left(walk_left_ref),
        .walk_right(walk_right_ref),
        .aaah(aaah_ref),
        .digging(digging_ref)
    );

    localparam FG_N_BKT = 5;
    integer fg_bkt_tot  [0:4];
    integer fg_bkt_pass [0:4];
    integer fg_ff_cyc   [0:4];
    reg [3:0] fg_ff_in_v  [0:4];
    reg [3:0] fg_ff_dut_v [0:4];
    reg [3:0] fg_ff_ref_v [0:4];
    integer fg_w [0:4];

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
        fg_bkt_tot[4]  = 0;
        fg_bkt_pass[4] = 0;
        fg_ff_cyc[4]   = -1;
        fg_w[0] = 2;   // A_reset
        fg_w[1] = 3;   // B_steady
        fg_w[2] = 3;   // C_boundary
        fg_w[3] = 2;   // D_backtoback
        fg_w[4] = 3;   // F_longseq
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
            if ({ walk_left_dut , walk_right_dut , aaah_dut , digging_dut } === { walk_left_ref , walk_right_ref , aaah_ref , digging_ref }) begin
                fg_passed         = fg_passed + 1;
                fg_bkt_pass[fg_b] = fg_bkt_pass[fg_b] + 1;
            end else begin
                fg_failed = fg_failed + 1;
                if (fg_ff_cyc[fg_b] < 0) begin
                    fg_ff_cyc[fg_b]   = fg_cyc;
                    fg_ff_in_v[fg_b]  = { bump_left , bump_right , ground , dig };
                    fg_ff_dut_v[fg_b] = { walk_left_dut , walk_right_dut , aaah_dut , digging_dut };
                    fg_ff_ref_v[fg_b] = { walk_left_ref , walk_right_ref , aaah_ref , digging_ref };
                end
            end
        end
    endtask


    task fg_step(input integer fg_b);
        begin @(posedge clk); fg_sample_bucket(fg_b); end
    endtask


    initial begin
        // initial idle settle
        #1;

        //==== A_reset ====
        areset = 1'b1;
        bump_left = 1'h0;
        bump_right = 1'h0;
        ground = 1'h0;
        dig = 1'h0;
        fg_step(0); fg_step(0); fg_step(0);
        areset = 1'b0;
        fg_step(0); fg_step(0);

        //==== B_steady ====
        for (fg_i = 0; fg_i < 50; fg_i = fg_i + 1) begin
        bump_left = $random(fg_seed);
        bump_right = $random(fg_seed);
        ground = $random(fg_seed);
        dig = $random(fg_seed);
            fg_step(1);
        end

        //==== C_boundary ====
        // Fall-duration tests around the >=20 death threshold
        bump_left = 1'b0; bump_right = 1'b0; dig = 1'b0;

        // Test 1: Short fall (5 cycles) → survive
        areset = 1'b1; fg_step(2); areset = 1'b0;
        ground = 1'b1; fg_step(2); fg_step(2);
        ground = 1'b0;
        for (fg_i = 0; fg_i < 5; fg_i = fg_i + 1) fg_step(2);
        ground = 1'b1; fg_step(2); fg_step(2);

        // Test 2: Fall exactly 19 cycles → survive
        areset = 1'b1; fg_step(2); areset = 1'b0;
        ground = 1'b1; fg_step(2); fg_step(2);
        ground = 1'b0;
        for (fg_i = 0; fg_i < 19; fg_i = fg_i + 1) fg_step(2);
        ground = 1'b1; fg_step(2); fg_step(2);

        // Test 3: Fall exactly 20 cycles → key off-by-one threshold
        areset = 1'b1; fg_step(2); areset = 1'b0;
        ground = 1'b1; fg_step(2); fg_step(2);
        ground = 1'b0;
        for (fg_i = 0; fg_i < 20; fg_i = fg_i + 1) fg_step(2);
        ground = 1'b1; fg_step(2); fg_step(2);

        // Test 4: Fall exactly 21 cycles → dead
        areset = 1'b1; fg_step(2); areset = 1'b0;
        ground = 1'b1; fg_step(2); fg_step(2);
        ground = 1'b0;
        for (fg_i = 0; fg_i < 21; fg_i = fg_i + 1) fg_step(2);
        ground = 1'b1; fg_step(2); fg_step(2);

        // Test 5: Long fall (35 cycles) → dead, verify dead ignores inputs
        areset = 1'b1; fg_step(2); areset = 1'b0;
        ground = 1'b1; fg_step(2); fg_step(2);
        ground = 1'b0;
        for (fg_i = 0; fg_i < 35; fg_i = fg_i + 1) fg_step(2);
        ground = 1'b1; fg_step(2);
        bump_left = 1'b1; fg_step(2);
        bump_right = 1'b1; fg_step(2);
        dig = 1'b1; fg_step(2);
        ground = 1'b0; fg_step(2);
        ground = 1'b1; bump_left = 1'b0; bump_right = 1'b0; dig = 1'b0;
        fg_step(2);

        // Test 6: Dig then fall 20 cycles → threshold test from dig state
        areset = 1'b1; fg_step(2); areset = 1'b0;
        ground = 1'b1; dig = 1'b0; bump_left = 1'b0; bump_right = 1'b0;
        fg_step(2); fg_step(2);
        dig = 1'b1; fg_step(2); dig = 1'b0;
        fg_step(2); fg_step(2);
        ground = 1'b0;
        for (fg_i = 0; fg_i < 20; fg_i = fg_i + 1) fg_step(2);
        ground = 1'b1; fg_step(2); fg_step(2);

        //==== D_backtoback ====
        for (fg_i = 0; fg_i < 30; fg_i = fg_i + 1) begin
            if (fg_i[0] == 1'b0) begin
        bump_left = 1'h0;
        bump_right = 1'h0;
        ground = 1'h0;
        dig = 1'h0;
            end else begin
        bump_left = $random(fg_seed);
        bump_right = $random(fg_seed);
        ground = $random(fg_seed);
        dig = $random(fg_seed);
            end
            fg_step(3);
        end

        //==== F_longseq ====
        for (fg_i = 0; fg_i < 950; fg_i = fg_i + 1) begin
        bump_left = $random(fg_seed);
        bump_right = $random(fg_seed);
        ground = $random(fg_seed);
        dig = $random(fg_seed);
            areset = (($random(fg_seed) & 31) == 0) ? 1'b1 : 1'b0;
            fg_step(4);
        end
        areset = 1'b0;

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
            $display("[FORGE_BUCKET] A_reset=%0d/%0d B_steady=%0d/%0d C_boundary=%0d/%0d D_backtoback=%0d/%0d F_longseq=%0d/%0d",
                     fg_bkt_pass[0],
                     fg_bkt_tot[0],
                     fg_bkt_pass[1],
                     fg_bkt_tot[1],
                     fg_bkt_pass[2],
                     fg_bkt_tot[2],
                     fg_bkt_pass[3],
                     fg_bkt_tot[3],
                     fg_bkt_pass[4],
                     fg_bkt_tot[4]);

            for (fg_k = 0; fg_k < FG_N_BKT; fg_k = fg_k + 1) begin
                if (fg_ff_cyc[fg_k] >= 0) begin
                    case (fg_k)
                  0: $display("[FORGE_FIRSTFAIL] bucket=A_reset        cyc=%0d in=%01h dut=%01h ref=%01h",
                       fg_ff_cyc[0], fg_ff_in_v[0], fg_ff_dut_v[0], fg_ff_ref_v[0]);
                  1: $display("[FORGE_FIRSTFAIL] bucket=B_steady       cyc=%0d in=%01h dut=%01h ref=%01h",
                       fg_ff_cyc[1], fg_ff_in_v[1], fg_ff_dut_v[1], fg_ff_ref_v[1]);
                  2: $display("[FORGE_FIRSTFAIL] bucket=C_boundary     cyc=%0d in=%01h dut=%01h ref=%01h",
                       fg_ff_cyc[2], fg_ff_in_v[2], fg_ff_dut_v[2], fg_ff_ref_v[2]);
                  3: $display("[FORGE_FIRSTFAIL] bucket=D_backtoback   cyc=%0d in=%01h dut=%01h ref=%01h",
                       fg_ff_cyc[3], fg_ff_in_v[3], fg_ff_dut_v[3], fg_ff_ref_v[3]);
                  4: $display("[FORGE_FIRSTFAIL] bucket=F_longseq      cyc=%0d in=%01h dut=%01h ref=%01h",
                       fg_ff_cyc[4], fg_ff_in_v[4], fg_ff_dut_v[4], fg_ff_ref_v[4]);
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
// Golden reference — verbatim from Prob155_lemmings4_ref.sv
//==============================================================================
module RefModule (
  input clk,
  input areset,
  input bump_left,
  input bump_right,
  input ground,
  input dig,
  output walk_left,
  output walk_right,
  output aaah,
  output digging
);

  parameter WL=0, WR=1, FALLL=2, FALLR=3, DIGL=4, DIGR=5, DEAD=6;
  reg [2:0] state;
  reg [2:0] next;

  reg [4:0] fall_counter;

  always_comb begin
    case (state)
      WL: if (!ground) next = FALLL;
        else if (dig) next = DIGL;
        else if (bump_left) next = WR;
        else next = WL;
      WR:
        if (!ground) next = FALLR;
        else if (dig) next = DIGR;
        else if (bump_right) next = WL;
        else next = WR;
      FALLL: next = ground ? (fall_counter >= 20 ? DEAD : WL) : FALLL;
      FALLR: next = ground ? (fall_counter >= 20 ? DEAD : WR) : FALLR;
      DIGL: next = ground ? DIGL : FALLL;
      DIGR: next = ground ? DIGR : FALLR;
      DEAD: next = DEAD;
      default: next = WL;
    endcase
  end

  always @(posedge clk, posedge areset) begin
    if (areset) state <= WL;
      else state <= next;
  end

  always @(posedge clk) begin
    if (state == FALLL || state == FALLR) begin
      if (fall_counter < 20)
        fall_counter <= fall_counter + 1'b1;
    end
    else
      fall_counter <= 0;
  end

  assign walk_left = (state==WL);
  assign walk_right = (state==WR);
  assign aaah = (state == FALLL) || (state == FALLR);
  assign digging = (state == DIGL) || (state == DIGR);

endmodule
