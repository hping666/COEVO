`timescale 1 ps/1 ps
//==============================================================================
// Auto-generated enhanced TB — Prob154_fsm_ps2data
// Category : sequential+pulse
// Buckets  : A_reset, B_steady, C_boundary, D_backtoback, F_longseq, G_pulse_edge
// MaxCycles: 1000
// Generator: coevo/tb_gen/template.py
//==============================================================================

module testbench_enhanced;

    reg clk = 1'b0;
    reg reset = 1'b0;
    reg [7:0] in = 0;
    wire [23:0] out_bytes_dut;
    wire [23:0] out_bytes_ref;
    wire done_dut;
    wire done_ref;

    always #5 clk = ~clk;
    TopModule uut (
        .clk(clk),
        .in(in),
        .reset(reset),
        .out_bytes(out_bytes_dut),
        .done(done_dut)
    );

    RefModule fg_gold (
        .clk(clk),
        .in(in),
        .reset(reset),
        .out_bytes(out_bytes_ref),
        .done(done_ref)
    );

    localparam FG_N_BKT = 6;
    integer fg_bkt_tot  [0:5];
    integer fg_bkt_pass [0:5];
    integer fg_ff_cyc   [0:5];
    reg [7:0] fg_ff_in_v  [0:5];
    reg [24:0] fg_ff_dut_v [0:5];
    reg [24:0] fg_ff_ref_v [0:5];
    integer fg_w [0:5];
    reg fg_prev_done_dut = 1'b0;
    reg fg_prev_done_ref = 1'b0;

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
        fg_bkt_tot[5]  = 0;
        fg_bkt_pass[5] = 0;
        fg_ff_cyc[5]   = -1;
        fg_w[0] = 2;   // A_reset
        fg_w[1] = 3;   // B_steady
        fg_w[2] = 3;   // C_boundary
        fg_w[3] = 2;   // D_backtoback
        fg_w[4] = 3;   // F_longseq
        fg_w[5] = 10;   // G_pulse_edge
    end

    initial begin
        #2000000;
        $display("[FORGE_RESULT] TIMEOUT TOTAL=%0d PASSED=%0d FAILED=%0d",
                 fg_total, fg_passed, fg_failed);
        $finish;
    end


    task fg_sample_bucket(input integer fg_b);
        reg fg_ref_rising;
        reg fg_dut_rising;
        begin
            #1; // settle
            fg_total = fg_total + 1;
            fg_cyc   = fg_cyc + 1;
            fg_bkt_tot[fg_b] = fg_bkt_tot[fg_b] + 1;
            if ({ out_bytes_dut , done_dut } === { out_bytes_ref , done_ref }) begin
                fg_passed         = fg_passed + 1;
                fg_bkt_pass[fg_b] = fg_bkt_pass[fg_b] + 1;
            end else begin
                fg_failed = fg_failed + 1;
                if (fg_ff_cyc[fg_b] < 0) begin
                    fg_ff_cyc[fg_b]   = fg_cyc;
                    fg_ff_in_v[fg_b]  = { in };
                    fg_ff_dut_v[fg_b] = { out_bytes_dut , done_dut };
                    fg_ff_ref_v[fg_b] = { out_bytes_ref , done_ref };
                end
            end

            //--- G_pulse_edge bucket: rising-edge events on 'done' ---
            fg_ref_rising = (done_ref === 1'b1) && (fg_prev_done_ref !== 1'b1);
            fg_dut_rising = (done_dut === 1'b1) && (fg_prev_done_dut !== 1'b1);
            if (fg_ref_rising || fg_dut_rising) begin
                fg_bkt_tot[5] = fg_bkt_tot[5] + 1;
                if (fg_ref_rising && fg_dut_rising) begin
                    fg_bkt_pass[5] = fg_bkt_pass[5] + 1;
                end else if (fg_ff_cyc[5] < 0) begin
                    fg_ff_cyc[5]   = fg_cyc;
                    fg_ff_in_v[5]  = { in };
                    fg_ff_dut_v[5] = { out_bytes_dut , done_dut };
                    fg_ff_ref_v[5] = { out_bytes_ref , done_ref };
                end
            end
            fg_prev_done_ref = done_ref;
            fg_prev_done_dut = done_dut;
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
        in = 8'h0;
        fg_step(0); fg_step(0); fg_step(0);
        reset = 1'b0;
        fg_step(0); fg_step(0);

        //==== B_steady ====
        for (fg_i = 0; fg_i < 50; fg_i = fg_i + 1) begin
        in = $random(fg_seed);
            fg_step(1);
        end

        //==== C_boundary ====
        // all-0
        in = 8'h0;
        fg_step(2); fg_step(2); fg_step(2);
        // all-1
        in = {8{1'b1}};
        fg_step(2); fg_step(2); fg_step(2);
        // LSB only
        in = 8'h1;
        fg_step(2); fg_step(2); fg_step(2);
        // MSB only
        in = {1'b1, 7'h0};
        fg_step(2); fg_step(2); fg_step(2);
        // alternating
        in = {1{8'h55}};
        fg_step(2); fg_step(2); fg_step(2);

        //==== D_backtoback ====
        for (fg_i = 0; fg_i < 30; fg_i = fg_i + 1) begin
            if (fg_i[0] == 1'b0) begin
        in = 8'h0;
            end else begin
        in = $random(fg_seed);
            end
            fg_step(3);
        end

        //==== F_longseq ====
        for (fg_i = 0; fg_i < 950; fg_i = fg_i + 1) begin
        in = $random(fg_seed);
            reset = (($random(fg_seed) & 31) == 0) ? 1'b1 : 1'b0;
            fg_step(4);
        end
        reset = 1'b0;

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
            $display("[FORGE_BUCKET] A_reset=%0d/%0d B_steady=%0d/%0d C_boundary=%0d/%0d D_backtoback=%0d/%0d F_longseq=%0d/%0d G_pulse_edge=%0d/%0d",
                     fg_bkt_pass[0],
                     fg_bkt_tot[0],
                     fg_bkt_pass[1],
                     fg_bkt_tot[1],
                     fg_bkt_pass[2],
                     fg_bkt_tot[2],
                     fg_bkt_pass[3],
                     fg_bkt_tot[3],
                     fg_bkt_pass[4],
                     fg_bkt_tot[4],
                     fg_bkt_pass[5],
                     fg_bkt_tot[5]);

            for (fg_k = 0; fg_k < FG_N_BKT; fg_k = fg_k + 1) begin
                if (fg_ff_cyc[fg_k] >= 0) begin
                    case (fg_k)
                  0: $display("[FORGE_FIRSTFAIL] bucket=A_reset        cyc=%0d in=%02h dut=%07h ref=%07h",
                       fg_ff_cyc[0], fg_ff_in_v[0], fg_ff_dut_v[0], fg_ff_ref_v[0]);
                  1: $display("[FORGE_FIRSTFAIL] bucket=B_steady       cyc=%0d in=%02h dut=%07h ref=%07h",
                       fg_ff_cyc[1], fg_ff_in_v[1], fg_ff_dut_v[1], fg_ff_ref_v[1]);
                  2: $display("[FORGE_FIRSTFAIL] bucket=C_boundary     cyc=%0d in=%02h dut=%07h ref=%07h",
                       fg_ff_cyc[2], fg_ff_in_v[2], fg_ff_dut_v[2], fg_ff_ref_v[2]);
                  3: $display("[FORGE_FIRSTFAIL] bucket=D_backtoback   cyc=%0d in=%02h dut=%07h ref=%07h",
                       fg_ff_cyc[3], fg_ff_in_v[3], fg_ff_dut_v[3], fg_ff_ref_v[3]);
                  4: $display("[FORGE_FIRSTFAIL] bucket=F_longseq      cyc=%0d in=%02h dut=%07h ref=%07h",
                       fg_ff_cyc[4], fg_ff_in_v[4], fg_ff_dut_v[4], fg_ff_ref_v[4]);
                  5: $display("[FORGE_FIRSTFAIL] bucket=G_pulse_edge   cyc=%0d in=%02h dut=%07h ref=%07h",
                       fg_ff_cyc[5], fg_ff_in_v[5], fg_ff_dut_v[5], fg_ff_ref_v[5]);
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
// Golden reference — verbatim from Prob154_fsm_ps2data_ref.sv
//==============================================================================
module RefModule (
  input clk,
  input [7:0] in,
  input reset,
  output [23:0] out_bytes,
  output done
);

  parameter BYTE1=0, BYTE2=1, BYTE3=2, DONE=3;
  reg [1:0] state;
  reg [1:0] next;

  wire in3 = in[3];

  always_comb begin
    case (state)
      BYTE1: next = in3 ? BYTE2 : BYTE1;
      BYTE2: next = BYTE3;
      BYTE3: next = DONE;
      DONE: next = in3 ? BYTE2 : BYTE1;
    endcase
  end

  always @(posedge clk) begin
    if (reset) state <= BYTE1;
      else state <= next;
  end

  assign done = (state==DONE);

  reg [23:0] out_bytes_r;
  always @(posedge clk)
    out_bytes_r <= {out_bytes_r[15:0], in};

  // Implementations may vary: Allow user to do anything while the output
  // doesn't have to be valid.

  assign out_bytes = done ? out_bytes_r : 'x;

endmodule
