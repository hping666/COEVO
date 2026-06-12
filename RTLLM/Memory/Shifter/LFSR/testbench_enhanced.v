`timescale 1ns/1ps

module testbench_enhanced;

    // Signal declarations
    reg clk;
    reg rst;
    wire [3:0] out;
    wire [3:0] ref_out;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // DUT instantiation
    LFSR uut (
        .out(out),
        .clk(clk),
        .rst(rst)
    );

    // Golden reference instantiation
    golden_LFSR ref_model (
        .out(ref_out),
        .clk(clk),
        .rst(rst)
    );

    // Clock generation: 10ns period
    initial clk = 0;
    always #5 clk = ~clk;

    // Check task
    task check;
        input [255:0] description;
        begin
            total_checks = total_checks + 1;
            check_id = check_id + 1;
            if (out === ref_out) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL | %0s | expected=%b got=%b | time=%0t", check_id, description, ref_out, out, $time);
            end
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
        // =============================================
        // Group A: Original testbench cases
        // =============================================
        rst = 1;
        @(posedge clk); #1;
        check("GroupA: Reset state");

        @(posedge clk); #1;
        check("GroupA: Still in reset");

        rst = 0;
        // Run for 20 clock cycles (matching original ~200ns with 10ns clock)
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge clk); #1;
            check("GroupA: LFSR sequence step");
        end

        // =============================================
        // Group B: Boundary/corner cases
        // =============================================

        // B1: Reset initializes to 0
        rst = 1;
        @(posedge clk); #1;
        check("GroupB: Reset to zero");

        @(posedge clk); #1;
        check("GroupB: Held in reset");

        @(posedge clk); #1;
        check("GroupB: Still held in reset");

        // B2: Release reset and run full LFSR cycle
        // A 4-bit LFSR with this feedback should cycle through states
        // Run for at least 16 cycles to see full cycle length
        rst = 0;
        for (i = 0; i < 16; i = i + 1) begin
            @(posedge clk); #1;
            check("GroupB: Full cycle step");
        end

        // B3: Continue beyond full cycle to verify repetition
        for (i = 0; i < 16; i = i + 1) begin
            @(posedge clk); #1;
            check("GroupB: Second cycle step");
        end

        // B4: Reset in middle of sequence
        rst = 1;
        @(posedge clk); #1;
        check("GroupB: Mid-sequence reset");

        rst = 0;
        @(posedge clk); #1;
        check("GroupB: After mid-sequence reset release");

        // =============================================
        // Group C: Randomized stress tests
        // =============================================

        // First ensure both are in known state
        rst = 1;
        @(posedge clk); #1;
        check("GroupC: Initial reset for random test");
        rst = 0;

        for (i = 0; i < 30; i = i + 1) begin
            // Randomly apply reset
            if (($random(seed) % 8) == 0) begin
                rst = 1;
                @(posedge clk); #1;
                check("GroupC: Random reset applied");
                rst = 0;
            end
            @(posedge clk); #1;
            check("GroupC: Random clock cycle");
        end

        // =============================================
        // Group D: Protocol/timing tests
        // =============================================

        // D1: Reset during operation
        rst = 1;
        @(posedge clk); #1;
        check("GroupD: Reset for protocol test");
        rst = 0;

        // Run a few cycles
        for (i = 0; i < 5; i = i + 1) begin
            @(posedge clk); #1;
            check("GroupD: Pre-reset run");
        end

        // Apply reset mid-operation
        rst = 1;
        @(posedge clk); #1;
        check("GroupD: Reset during operation");

        // Release and continue
        rst = 0;
        for (i = 0; i < 5; i = i + 1) begin
            @(posedge clk); #1;
            check("GroupD: After reset release");
        end

        // D2: Multiple rapid resets
        for (i = 0; i < 5; i = i + 1) begin
            rst = 1;
            @(posedge clk); #1;
            check("GroupD: Rapid reset assert");
            rst = 0;
            @(posedge clk); #1;
            check("GroupD: Rapid reset release");
        end

        // D3: Long run after multiple resets
        rst = 1;
        @(posedge clk); #1;
        rst = 0;
        for (i = 0; i < 10; i = i + 1) begin
            @(posedge clk); #1;
            check("GroupD: Long run after resets");
        end

        // =============================================
        // Score reporting
        // =============================================
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

// =============================================
// Golden reference model
// =============================================
module golden_LFSR (out, clk, rst);
  input clk, rst;
  output reg [3:0] out;
  wire feedback;

  assign feedback = ~(out[3] ^ out[2]);

always @(posedge clk, posedge rst)
  begin
    if (rst)
      out = 4'b0;
    else
      out = {out[2:0],feedback};
  end
endmodule
