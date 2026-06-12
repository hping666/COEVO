`timescale 1 ps/1 ps
//==============================================================================
// Auto-generated enhanced TB — Prob068_countbcd
// Category : sequential
// Buckets  : A_reset, B_steady, C_boundary, D_backtoback, F_longseq
// MaxCycles: 1000
// Generator: coevo/tb_gen/template.py
//==============================================================================

module testbench_enhanced;

    reg clk = 1'b0;
    reg reset = 1'b0;
    wire [3:1] ena_dut;
    wire [3:1] ena_ref;
    wire [15:0] q_dut;
    wire [15:0] q_ref;

    always #5 clk = ~clk;
    TopModule uut (
        .clk(clk),
        .reset(reset),
        .ena(ena_dut),
        .q(q_dut)
    );

    RefModule fg_gold (
        .clk(clk),
        .reset(reset),
        .ena(ena_ref),
        .q(q_ref)
    );

    localparam FG_N_BKT = 5;
    integer fg_bkt_tot  [0:4];
    integer fg_bkt_pass [0:4];
    integer fg_ff_cyc   [0:4];
    reg [0:0] fg_ff_in_v  [0:4];
    reg [18:0] fg_ff_dut_v [0:4];
    reg [18:0] fg_ff_ref_v [0:4];
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
        #20000000;
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
            if ({ ena_dut , q_dut } === { ena_ref , q_ref }) begin
                fg_passed         = fg_passed + 1;
                fg_bkt_pass[fg_b] = fg_bkt_pass[fg_b] + 1;
            end else begin
                fg_failed = fg_failed + 1;
                if (fg_ff_cyc[fg_b] < 0) begin
                    fg_ff_cyc[fg_b]   = fg_cyc;
                    fg_ff_in_v[fg_b]  = { 1'b0 };
                    fg_ff_dut_v[fg_b] = { ena_dut , q_dut };
                    fg_ff_ref_v[fg_b] = { ena_ref , q_ref };
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
        reset = 1'b1;

        fg_step(0); fg_step(0); fg_step(0);
        reset = 1'b0;
        fg_step(0); fg_step(0);

        //==== B_steady ====
        for (fg_i = 0; fg_i < 50; fg_i = fg_i + 1) begin

            fg_step(1);
        end

        //==== C_boundary ====
        // all-0

        fg_step(2); fg_step(2); fg_step(2);
        // all-1

        fg_step(2); fg_step(2); fg_step(2);
        // LSB only

        fg_step(2); fg_step(2); fg_step(2);
        // MSB only

        fg_step(2); fg_step(2); fg_step(2);
        // alternating

        fg_step(2); fg_step(2); fg_step(2);

        //==== D_backtoback ====
        for (fg_i = 0; fg_i < 30; fg_i = fg_i + 1) begin
            if (fg_i[0] == 1'b0) begin

            end else begin

            end
            fg_step(3);
        end

        //==== F_longseq ====
        // Full 4-digit BCD wrap coverage: reset once, then free-run ≥ 11000
        // cycles so the counter rolls through 0→9→10→99→100→999→1000→9999→0.
        reset = 1'b1;
        fg_step(4); fg_step(4);
        reset = 1'b0;
        for (fg_i = 0; fg_i < 11000; fg_i = fg_i + 1) begin
            fg_step(4);
        end
        // Additional stress: inject one reset and run another ~1000 cycles
        reset = 1'b1;
        fg_step(4);
        reset = 1'b0;
        for (fg_i = 0; fg_i < 1000; fg_i = fg_i + 1) begin
            fg_step(4);
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
                  0: $display("[FORGE_FIRSTFAIL] bucket=A_reset        cyc=%0d in=%01h dut=%05h ref=%05h",
                       fg_ff_cyc[0], fg_ff_in_v[0], fg_ff_dut_v[0], fg_ff_ref_v[0]);
                  1: $display("[FORGE_FIRSTFAIL] bucket=B_steady       cyc=%0d in=%01h dut=%05h ref=%05h",
                       fg_ff_cyc[1], fg_ff_in_v[1], fg_ff_dut_v[1], fg_ff_ref_v[1]);
                  2: $display("[FORGE_FIRSTFAIL] bucket=C_boundary     cyc=%0d in=%01h dut=%05h ref=%05h",
                       fg_ff_cyc[2], fg_ff_in_v[2], fg_ff_dut_v[2], fg_ff_ref_v[2]);
                  3: $display("[FORGE_FIRSTFAIL] bucket=D_backtoback   cyc=%0d in=%01h dut=%05h ref=%05h",
                       fg_ff_cyc[3], fg_ff_in_v[3], fg_ff_dut_v[3], fg_ff_ref_v[3]);
                  4: $display("[FORGE_FIRSTFAIL] bucket=F_longseq      cyc=%0d in=%01h dut=%05h ref=%05h",
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
// Golden reference — verbatim from Prob068_countbcd_ref.sv
//==============================================================================
module RefModule (
  input clk,
  input reset,
  output [3:1] ena,
  output reg [15:0] q
);

  wire [3:0] enable = { q[11:0]==12'h999, q[7:0]==8'h99, q[3:0] == 4'h9, 1'b1};
  assign ena = enable[3:1];
  always @(posedge clk)
    for (int i=0;i<4;i++) begin
      if (reset || (q[i*4 +:4] == 9 && enable[i]))
        q[i*4 +:4] <= 0;
      else if (enable[i])
        q[i*4 +:4] <= q[i*4 +:4]+1;
    end

endmodule
