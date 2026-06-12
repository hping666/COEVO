`timescale 1ns/1ps
module testbench_enhanced;

    // Signal declarations
    reg clk;
    reg rst_n;
    wire [63:0] Q;
    wire [63:0] ref_Q;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // DUT instantiation
    JC_counter uut (
        .clk(clk),
        .rst_n(rst_n),
        .Q(Q)
    );

    // Golden reference instantiation
    golden_JC_counter ref_model (
        .clk(clk),
        .rst_n(rst_n),
        .Q(ref_Q)
    );

    // Clock generation: 10ns period
    always #5 clk = ~clk;

    // Check task
    task check;
        input [63:0] expected;
        input [63:0] actual;
        input [255:0] description;
        begin
            total_checks = total_checks + 1;
            check_id = check_id + 1;
            if (actual === expected) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL | %0s | expected=%h got=%h | time=%0t", check_id, description, expected, actual, $time);
            end
        end
    endtask

    // Watchdog
    initial begin
        #5000000;
        $display("[FORGE_RESULT] TIMEOUT");
        $finish;
    end

    // Main test sequence
    initial begin
        clk = 0;
        rst_n = 1;

        // ============================================================
        // Group A: Original testbench cases
        // ============================================================

        // Reset sequence from original TB
        #20; // 2 clock periods
        rst_n = 0;
        #20; // 2 clock periods in reset
        @(posedge clk); #1;
        check(ref_Q, Q, "GroupA: after reset");
        rst_n = 1;

        // Count for 20 cycles and check (original testcase)
        repeat (20) begin
            @(posedge clk); #1;
        end
        check(ref_Q, Q, "GroupA: after 20 cycles");

        // Count for 44 more cycles
        repeat (44) begin
            @(posedge clk); #1;
        end
        check(ref_Q, Q, "GroupA: after 64 cycles total");

        // 1 more cycle
        @(posedge clk); #1;
        check(ref_Q, Q, "GroupA: after 65 cycles");

        // 62 more cycles
        repeat (62) begin
            @(posedge clk); #1;
        end
        check(ref_Q, Q, "GroupA: after 127 cycles");

        // ============================================================
        // Group B: Boundary/corner cases
        // ============================================================

        // B1: Reset and watch full Johnson sequence filling up
        rst_n = 0; #10;
        @(posedge clk); #1;
        check(ref_Q, Q, "GroupB: reset state");
        rst_n = 1;

        // B2: Watch first 10 cycles - ones filling from MSB
        repeat (10) begin
            @(posedge clk); #1;
            check(ref_Q, Q, "GroupB: filling ones");
        end

        // B3: Count to all-ones state (64 cycles from reset)
        repeat (54) begin
            @(posedge clk); #1;
        end
        check(ref_Q, Q, "GroupB: near all-ones");

        // B4: Cross from all-ones to draining zeros
        repeat (5) begin
            @(posedge clk); #1;
            check(ref_Q, Q, "GroupB: crossing all-ones");
        end

        // B5: Reset during draining phase
        rst_n = 0; #10;
        @(posedge clk); #1;
        check(ref_Q, Q, "GroupB: reset during drain");
        rst_n = 1;

        // B6: Count through half-cycle
        repeat (32) begin
            @(posedge clk); #1;
            check(ref_Q, Q, "GroupB: half cycle count");
        end

        // B7: Reset at midpoint
        rst_n = 0; #10;
        @(posedge clk); #1;
        check(ref_Q, Q, "GroupB: reset at midpoint");
        rst_n = 1;

        // B8: Very short run then reset
        @(posedge clk); #1;
        check(ref_Q, Q, "GroupB: one cycle");
        rst_n = 0; #10;
        @(posedge clk); #1;
        check(ref_Q, Q, "GroupB: quick reset");
        rst_n = 1;

        // ============================================================
        // Group C: Randomized tests - random reset assertions
        // ============================================================

        repeat (50) begin
            if (($random(seed) % 8) == 0) begin
                rst_n = 0;
                @(posedge clk); #1;
                check(ref_Q, Q, "GroupC: random reset");
                rst_n = 1;
            end
            @(posedge clk); #1;
            check(ref_Q, Q, "GroupC: random counting");
        end

        // ============================================================
        // Group D: Protocol/timing tests
        // ============================================================

        // D1: Reset from various states
        rst_n = 0; #10; rst_n = 1;
        repeat (5) @(posedge clk);
        #1;
        rst_n = 0; #10;
        @(posedge clk); #1;
        check(ref_Q, Q, "GroupD: reset from state 5");
        rst_n = 1;

        repeat (30) @(posedge clk);
        #1;
        rst_n = 0; #10;
        @(posedge clk); #1;
        check(ref_Q, Q, "GroupD: reset from state 30");
        rst_n = 1;

        // D2: Back-to-back counting
        repeat (10) begin
            @(posedge clk); #1;
            check(ref_Q, Q, "GroupD: b2b counting");
        end

        // D3: Multiple resets in quick succession
        repeat (5) begin
            rst_n = 0; #10;
            @(posedge clk); #1;
            check(ref_Q, Q, "GroupD: multi reset");
            rst_n = 1;
            @(posedge clk); #1;
            check(ref_Q, Q, "GroupD: after multi reset");
        end

        // D4: Full cycle test (128 clocks = complete Johnson cycle)
        rst_n = 0; #10; rst_n = 1;
        repeat (128) begin
            @(posedge clk); #1;
            check(ref_Q, Q, "GroupD: full cycle");
        end

        // D5: Short reset pulse
        rst_n = 0; #3;
        rst_n = 1;
        @(posedge clk); #1;
        check(ref_Q, Q, "GroupD: short reset pulse");

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

// ============================================================
// Golden Reference Model
// ============================================================
module golden_JC_counter(
   input                clk ,
   input                rst_n,

   output reg [63:0]     Q
);
    always@(posedge clk or negedge rst_n)begin
        if(!rst_n) Q <= 'd0;
        else if(!Q[0]) Q <= {1'b1, Q[63 : 1]};
        else Q <= {1'b0, Q[63 : 1]};
    end
endmodule
