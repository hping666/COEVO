`timescale 1 ps/1 ps
//==============================================================================
// Auto-generated enhanced TB — Prob099_m2014_q6c
// Category : combinational
// Buckets  : B_steady, C_boundary, D_backtoback, F_longseq
// MaxCycles: 1000
// Generator: coevo/tb_gen/template.py
//==============================================================================

module testbench_enhanced;

    reg [5:0] y = 0;
    reg w = 1'b0;
    wire Y1_dut;
    wire Y1_ref;
    wire Y3_dut;
    wire Y3_ref;

    TopModule uut (
        .y(y),
        .w(w),
        .Y1(Y1_dut),
        .Y3(Y3_dut)
    );

    RefModule fg_gold (
        .y(y),
        .w(w),
        .Y1(Y1_ref),
        .Y3(Y3_ref)
    );

    localparam FG_N_BKT = 4;
    integer fg_bkt_tot  [0:3];
    integer fg_bkt_pass [0:3];
    integer fg_ff_cyc   [0:3];
    reg [6:0] fg_ff_in_v  [0:3];
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
            if ({ Y1_dut , Y3_dut } === { Y1_ref , Y3_ref }) begin
                fg_passed         = fg_passed + 1;
                fg_bkt_pass[fg_b] = fg_bkt_pass[fg_b] + 1;
            end else begin
                fg_failed = fg_failed + 1;
                if (fg_ff_cyc[fg_b] < 0) begin
                    fg_ff_cyc[fg_b]   = fg_cyc;
                    fg_ff_in_v[fg_b]  = { y , w };
                    fg_ff_dut_v[fg_b] = { Y1_dut , Y3_dut };
                    fg_ff_ref_v[fg_b] = { Y1_ref , Y3_ref };
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
        y = $random(fg_seed);
        w = $random(fg_seed);
            fg_step(0);
        end

        //==== C_boundary ====
        // all-0
        y = 6'h0;
        w = 1'h0;
        fg_step(1); fg_step(1); fg_step(1);
        // all-1
        y = {6{1'b1}};
        w = {1{1'b1}};
        fg_step(1); fg_step(1); fg_step(1);
        // LSB only
        y = 6'h1;
        w = 1'h1;
        fg_step(1); fg_step(1); fg_step(1);
        // MSB only
        y = {1'b1, 5'h0};
        w = 1'b1;
        fg_step(1); fg_step(1); fg_step(1);
        // alternating
        y = 6'h55;
        w = 1'h5;
        fg_step(1); fg_step(1); fg_step(1);

        //==== D_backtoback ====
        for (fg_i = 0; fg_i < 30; fg_i = fg_i + 1) begin
            if (fg_i[0] == 1'b0) begin
        y = 6'h0;
        w = 1'h0;
            end else begin
        y = $random(fg_seed);
        w = $random(fg_seed);
            end
            fg_step(2);
        end

        //==== F_longseq ====
        for (fg_i = 0; fg_i < 950; fg_i = fg_i + 1) begin
        y = $random(fg_seed);
        w = $random(fg_seed);

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
                  0: $display("[FORGE_FIRSTFAIL] bucket=B_steady       cyc=%0d in=%02h dut=%01h ref=%01h",
                       fg_ff_cyc[0], fg_ff_in_v[0], fg_ff_dut_v[0], fg_ff_ref_v[0]);
                  1: $display("[FORGE_FIRSTFAIL] bucket=C_boundary     cyc=%0d in=%02h dut=%01h ref=%01h",
                       fg_ff_cyc[1], fg_ff_in_v[1], fg_ff_dut_v[1], fg_ff_ref_v[1]);
                  2: $display("[FORGE_FIRSTFAIL] bucket=D_backtoback   cyc=%0d in=%02h dut=%01h ref=%01h",
                       fg_ff_cyc[2], fg_ff_in_v[2], fg_ff_dut_v[2], fg_ff_ref_v[2]);
                  3: $display("[FORGE_FIRSTFAIL] bucket=F_longseq      cyc=%0d in=%02h dut=%01h ref=%01h",
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
// Golden reference — verbatim from Prob099_m2014_q6c_ref.sv
//==============================================================================
module RefModule (
  input  [5:0] y,
  input        w,
  output       Y1,
  output       Y3
);

  assign Y1 = y[0]&~w;
  assign Y3 = (y[1]|y[2]|y[4]|y[5]) & w;

endmodule
