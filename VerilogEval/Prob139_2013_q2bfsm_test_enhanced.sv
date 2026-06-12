`timescale 1 ps/1 ps
//==============================================================================
// Auto-generated enhanced TB — Prob139_2013_q2bfsm
// Category : sequential
// Buckets  : A_reset, B_steady, C_boundary, D_backtoback, F_longseq
// MaxCycles: 1000
// Generator: coevo/tb_gen/template.py
//==============================================================================

module testbench_enhanced;

    reg clk = 1'b0;
    reg resetn = 1'b1;
    reg x = 1'b0;
    reg y = 1'b0;
    wire f_dut;
    wire f_ref;
    wire g_dut;
    wire g_ref;

    always #5 clk = ~clk;
    TopModule uut (
        .clk(clk),
        .resetn(resetn),
        .x(x),
        .y(y),
        .f(f_dut),
        .g(g_dut)
    );

    RefModule fg_gold (
        .clk(clk),
        .resetn(resetn),
        .x(x),
        .y(y),
        .f(f_ref),
        .g(g_ref)
    );

    localparam FG_N_BKT = 5;
    integer fg_bkt_tot  [0:4];
    integer fg_bkt_pass [0:4];
    integer fg_ff_cyc   [0:4];
    reg [1:0] fg_ff_in_v  [0:4];
    reg [1:0] fg_ff_dut_v [0:4];
    reg [1:0] fg_ff_ref_v [0:4];
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
            if ({ f_dut , g_dut } === { f_ref , g_ref }) begin
                fg_passed         = fg_passed + 1;
                fg_bkt_pass[fg_b] = fg_bkt_pass[fg_b] + 1;
            end else begin
                fg_failed = fg_failed + 1;
                if (fg_ff_cyc[fg_b] < 0) begin
                    fg_ff_cyc[fg_b]   = fg_cyc;
                    fg_ff_in_v[fg_b]  = { x , y };
                    fg_ff_dut_v[fg_b] = { f_dut , g_dut };
                    fg_ff_ref_v[fg_b] = { f_ref , g_ref };
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
        resetn = 1'b0;
        x = 1'h0;
        y = 1'h0;
        fg_step(0); fg_step(0); fg_step(0);
        resetn = 1'b1;
        fg_step(0); fg_step(0);

        //==== B_steady ====
        for (fg_i = 0; fg_i < 50; fg_i = fg_i + 1) begin
        x = $random(fg_seed);
        y = $random(fg_seed);
            fg_step(1);
        end

        //==== C_boundary ====
        // FSM-specific path tests for pattern detector (detects x=1,0,1)

        // Test 0: Race condition — release resetn AT posedge to expose
        // comb dependency on resetn in state A (ref: A→B unconditional)
        resetn = 1'b0; x = 1'b0; y = 1'b0;
        fg_step(2); fg_step(2);
        @(posedge clk);
        resetn = 1'b1;           // blocking at posedge creates race
        fg_sample_bucket(2);     // ref: A→B (f=1). Buggy DUT: still A (f=0)
        fg_step(2);              // ref: B→S0. Buggy DUT: A→B
        fg_step(2);              // check propagation

        // Test 0b: Race again with full pattern after race-triggered reset
        resetn = 1'b0; fg_step(2); fg_step(2);
        @(posedge clk);
        resetn = 1'b1;
        fg_sample_bucket(2);
        fg_step(2); fg_step(2);
        x = 1'b1; y = 1'b0; fg_step(2);
        x = 1'b0; fg_step(2);
        x = 1'b1; fg_step(2);         // pattern detected → G1
        y = 1'b0; fg_step(2);         // G1→G2
        fg_step(2);                    // G2→P0
        fg_step(2);

        // Test 1: Complete path → pattern match → y=0,0 → g stays 0 (P0)
        resetn = 1'b0; fg_step(2); fg_step(2);
        resetn = 1'b1; fg_step(2);  // A→B (f=1)
        fg_step(2);                  // B→S0 (f=0)
        x = 1'b1; y = 1'b0; fg_step(2);  // S0→S1
        x = 1'b0; fg_step(2);             // S1→S10
        x = 1'b1; fg_step(2);             // S10→G1 (g=1)
        x = 1'b0; y = 1'b0; fg_step(2);  // G1→G2 (g=1)
        fg_step(2);                        // G2→P0 (g=0)
        fg_step(2); fg_step(2);            // P0 terminal (g=0)

        // Test 2: Pattern match → y=1 in first cycle → g=1 forever (P1)
        resetn = 1'b0; fg_step(2); fg_step(2);
        resetn = 1'b1; fg_step(2); fg_step(2);
        x = 1'b1; y = 1'b0; fg_step(2);
        x = 1'b0; fg_step(2);
        x = 1'b1; fg_step(2);             // G1
        x = 1'b0; y = 1'b1; fg_step(2);  // G1→P1 (y=1)
        fg_step(2); fg_step(2);            // P1 terminal (g=1)

        // Test 3: Pattern match → y=0 then y=1 → g=1 forever (P1)
        resetn = 1'b0; fg_step(2); fg_step(2);
        resetn = 1'b1; fg_step(2); fg_step(2);
        x = 1'b1; y = 1'b0; fg_step(2);
        x = 1'b0; fg_step(2);
        x = 1'b1; fg_step(2);             // G1
        y = 1'b0; fg_step(2);             // G1→G2
        y = 1'b1; fg_step(2);             // G2→P1
        fg_step(2); fg_step(2);            // P1 terminal

        // Test 4: Near-miss pattern 1,0,0 → no trigger, restart
        resetn = 1'b0; fg_step(2); fg_step(2);
        resetn = 1'b1; fg_step(2); fg_step(2);
        x = 1'b1; y = 1'b0; fg_step(2);  // S0→S1
        x = 1'b0; fg_step(2);             // S1→S10
        x = 1'b0; fg_step(2);             // S10→S0 (no match)
        fg_step(2); fg_step(2);

        // Test 5: Extended 1s before pattern: 1,1,1,0,1
        resetn = 1'b0; fg_step(2); fg_step(2);
        resetn = 1'b1; fg_step(2); fg_step(2);
        x = 1'b1; y = 1'b0; fg_step(2);  // S0→S1
        x = 1'b1; fg_step(2);             // S1→S1 (stays)
        x = 1'b1; fg_step(2);             // S1→S1
        x = 1'b0; fg_step(2);             // S1→S10
        x = 1'b1; fg_step(2);             // S10→G1 → pattern detected
        y = 1'b0; fg_step(2);
        fg_step(2); fg_step(2);

        // Test 6: Reset during pattern detection
        resetn = 1'b0; fg_step(2); fg_step(2);
        resetn = 1'b1; fg_step(2); fg_step(2);
        x = 1'b1; y = 1'b0; fg_step(2);  // S0→S1
        x = 1'b0; fg_step(2);             // S1→S10
        resetn = 1'b0; fg_step(2);        // reset mid-pattern
        resetn = 1'b1; fg_step(2);        // restart: A→B
        fg_step(2);                        // B→S0
        x = 1'b1; fg_step(2);             // pattern from scratch
        x = 1'b0; fg_step(2);
        x = 1'b1; fg_step(2);             // detect
        y = 1'b1; fg_step(2);             // G1→P1
        fg_step(2);

        //==== D_backtoback ====
        for (fg_i = 0; fg_i < 30; fg_i = fg_i + 1) begin
            if (fg_i[0] == 1'b0) begin
        x = 1'h0;
        y = 1'h0;
            end else begin
        x = $random(fg_seed);
        y = $random(fg_seed);
            end
            fg_step(3);
        end

        //==== F_longseq ====
        for (fg_i = 0; fg_i < 950; fg_i = fg_i + 1) begin
        x = $random(fg_seed);
        y = $random(fg_seed);
            resetn = (($random(fg_seed) & 31) == 0) ? 1'b0 : 1'b1;
            fg_step(4);
        end
        resetn = 1'b1;

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
// Golden reference — verbatim from Prob139_2013_q2bfsm_ref.sv
//==============================================================================
module RefModule (
  input clk,
  input resetn,
  input x,
  input y,
  output f,
  output g
);

  parameter A=0, B=1, S0=2, S1=3, S10=4, G1=5, G2=6, P0=7, P1=8;
  reg [3:0] state, next;

  always @(posedge clk) begin
    if (~resetn) state <= A;
    else state <= next;
  end

  always_comb begin
    case (state)
      A: next = B;
      B: next = S0;
      S0: next = x ? S1 : S0;
      S1: next = x ? S1 : S10;
      S10: next = x? G1 : S0;
      G1: next = y ? P1 : G2;
      G2: next = y ? P1 : P0;
      P0: next = P0;
      P1: next = P1;
      default: next = 'x;
    endcase
  end

  assign f = (state == B);
  assign g = (state == G1) || (state == G2) || (state == P1);

endmodule
