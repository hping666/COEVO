`timescale 1 ps/1 ps
//==============================================================================
// Auto-generated enhanced TB — Prob097_mux9to1v
// Category : combinational
// Buckets  : B_steady, C_boundary, D_backtoback, F_longseq
// MaxCycles: 1000
// Generator: coevo/tb_gen/template.py
//==============================================================================

module testbench_enhanced;

    reg [15:0] a = 0;
    reg [15:0] b = 0;
    reg [15:0] c = 0;
    reg [15:0] d = 0;
    reg [15:0] e = 0;
    reg [15:0] f = 0;
    reg [15:0] g = 0;
    reg [15:0] h = 0;
    reg [15:0] i = 0;
    reg [3:0] sel = 0;
    wire [15:0] out_dut;
    wire [15:0] out_ref;

    TopModule uut (
        .a(a),
        .b(b),
        .c(c),
        .d(d),
        .e(e),
        .f(f),
        .g(g),
        .h(h),
        .i(i),
        .sel(sel),
        .out(out_dut)
    );

    RefModule fg_gold (
        .a(a),
        .b(b),
        .c(c),
        .d(d),
        .e(e),
        .f(f),
        .g(g),
        .h(h),
        .i(i),
        .sel(sel),
        .out(out_ref)
    );

    localparam FG_N_BKT = 4;
    integer fg_bkt_tot  [0:3];
    integer fg_bkt_pass [0:3];
    integer fg_ff_cyc   [0:3];
    reg [147:0] fg_ff_in_v  [0:3];
    reg [15:0] fg_ff_dut_v [0:3];
    reg [15:0] fg_ff_ref_v [0:3];
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
            if ({ out_dut } === { out_ref }) begin
                fg_passed         = fg_passed + 1;
                fg_bkt_pass[fg_b] = fg_bkt_pass[fg_b] + 1;
            end else begin
                fg_failed = fg_failed + 1;
                if (fg_ff_cyc[fg_b] < 0) begin
                    fg_ff_cyc[fg_b]   = fg_cyc;
                    fg_ff_in_v[fg_b]  = { a , b , c , d , e , f , g , h , i , sel };
                    fg_ff_dut_v[fg_b] = { out_dut };
                    fg_ff_ref_v[fg_b] = { out_ref };
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
        a = $random(fg_seed);
        b = $random(fg_seed);
        c = $random(fg_seed);
        d = $random(fg_seed);
        e = $random(fg_seed);
        f = $random(fg_seed);
        g = $random(fg_seed);
        h = $random(fg_seed);
        i = $random(fg_seed);
        sel = $random(fg_seed);
            fg_step(0);
        end

        //==== C_boundary ====
        // all-0
        a = 16'h0;
        b = 16'h0;
        c = 16'h0;
        d = 16'h0;
        e = 16'h0;
        f = 16'h0;
        g = 16'h0;
        h = 16'h0;
        i = 16'h0;
        sel = 4'h0;
        fg_step(1); fg_step(1); fg_step(1);
        // all-1
        a = {16{1'b1}};
        b = {16{1'b1}};
        c = {16{1'b1}};
        d = {16{1'b1}};
        e = {16{1'b1}};
        f = {16{1'b1}};
        g = {16{1'b1}};
        h = {16{1'b1}};
        i = {16{1'b1}};
        sel = {4{1'b1}};
        fg_step(1); fg_step(1); fg_step(1);
        // LSB only
        a = 16'h1;
        b = 16'h1;
        c = 16'h1;
        d = 16'h1;
        e = 16'h1;
        f = 16'h1;
        g = 16'h1;
        h = 16'h1;
        i = 16'h1;
        sel = 4'h1;
        fg_step(1); fg_step(1); fg_step(1);
        // MSB only
        a = {1'b1, 15'h0};
        b = {1'b1, 15'h0};
        c = {1'b1, 15'h0};
        d = {1'b1, 15'h0};
        e = {1'b1, 15'h0};
        f = {1'b1, 15'h0};
        g = {1'b1, 15'h0};
        h = {1'b1, 15'h0};
        i = {1'b1, 15'h0};
        sel = {1'b1, 3'h0};
        fg_step(1); fg_step(1); fg_step(1);
        // alternating
        a = {2{8'h55}};
        b = {2{8'h55}};
        c = {2{8'h55}};
        d = {2{8'h55}};
        e = {2{8'h55}};
        f = {2{8'h55}};
        g = {2{8'h55}};
        h = {2{8'h55}};
        i = {2{8'h55}};
        sel = 4'h5;
        fg_step(1); fg_step(1); fg_step(1);

        //==== D_backtoback ====
        for (fg_i = 0; fg_i < 30; fg_i = fg_i + 1) begin
            if (fg_i[0] == 1'b0) begin
        a = 16'h0;
        b = 16'h0;
        c = 16'h0;
        d = 16'h0;
        e = 16'h0;
        f = 16'h0;
        g = 16'h0;
        h = 16'h0;
        i = 16'h0;
        sel = 4'h0;
            end else begin
        a = $random(fg_seed);
        b = $random(fg_seed);
        c = $random(fg_seed);
        d = $random(fg_seed);
        e = $random(fg_seed);
        f = $random(fg_seed);
        g = $random(fg_seed);
        h = $random(fg_seed);
        i = $random(fg_seed);
        sel = $random(fg_seed);
            end
            fg_step(2);
        end

        //==== F_longseq ====
        for (fg_i = 0; fg_i < 950; fg_i = fg_i + 1) begin
        a = $random(fg_seed);
        b = $random(fg_seed);
        c = $random(fg_seed);
        d = $random(fg_seed);
        e = $random(fg_seed);
        f = $random(fg_seed);
        g = $random(fg_seed);
        h = $random(fg_seed);
        i = $random(fg_seed);
        sel = $random(fg_seed);

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
                  0: $display("[FORGE_FIRSTFAIL] bucket=B_steady       cyc=%0d in=%037h dut=%04h ref=%04h",
                       fg_ff_cyc[0], fg_ff_in_v[0], fg_ff_dut_v[0], fg_ff_ref_v[0]);
                  1: $display("[FORGE_FIRSTFAIL] bucket=C_boundary     cyc=%0d in=%037h dut=%04h ref=%04h",
                       fg_ff_cyc[1], fg_ff_in_v[1], fg_ff_dut_v[1], fg_ff_ref_v[1]);
                  2: $display("[FORGE_FIRSTFAIL] bucket=D_backtoback   cyc=%0d in=%037h dut=%04h ref=%04h",
                       fg_ff_cyc[2], fg_ff_in_v[2], fg_ff_dut_v[2], fg_ff_ref_v[2]);
                  3: $display("[FORGE_FIRSTFAIL] bucket=F_longseq      cyc=%0d in=%037h dut=%04h ref=%04h",
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
// Golden reference — verbatim from Prob097_mux9to1v_ref.sv
//==============================================================================
module RefModule (
  input [15:0] a,
  input [15:0] b,
  input [15:0] c,
  input [15:0] d,
  input [15:0] e,
  input [15:0] f,
  input [15:0] g,
  input [15:0] h,
  input [15:0] i,
  input [3:0] sel,
  output logic [15:0] out
);

  always @(*) begin
    out = '1;
    case (sel)
      4'h0: out = a;
      4'h1: out = b;
      4'h2: out = c;
      4'h3: out = d;
      4'h4: out = e;
      4'h5: out = f;
      4'h6: out = g;
      4'h7: out = h;
      4'h8: out = i;
    endcase
  end

endmodule
