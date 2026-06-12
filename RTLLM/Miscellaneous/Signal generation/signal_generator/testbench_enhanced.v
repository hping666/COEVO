`timescale 1ns/1ps

module testbench_enhanced;

    // Signal declarations
    reg clk;
    reg rst_n;
    wire [4:0] wave;
    wire [4:0] ref_wave;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // DUT instantiation
    signal_generator uut (
        .clk(clk),
        .rst_n(rst_n),
        .wave(wave)
    );

    // Golden reference instantiation
    golden_signal_generator ref_model (
        .clk(clk),
        .rst_n(rst_n),
        .wave(ref_wave)
    );

    // Clock generation: 10ns period
    initial clk = 0;
    always #5 clk = ~clk;

    // Check task
    task check;
        input [4:0] dut_val;
        input [4:0] ref_val;
        begin
            check_id = check_id + 1;
            total_checks = total_checks + 1;
            if (dut_val === ref_val) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL: DUT wave=%0d, REF wave=%0d at time %0t", check_id, dut_val, ref_val, $time);
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
        // =============================================
        // Group A: Original testbench cases
        // =============================================
        $display("=== Group A: Original testbench cases ===");

        // Reset
        rst_n = 0;
        @(posedge clk); #1;
        check(wave, ref_wave);

        // Release reset
        rst_n = 1;

        // Run for 100 clock cycles (like original TB)
        for (i = 0; i < 100; i = i + 1) begin
            @(posedge clk); #1;
            check(wave, ref_wave);
        end

        // =============================================
        // Group B: Boundary/corner cases
        // =============================================
        $display("=== Group B: Boundary/corner cases ===");

        // B1: Reset behavior - apply reset and verify outputs go to 0
        rst_n = 0;
        @(posedge clk); #1;
        check(wave, ref_wave);
        @(posedge clk); #1;
        check(wave, ref_wave);

        // B2: Release reset and run through a complete up cycle (0 to 31)
        rst_n = 1;
        // It takes 31 clocks to go from 0 to 31, then 1 clock for state change
        for (i = 0; i < 33; i = i + 1) begin
            @(posedge clk); #1;
            check(wave, ref_wave);
        end

        // B3: Continue through full down cycle (31 to 0)
        for (i = 0; i < 33; i = i + 1) begin
            @(posedge clk); #1;
            check(wave, ref_wave);
        end

        // B4: Reset at mid-count
        // Run a few more cycles first
        for (i = 0; i < 10; i = i + 1) begin
            @(posedge clk); #1;
        end
        rst_n = 0;
        @(posedge clk); #1;
        check(wave, ref_wave);
        rst_n = 1;
        @(posedge clk); #1;
        check(wave, ref_wave);

        // B5: Multiple rapid resets
        for (i = 0; i < 5; i = i + 1) begin
            rst_n = 0;
            @(posedge clk); #1;
            check(wave, ref_wave);
            rst_n = 1;
            @(posedge clk); #1;
            check(wave, ref_wave);
        end

        // =============================================
        // Group C: Randomized stress
        // =============================================
        $display("=== Group C: Randomized stress ===");

        // Make sure we're out of reset
        rst_n = 1;
        for (i = 0; i < 50; i = i + 1) begin
            // Randomly apply reset
            if (($random(seed) % 10) == 0) begin
                rst_n = 0;
                @(posedge clk); #1;
                check(wave, ref_wave);
                rst_n = 1;
            end
            @(posedge clk); #1;
            check(wave, ref_wave);
        end

        // =============================================
        // Group D: Protocol/timing
        // =============================================
        $display("=== Group D: Protocol/timing ===");

        // D1: Reset during counting up phase
        rst_n = 1;
        for (i = 0; i < 15; i = i + 1) begin
            @(posedge clk); #1;
        end
        rst_n = 0;
        @(posedge clk); #1;
        check(wave, ref_wave);
        rst_n = 1;

        // D2: Run through multiple full triangle cycles
        for (i = 0; i < 130; i = i + 1) begin
            @(posedge clk); #1;
            check(wave, ref_wave);
        end

        // D3: Quick toggle reset in various phases
        rst_n = 0;
        @(posedge clk); #1;
        check(wave, ref_wave);
        rst_n = 1;
        // Run 20 cycles
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge clk); #1;
            check(wave, ref_wave);
        end
        // Reset again
        rst_n = 0;
        @(posedge clk); #1;
        check(wave, ref_wave);
        rst_n = 1;
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge clk); #1;
            check(wave, ref_wave);
        end

        // =============================================
        // Score Reporting
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
// Golden Reference Model
// =============================================
module golden_signal_generator(
  input clk,
  input rst_n,
  output reg [4:0] wave
);

  reg [1:0] state;

  always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      state <= 2'b0;
      wave <= 5'b0;
    end
    else begin
      case (state)
        2'b00:
          begin
            if (wave == 5'b11111)
              state <= 2'b01;
            else
              wave <= wave + 1;
          end

        2'b01:
          begin
            if (wave == 5'b00000)
              state <= 2'b00;
            else
              wave <= wave - 1;
          end
      endcase
    end
  end

endmodule
