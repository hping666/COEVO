`timescale 1ns/1ps
module testbench_enhanced;

    // Signal declarations
    reg clk;
    reg rst_n;
    reg valid_count;
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
    counter_12 uut (
        .rst_n(rst_n),
        .clk(clk),
        .valid_count(valid_count),
        .out(out)
    );

    // Golden reference instantiation
    golden_counter_12 ref_model (
        .rst_n(rst_n),
        .clk(clk),
        .valid_count(valid_count),
        .out(ref_out)
    );

    // Clock generation: 10ns period
    always #5 clk = ~clk;

    // Check task
    task check;
        input [3:0] expected;
        input [3:0] actual;
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
        rst_n = 0;
        valid_count = 0;

        // ============================================================
        // Group A: Original testbench cases
        // ============================================================

        // Reset
        #20;
        rst_n = 1;

        // A1: valid_count=0, counter should stay at 0
        repeat (15) begin
            @(posedge clk); #1;
            check(ref_out, out, "GroupA: count stays 0 when valid_count=0");
        end

        // A2: Enable counting for 11 cycles (0 to 10)
        @(posedge clk); #1;
        valid_count = 1;
        repeat (11) begin
            @(posedge clk); #1;
            check(ref_out, out, "GroupA: counting up");
        end

        // A3: Disable counting, counter should hold
        valid_count = 0;
        repeat (5) begin
            @(posedge clk); #1;
            check(ref_out, out, "GroupA: count paused");
        end

        // ============================================================
        // Group B: Boundary/corner cases
        // ============================================================

        // B1: Reset during active counting
        valid_count = 1;
        repeat (5) begin
            @(posedge clk); #1;
        end
        rst_n = 0;
        #10;
        @(posedge clk); #1;
        check(ref_out, out, "GroupB: reset during counting");
        rst_n = 1;
        @(posedge clk); #1;
        check(ref_out, out, "GroupB: after reset release");

        // B2: Count all the way to wrap (0->11->0)
        valid_count = 1;
        repeat (13) begin
            @(posedge clk); #1;
            check(ref_out, out, "GroupB: full wrap around");
        end

        // B3: Multiple wraps
        repeat (24) begin
            @(posedge clk); #1;
            check(ref_out, out, "GroupB: multiple wraps");
        end

        // B4: Toggle enable on/off rapidly
        repeat (10) begin
            valid_count = 1;
            @(posedge clk); #1;
            check(ref_out, out, "GroupB: toggle enable on");
            valid_count = 0;
            @(posedge clk); #1;
            check(ref_out, out, "GroupB: toggle enable off");
        end

        // B5: Reset at exact wrap point - count to 11 then reset
        valid_count = 1;
        // First reset to known state
        rst_n = 0; #10; rst_n = 1;
        @(posedge clk); #1;
        // Count to 11
        repeat (11) begin
            @(posedge clk); #1;
        end
        check(ref_out, out, "GroupB: at wrap value 11");
        rst_n = 0; #10;
        @(posedge clk); #1;
        check(ref_out, out, "GroupB: reset at wrap");
        rst_n = 1;
        @(posedge clk); #1;
        check(ref_out, out, "GroupB: after reset at wrap");

        // B6: Enable immediately after reset
        rst_n = 0; #10; rst_n = 1;
        valid_count = 1;
        @(posedge clk); #1;
        check(ref_out, out, "GroupB: enable right after reset");
        @(posedge clk); #1;
        check(ref_out, out, "GroupB: enable right after reset+1");

        // B7: Disable at wrap point
        rst_n = 0; #10; rst_n = 1;
        valid_count = 1;
        repeat (12) begin
            @(posedge clk); #1;
        end
        // Should be at 0 after wrap
        valid_count = 0;
        repeat (3) begin
            @(posedge clk); #1;
            check(ref_out, out, "GroupB: disable at wrap");
        end

        // ============================================================
        // Group C: Randomized tests
        // ============================================================

        // Reset to known state
        rst_n = 0; #10; rst_n = 1;
        valid_count = 0;
        @(posedge clk); #1;

        repeat (50) begin
            valid_count = $random(seed) % 2;
            if (($random(seed) % 10) == 0) begin
                rst_n = 0;
                @(posedge clk); #1;
                check(ref_out, out, "GroupC: random reset");
                rst_n = 1;
            end
            @(posedge clk); #1;
            check(ref_out, out, "GroupC: random stimulus");
        end

        // ============================================================
        // Group D: Protocol/timing tests
        // ============================================================

        // D1: Reset from different states
        rst_n = 0; #10; rst_n = 1;
        valid_count = 1;
        // Count to 3
        repeat (3) @(posedge clk);
        #1;
        rst_n = 0; #10; rst_n = 1;
        @(posedge clk); #1;
        check(ref_out, out, "GroupD: reset from state 3");

        // Count to 7
        valid_count = 1;
        repeat (7) @(posedge clk);
        #1;
        rst_n = 0; #10; rst_n = 1;
        @(posedge clk); #1;
        check(ref_out, out, "GroupD: reset from state 7");

        // D2: Back-to-back enable/disable
        valid_count = 1;
        @(posedge clk); #1;
        check(ref_out, out, "GroupD: b2b enable");
        valid_count = 0;
        @(posedge clk); #1;
        check(ref_out, out, "GroupD: b2b disable");
        valid_count = 1;
        @(posedge clk); #1;
        check(ref_out, out, "GroupD: b2b re-enable");

        // D3: Multiple resets in succession
        repeat (5) begin
            rst_n = 0; #10;
            @(posedge clk); #1;
            check(ref_out, out, "GroupD: multiple resets");
            rst_n = 1;
            @(posedge clk); #1;
            check(ref_out, out, "GroupD: after multi reset");
        end

        // D4: Long continuous counting
        valid_count = 1;
        repeat (36) begin
            @(posedge clk); #1;
            check(ref_out, out, "GroupD: long continuous count");
        end

        // D5: Reset pulse width test
        rst_n = 0; #3;
        rst_n = 1;
        @(posedge clk); #1;
        check(ref_out, out, "GroupD: short reset pulse");

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
module golden_counter_12
(
  input rst_n,
  input clk,
  input valid_count,

  output reg [3:0] out
);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
	begin
      out <= 4'b0000;
    end

	else if (valid_count)
	begin
      if (out == 4'd11)
	  begin
        out <= 4'b0000;
      end
	  else begin
        out <= out + 1;
      end
    end

	else begin
      out <= out; // Pause the count when valid_count is invalid
    end
  end

endmodule
