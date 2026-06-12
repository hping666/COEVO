`timescale 1ns/1ps
module testbench_enhanced;

    // Signal declarations
    reg clk;
    reg reset;
    reg up_down;
    wire [15:0] count;
    wire [15:0] ref_count;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // DUT instantiation
    up_down_counter uut (
        .clk(clk),
        .reset(reset),
        .up_down(up_down),
        .count(count)
    );

    // Golden reference instantiation
    golden_up_down_counter ref_model (
        .clk(clk),
        .reset(reset),
        .up_down(up_down),
        .count(ref_count)
    );

    // Clock generation: 10ns period
    always #5 clk = ~clk;

    // Check task
    task check;
        input [15:0] expected;
        input [15:0] actual;
        input [255:0] description;
        begin
            total_checks = total_checks + 1;
            check_id = check_id + 1;
            if (actual === expected) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL | %0s | expected=%0d got=%0d | time=%0t", check_id, description, expected, actual, $time);
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
        up_down = 1;

        // ============================================================
        // Group A: Original testbench cases
        // ============================================================

        // Reset
        #10;
        reset = 0;
        @(posedge clk); #1;
        check(ref_count, count, "GroupA: after reset");

        // A1: Count up for 10 cycles
        up_down = 1;
        repeat (10) begin
            @(posedge clk); #1;
            check(ref_count, count, "GroupA: counting up");
        end

        // A2: Switch to count down
        up_down = 0;
        repeat (20) begin
            @(posedge clk); #1;
            check(ref_count, count, "GroupA: counting down");
        end

        // A3: Switch back to count up
        up_down = 1;
        repeat (30) begin
            @(posedge clk); #1;
            check(ref_count, count, "GroupA: counting up again");
        end

        // ============================================================
        // Group B: Boundary/corner cases
        // ============================================================

        // B1: Reset during counting
        up_down = 1;
        repeat (5) @(posedge clk);
        #1;
        reset = 1;
        @(posedge clk); #1;
        check(ref_count, count, "GroupB: reset during up count");
        reset = 0;
        @(posedge clk); #1;
        check(ref_count, count, "GroupB: after reset release");

        // B2: Count down from 0 (underflow/wrap)
        reset = 1; @(posedge clk); #1;
        reset = 0;
        up_down = 0;
        @(posedge clk); #1;
        check(ref_count, count, "GroupB: underflow wrap from 0");
        @(posedge clk); #1;
        check(ref_count, count, "GroupB: after underflow");

        // B3: Count up to max and wrap
        reset = 1; @(posedge clk); #1;
        reset = 0;
        up_down = 0; // Count down from 0 to get to 65535
        @(posedge clk); #1;
        check(ref_count, count, "GroupB: at 65535");
        up_down = 1;
        @(posedge clk); #1;
        check(ref_count, count, "GroupB: overflow wrap from 65535");
        @(posedge clk); #1;
        check(ref_count, count, "GroupB: after overflow");

        // B4: Toggle direction rapidly
        reset = 1; @(posedge clk); #1;
        reset = 0;
        repeat (10) begin
            up_down = 1;
            @(posedge clk); #1;
            check(ref_count, count, "GroupB: toggle up");
            up_down = 0;
            @(posedge clk); #1;
            check(ref_count, count, "GroupB: toggle down");
        end

        // B5: Hold reset for multiple cycles
        reset = 1;
        repeat (5) begin
            @(posedge clk); #1;
            check(ref_count, count, "GroupB: held in reset");
        end
        reset = 0;

        // B6: Count down multiple cycles near zero
        reset = 1; @(posedge clk); #1;
        reset = 0;
        up_down = 1;
        repeat (3) @(posedge clk);
        #1;
        up_down = 0;
        repeat (5) begin
            @(posedge clk); #1;
            check(ref_count, count, "GroupB: count down near zero");
        end

        // B7: Reset at exact boundary value
        reset = 1; @(posedge clk); #1;
        reset = 0;
        up_down = 0;
        @(posedge clk); #1; // now at 65535
        reset = 1;
        @(posedge clk); #1;
        check(ref_count, count, "GroupB: reset at max value");
        reset = 0;

        // ============================================================
        // Group C: Randomized tests
        // ============================================================

        reset = 1; @(posedge clk); #1;
        reset = 0;

        repeat (50) begin
            up_down = $random(seed) % 2;
            if (($random(seed) % 10) == 0) begin
                reset = 1;
                @(posedge clk); #1;
                check(ref_count, count, "GroupC: random reset");
                reset = 0;
            end
            @(posedge clk); #1;
            check(ref_count, count, "GroupC: random stimulus");
        end

        // ============================================================
        // Group D: Protocol/timing tests
        // ============================================================

        // D1: Reset from different count values
        reset = 1; @(posedge clk); #1; reset = 0;
        up_down = 1;
        repeat (100) @(posedge clk);
        #1;
        reset = 1;
        @(posedge clk); #1;
        check(ref_count, count, "GroupD: reset from count 100");
        reset = 0;

        up_down = 0;
        repeat (50) @(posedge clk);
        #1;
        reset = 1;
        @(posedge clk); #1;
        check(ref_count, count, "GroupD: reset during down count");
        reset = 0;

        // D2: Back-to-back direction changes
        up_down = 1;
        repeat (3) begin
            @(posedge clk); #1;
            check(ref_count, count, "GroupD: b2b up");
        end
        up_down = 0;
        repeat (3) begin
            @(posedge clk); #1;
            check(ref_count, count, "GroupD: b2b down");
        end
        up_down = 1;
        repeat (3) begin
            @(posedge clk); #1;
            check(ref_count, count, "GroupD: b2b up again");
        end

        // D3: Multiple resets in succession
        repeat (5) begin
            reset = 1;
            @(posedge clk); #1;
            check(ref_count, count, "GroupD: multi reset");
            reset = 0;
            @(posedge clk); #1;
            check(ref_count, count, "GroupD: after multi reset");
        end

        // D4: Long continuous counting up
        up_down = 1;
        repeat (20) begin
            @(posedge clk); #1;
            check(ref_count, count, "GroupD: long up count");
        end

        // D5: Long continuous counting down
        up_down = 0;
        repeat (20) begin
            @(posedge clk); #1;
            check(ref_count, count, "GroupD: long down count");
        end

        // D6: Direction change exactly at reset release
        reset = 1;
        up_down = 0;
        @(posedge clk); #1;
        reset = 0;
        up_down = 1;
        @(posedge clk); #1;
        check(ref_count, count, "GroupD: dir change at reset release");

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
module golden_up_down_counter (
    input wire clk,
    input wire reset,
    input wire up_down,
    output reg [15:0] count
);

always @(posedge clk or posedge reset)
begin
    if (reset) begin
        count <= 16'b0;
    end else begin
        if (up_down) begin
            if (count == 16'b1111_1111_1111_1111) begin
                count <= 16'b0;
            end else begin
                count <= count + 1;
            end
        end else begin
            if (count == 16'b0) begin
                count <= 16'b1111_1111_1111_1111;
            end else begin
                count <= count - 1;
            end
        end
    end
end

endmodule
