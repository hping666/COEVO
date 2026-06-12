`timescale 1ns/1ps

module tb_multi_booth_8bit_enhanced;

    // Signal declarations
    reg clk;
    reg reset;
    reg [7:0] a, b;
    wire [15:0] p;
    wire rdy;
    wire [15:0] ref_p;
    wire ref_rdy;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;
    integer timeout_cnt;

    // DUT instantiation
    multi_booth_8bit uut (
        .clk(clk),
        .reset(reset),
        .a(a),
        .b(b),
        .p(p),
        .rdy(rdy)
    );

    // Golden reference instantiation
    golden_multi_booth_8bit ref_model (
        .clk(clk),
        .reset(reset),
        .a(a),
        .b(b),
        .p(ref_p),
        .rdy(ref_rdy)
    );

    // Clock generation: 10ns period
    always #5 clk = ~clk;

    // Check task
    task check_outputs;
        begin
            total_checks = total_checks + 1;
            check_id = check_id + 1;
            if (p !== ref_p || rdy !== ref_rdy) begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL: a=%h b=%h | DUT: p=%h rdy=%b | REF: p=%h rdy=%b",
                         check_id, a, b, p, rdy, ref_p, ref_rdy);
            end else begin
                passed_checks = passed_checks + 1;
            end
        end
    endtask

    // Task to run one multiplication and wait for rdy
    task run_multiply;
        input [7:0] a_val;
        input [7:0] b_val;
        begin
            a = a_val;
            b = b_val;
            // Assert reset for one cycle
            reset = 1;
            @(posedge clk);
            #1;
            reset = 0;
            // Wait for rdy from reference model
            timeout_cnt = 0;
            while (ref_rdy !== 1'b1 && timeout_cnt < 500) begin
                @(posedge clk);
                #1;
                timeout_cnt = timeout_cnt + 1;
            end
            // Check at rdy
            check_outputs;
        end
    endtask

    // Watchdog
    initial begin
        #5000000;
        $display("[FORGE_RESULT] TIMEOUT");
        $finish;
    end

    // Main test
    initial begin
        clk = 1;
        reset = 0;
        a = 0;
        b = 0;

        // =====================================================
        // Group A: Original testbench cases (basic tests)
        // =====================================================
        $display("--- Group A: Original testbench cases ---");

        run_multiply(8'd3, 8'd7);
        run_multiply(8'd5, 8'd10);
        run_multiply(8'd127, 8'd2);
        run_multiply(8'd100, 8'd50);
        run_multiply(8'd15, 8'd15);

        // =====================================================
        // Group B: Boundary/corner cases
        // =====================================================
        $display("--- Group B: Boundary/corner cases ---");

        // Zero cases
        run_multiply(8'h00, 8'h00);
        run_multiply(8'h00, 8'hFF);
        run_multiply(8'hFF, 8'h00);
        run_multiply(8'h00, 8'h7F);
        run_multiply(8'h7F, 8'h00);

        // Max positive (signed: 127)
        run_multiply(8'h7F, 8'h7F);
        run_multiply(8'h7F, 8'h01);
        run_multiply(8'h01, 8'h7F);

        // One values
        run_multiply(8'h01, 8'h01);
        run_multiply(8'h01, 8'hFF);
        run_multiply(8'hFF, 8'h01);

        // All ones (signed: -1)
        run_multiply(8'hFF, 8'hFF);

        // Signed boundary: -128
        run_multiply(8'h80, 8'h01);
        run_multiply(8'h01, 8'h80);
        run_multiply(8'h80, 8'h80);
        run_multiply(8'h80, 8'hFF);
        run_multiply(8'hFF, 8'h80);
        run_multiply(8'h80, 8'h7F);
        run_multiply(8'h7F, 8'h80);

        // Alternating bits
        run_multiply(8'hAA, 8'h55);
        run_multiply(8'h55, 8'hAA);
        run_multiply(8'hAA, 8'hAA);
        run_multiply(8'h55, 8'h55);

        // Power of 2
        run_multiply(8'h02, 8'h02);
        run_multiply(8'h04, 8'h08);
        run_multiply(8'h10, 8'h10);
        run_multiply(8'h40, 8'h02);
        run_multiply(8'h02, 8'h40);

        // Negative values (signed interpretation)
        run_multiply(8'hFE, 8'hFE); // -2 * -2
        run_multiply(8'hFD, 8'hFB); // -3 * -5
        run_multiply(8'hF0, 8'h0F); // -16 * 15
        run_multiply(8'h0F, 8'hF0); // 15 * -16

        // Carry propagation
        run_multiply(8'hFF, 8'h02);
        run_multiply(8'h02, 8'hFF);
        run_multiply(8'hFE, 8'hFF);

        // =====================================================
        // Group C: Randomized stress testing
        // =====================================================
        $display("--- Group C: Randomized stress testing ---");

        for (i = 0; i < 50; i = i + 1) begin
            run_multiply($random(seed), $random(seed));
        end

        // =====================================================
        // Group D: Protocol/timing tests
        // =====================================================
        $display("--- Group D: Protocol/timing tests ---");

        // Back-to-back multiplications
        run_multiply(8'h12, 8'h34);
        run_multiply(8'h56, 8'h78);
        run_multiply(8'h9A, 8'hBC);

        // Reset in the middle of operation
        a = 8'h33;
        b = 8'h44;
        reset = 1;
        @(posedge clk);
        #1;
        reset = 0;
        // Wait a few cycles (not done yet)
        @(posedge clk); #1;
        @(posedge clk); #1;
        @(posedge clk); #1;
        // Now reset and do a proper multiply
        run_multiply(8'h05, 8'h06);

        // Multiple resets
        reset = 1; @(posedge clk); #1;
        reset = 1; @(posedge clk); #1;
        reset = 0;
        timeout_cnt = 0;
        while (ref_rdy !== 1'b1 && timeout_cnt < 500) begin
            @(posedge clk); #1;
            timeout_cnt = timeout_cnt + 1;
        end
        check_outputs;

        // Verify after protocol stress
        run_multiply(8'h0A, 8'h0B);

        // Score reporting
        $display("===================================================");
        $display("[FORGE_RESULT] TOTAL=%0d PASSED=%0d FAILED=%0d", total_checks, passed_checks, failed_checks);
        if (failed_checks == 0)
            $display("[FORGE_RESULT] STATUS=PASS SCORE=%0d/%0d", passed_checks, total_checks);
        else
            $display("[FORGE_RESULT] STATUS=FAIL SCORE=%0d/%0d", passed_checks, total_checks);
        $display("===================================================");
        $finish;
    end

endmodule

// =========================================================
// Golden Reference Model - copy of verified_multi_booth_8bit.v
// =========================================================
module golden_multi_booth_8bit (p, rdy, clk, reset, a, b);
   input clk, reset;
   input [7:0] a, b;
   output [15:0] p;
   output rdy;

   reg [15:0] p;
   reg [15:0] multiplier;
   reg [15:0] multiplicand;
   reg rdy;
   reg [4:0] ctr;

always @(posedge clk) begin
    if (reset)
    begin
    rdy     <= 0;
    p   <= 0;
    ctr     <= 0;
    multiplier <= {{8{a[7]}}, a};
    multiplicand <= {{8{b[7]}}, b};
    end
    else
    begin
      if(ctr < 16)
          begin
          multiplicand <= multiplicand << 1;
            if (multiplier[ctr] == 1)
            begin
                p <= p + multiplicand;
            end
            ctr <= ctr + 1;
          end
       else
           begin
           rdy <= 1;
           end
    end
  end

endmodule
