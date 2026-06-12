`timescale 1ns/1ps
module testbench_enhanced;

    // Signal declarations
    reg clk;
    reg reset;
    wire [7:0] out;
    wire [7:0] ref_out;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // DUT instantiation
    ring_counter uut (
        .clk(clk),
        .reset(reset),
        .out(out)
    );

    // Golden reference instantiation
    golden_ring_counter ref_model (
        .clk(clk),
        .reset(reset),
        .out(ref_out)
    );

    // Clock generation: 10ns period
    always #5 clk = ~clk;

    // Check task
    task check;
        input [7:0] expected;
        input [7:0] actual;
        input [255:0] description;
        begin
            total_checks = total_checks + 1;
            check_id = check_id + 1;
            if (actual === expected) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL | %0s | expected=%b got=%b | time=%0t", check_id, description, expected, actual, $time);
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
        reset = 1;

        // ============================================================
        // Group A: Original testbench cases
        // ============================================================

        // A0: Pre-posedge async reset check
        // Async reset: out = 8'b00000001 immediately. Sync reset: out = x.
        #1;
        check(ref_out, out, "GroupA: async reset imm");

        // A1: Check reset state
        @(posedge clk); #1;
        check(ref_out, out, "GroupA: reset state");

        // A2: Release reset, check initial state
        #9; // complete the cycle
        reset = 0;
        @(posedge clk); #1;
        check(ref_out, out, "GroupA: first cycle after reset");

        // A3: Walk through full ring (8 positions)
        repeat (7) begin
            @(posedge clk); #1;
            check(ref_out, out, "GroupA: ring rotation");
        end

        // A4: Wrap back to start
        @(posedge clk); #1;
        check(ref_out, out, "GroupA: wrap to start");

        // ============================================================
        // Group B: Boundary/corner cases
        // ============================================================

        // B1: Reset during mid-rotation
        repeat (3) begin
            @(posedge clk); #1;
        end
        reset = 1;
        @(posedge clk); #1;
        check(ref_out, out, "GroupB: reset during rotation");
        reset = 0;
        @(posedge clk); #1;
        check(ref_out, out, "GroupB: after mid-rotation reset");

        // B2: Multiple full rotations
        repeat (16) begin
            @(posedge clk); #1;
            check(ref_out, out, "GroupB: multiple rotations");
        end

        // B3: Reset at every position
        repeat (8) begin
            @(posedge clk); #1;
            check(ref_out, out, "GroupB: before position reset");
            reset = 1;
            @(posedge clk); #1;
            check(ref_out, out, "GroupB: reset at position");
            reset = 0;
        end

        // B4: Immediate reset after release
        reset = 1;
        @(posedge clk); #1;
        check(ref_out, out, "GroupB: immediate reset");
        reset = 0;
        @(posedge clk); #1;
        check(ref_out, out, "GroupB: immediate release");
        reset = 1;
        @(posedge clk); #1;
        check(ref_out, out, "GroupB: re-reset");
        reset = 0;

        // B5: Long continuous rotation (3 full cycles)
        repeat (24) begin
            @(posedge clk); #1;
            check(ref_out, out, "GroupB: long rotation");
        end

        // ============================================================
        // Group C: Randomized tests
        // ============================================================

        // Reset to known state
        reset = 1;
        @(posedge clk); #1;
        reset = 0;

        repeat (50) begin
            if (($random(seed) % 8) == 0) begin
                reset = 1;
                @(posedge clk); #1;
                check(ref_out, out, "GroupC: random reset");
                reset = 0;
            end
            @(posedge clk); #1;
            check(ref_out, out, "GroupC: random cycle");
        end

        // ============================================================
        // Group D: Protocol/timing tests
        // ============================================================

        // D1: Reset from different rotational states
        reset = 1; @(posedge clk); #1; reset = 0;
        repeat (2) @(posedge clk);
        #1;
        reset = 1;
        @(posedge clk); #1;
        check(ref_out, out, "GroupD: reset from state 2");
        reset = 0;

        repeat (5) @(posedge clk);
        #1;
        reset = 1;
        @(posedge clk); #1;
        check(ref_out, out, "GroupD: reset from state 5");
        reset = 0;

        // D2: Back-to-back operations
        repeat (5) begin
            @(posedge clk); #1;
            check(ref_out, out, "GroupD: b2b operation");
        end

        // D3: Multiple resets in succession
        repeat (5) begin
            reset = 1;
            @(posedge clk); #1;
            check(ref_out, out, "GroupD: multi reset");
            reset = 0;
            @(posedge clk); #1;
            check(ref_out, out, "GroupD: after multi reset");
        end

        // D4: Reset hold for multiple cycles
        reset = 1;
        repeat (5) begin
            @(posedge clk); #1;
            check(ref_out, out, "GroupD: held reset");
        end
        reset = 0;
        repeat (5) begin
            @(posedge clk); #1;
            check(ref_out, out, "GroupD: after held reset");
        end

        // D5: Alternating reset and run
        repeat (8) begin
            reset = 1;
            @(posedge clk); #1;
            check(ref_out, out, "GroupD: alt reset");
            reset = 0;
            repeat (2) begin
                @(posedge clk); #1;
                check(ref_out, out, "GroupD: alt run");
            end
        end

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
// Golden Reference Model (fixed output port type)
// ============================================================
module golden_ring_counter (
    input wire clk,
    input wire reset,
    output wire [7:0] out
);

    reg [7:0] state;

    always @ (posedge clk or posedge reset)
    begin
        if (reset)
            state <= 8'b0000_0001;
        else
            state <= {state[6:0], state[7]};
    end

    assign out = state;

endmodule

