`timescale 1 ps/1 ps
//==============================================================================
// Auto-generated enhanced TB — Prob147_circuit10
// Category : sequential
// Buckets  : B_steady, C_boundary, D_backtoback, F_longseq
// MaxCycles: 1000
// Generator: coevo/tb_gen/template.py
//==============================================================================

module testbench_enhanced;

    reg clk = 1'b0;
    reg a = 1'b0;
    reg b = 1'b0;
    wire q_dut;
    wire q_ref;
    wire state_dut;
    wire state_ref;

    always #5 clk = ~clk;
    TopModule uut (
        .clk(clk),
        .a(a),
        .b(b),
        .q(q_dut),
        .state(state_dut)
    );

    RefModule fg_gold (
        .clk(clk),
        .a(a),
        .b(b),
        .q(q_ref),
        .state(state_ref)
    );

    localparam FG_N_BKT = 4;
    integer fg_bkt_tot  [0:3];
    integer fg_bkt_pass [0:3];
    integer fg_ff_cyc   [0:3];
    reg [1:0] fg_ff_in_v  [0:3];
    reg [1:0] fg_ff_dut_v [0:3];
    reg [1:0] fg_ff_ref_v [0:3];
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
            if ({ q_dut , state_dut } === { q_ref , state_ref }) begin
                fg_passed         = fg_passed + 1;
                fg_bkt_pass[fg_b] = fg_bkt_pass[fg_b] + 1;
            end else begin
                fg_failed = fg_failed + 1;
                if (fg_ff_cyc[fg_b] < 0) begin
                    fg_ff_cyc[fg_b]   = fg_cyc;
                    fg_ff_in_v[fg_b]  = { a , b };
                    fg_ff_dut_v[fg_b] = { q_dut , state_dut };
                    fg_ff_ref_v[fg_b] = { q_ref , state_ref };
                end
            end
        end
    endtask


    // 2-phase step: check after posedge, change inputs mid-cycle, check again.
    // Detects DUTs that register q instead of computing it combinationally.
    task fg_step(input integer fg_b);
        begin
            @(posedge clk); #2;
            fg_sample_bucket(fg_b);        // check after posedge settle
            a = $random(fg_seed) & 1;      // change inputs mid high-phase
            b = $random(fg_seed) & 1;
            #2;
            fg_sample_bucket(fg_b);        // combinational q must track immediately
        end
    endtask


    initial begin
        // initial idle settle
        #1;

        //==== B_steady ====
        for (fg_i = 0; fg_i < 50; fg_i = fg_i + 1) begin
        a = $random(fg_seed);
        b = $random(fg_seed);
            fg_step(0);
        end

        //==== C_boundary ====
        // Deterministic init: force c=0 by running {0,0} for 3 cycles
        a = 1'b0; b = 1'b0;
        fg_step(1); fg_step(1); fg_step(1);
        // Majority carry-in test (exercises c=a&b|a&c|b&c):
        a = 1'b1; b = 1'b1; fg_step(1);  // c→1 (a&b=1)
        a = 1'b0; b = 1'b0; fg_step(1);  // c stays 1 (majority(0,0,1)=0→c→0)
        a = 1'b1; b = 1'b0; fg_step(1);  // c=maj(1,0,0)=0
        a = 1'b0; b = 1'b1; fg_step(1);  // c=maj(0,1,0)=0
        a = 1'b1; b = 1'b1; fg_step(1);  // c→1
        a = 1'b1; b = 1'b0; fg_step(1);  // c=maj(1,0,1)=1
        a = 1'b0; b = 1'b1; fg_step(1);  // c=maj(0,1,1)=1
        a = 1'b0; b = 1'b0; fg_step(1);  // c=maj(0,0,1)=0
        a = 1'b0; b = 1'b0; fg_step(1);  // c=0
        // Original TB toggle pattern: 1,2,3,0,3,3,3,2,1,0,0,0
        a = 1'b1; b = 1'b0; fg_step(1);
        a = 1'b0; b = 1'b1; fg_step(1);
        a = 1'b1; b = 1'b1; fg_step(1);
        a = 1'b0; b = 1'b0; fg_step(1);
        a = 1'b1; b = 1'b1; fg_step(1);
        a = 1'b1; b = 1'b1; fg_step(1);
        a = 1'b1; b = 1'b1; fg_step(1);
        a = 1'b0; b = 1'b1; fg_step(1);
        a = 1'b1; b = 1'b0; fg_step(1);
        a = 1'b0; b = 1'b0; fg_step(1);
        a = 1'b0; b = 1'b0; fg_step(1);
        a = 1'b0; b = 1'b0; fg_step(1);

        //==== D_backtoback ====
        for (fg_i = 0; fg_i < 30; fg_i = fg_i + 1) begin
            if (fg_i[0] == 1'b0) begin
        a = 1'h0;
        b = 1'h0;
            end else begin
        a = $random(fg_seed);
        b = $random(fg_seed);
            end
            fg_step(2);
        end

        //==== F_longseq ====
        for (fg_i = 0; fg_i < 950; fg_i = fg_i + 1) begin
        a = $random(fg_seed);
        b = $random(fg_seed);

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
                  0: $display("[FORGE_FIRSTFAIL] bucket=B_steady       cyc=%0d in=%01h dut=%01h ref=%01h",
                       fg_ff_cyc[0], fg_ff_in_v[0], fg_ff_dut_v[0], fg_ff_ref_v[0]);
                  1: $display("[FORGE_FIRSTFAIL] bucket=C_boundary     cyc=%0d in=%01h dut=%01h ref=%01h",
                       fg_ff_cyc[1], fg_ff_in_v[1], fg_ff_dut_v[1], fg_ff_ref_v[1]);
                  2: $display("[FORGE_FIRSTFAIL] bucket=D_backtoback   cyc=%0d in=%01h dut=%01h ref=%01h",
                       fg_ff_cyc[2], fg_ff_in_v[2], fg_ff_dut_v[2], fg_ff_ref_v[2]);
                  3: $display("[FORGE_FIRSTFAIL] bucket=F_longseq      cyc=%0d in=%01h dut=%01h ref=%01h",
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
// Golden reference — verbatim from Prob147_circuit10_ref.sv
//==============================================================================
module RefModule (
  input clk,
  input a,
  input b,
  output q,
  output state
);

  reg c;
  always @(posedge clk)
    c <= a&b | a&c | b&c;

  assign q = a^b^c;
  assign state = c;

endmodule
