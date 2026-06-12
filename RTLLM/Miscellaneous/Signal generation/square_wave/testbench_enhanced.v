`timescale 1ns/1ps

module testbench_enhanced;

    // Signal declarations
    reg clk;
    reg [7:0] freq;
    wire wave_out;
    wire ref_wave_out;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // DUT instantiation
    square_wave uut (
        .clk(clk),
        .freq(freq),
        .wave_out(wave_out)
    );

    // Golden reference instantiation
    golden_square_wave ref_model (
        .clk(clk),
        .freq(freq),
        .wave_out(ref_wave_out)
    );

    // Clock generation: 10ns period
    initial clk = 0;
    always #5 clk = ~clk;

    // Check task
    task check;
        input dut_val;
        input ref_val;
        begin
            check_id = check_id + 1;
            total_checks = total_checks + 1;
            if (dut_val === ref_val) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL: DUT wave_out=%b, REF wave_out=%b at time %0t", check_id, dut_val, ref_val, $time);
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

        // Original TB uses freq=4
        freq = 8'd4;

        // Run for 200 cycles like original, checking every cycle
        for (i = 0; i < 200; i = i + 1) begin
            @(posedge clk); #1;
            check(wave_out, ref_wave_out);
        end

        // =============================================
        // Group B: Boundary/corner cases
        // =============================================
        $display("=== Group B: Boundary/corner cases ===");

        // B1: freq = 1 (fastest toggling - toggle every clock)
        freq = 8'd1;
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge clk); #1;
            check(wave_out, ref_wave_out);
        end

        // B2: freq = 2 (toggle every 2 clocks)
        freq = 8'd2;
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge clk); #1;
            check(wave_out, ref_wave_out);
        end

        // B3: freq = 255 (slowest toggling)
        freq = 8'd255;
        for (i = 0; i < 30; i = i + 1) begin
            @(posedge clk); #1;
            check(wave_out, ref_wave_out);
        end

        // B4: freq = 128 (mid-range)
        freq = 8'd128;
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge clk); #1;
            check(wave_out, ref_wave_out);
        end

        // B5: freq = 3
        freq = 8'd3;
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge clk); #1;
            check(wave_out, ref_wave_out);
        end

        // =============================================
        // Group C: Randomized stress
        // =============================================
        $display("=== Group C: Randomized stress ===");

        // Randomly change freq and run
        for (i = 0; i < 60; i = i + 1) begin
            if (($random(seed) % 8) == 0) begin
                // Change freq to a random non-zero value
                freq = ($random(seed) % 255) + 1;
            end
            @(posedge clk); #1;
            check(wave_out, ref_wave_out);
        end

        // =============================================
        // Group D: Protocol/timing - freq switching
        // =============================================
        $display("=== Group D: Protocol/timing ===");

        // D1: Rapid frequency changes
        freq = 8'd5;
        for (i = 0; i < 10; i = i + 1) begin
            @(posedge clk); #1;
            check(wave_out, ref_wave_out);
        end
        freq = 8'd10;
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge clk); #1;
            check(wave_out, ref_wave_out);
        end
        freq = 8'd3;
        for (i = 0; i < 15; i = i + 1) begin
            @(posedge clk); #1;
            check(wave_out, ref_wave_out);
        end

        // D2: Switch freq every cycle
        for (i = 0; i < 20; i = i + 1) begin
            freq = (i % 5) + 1;
            @(posedge clk); #1;
            check(wave_out, ref_wave_out);
        end

        // D3: Power-of-2 frequencies
        freq = 8'd1;
        for (i = 0; i < 5; i = i + 1) begin
            @(posedge clk); #1;
            check(wave_out, ref_wave_out);
        end
        freq = 8'd2;
        for (i = 0; i < 5; i = i + 1) begin
            @(posedge clk); #1;
            check(wave_out, ref_wave_out);
        end
        freq = 8'd4;
        for (i = 0; i < 5; i = i + 1) begin
            @(posedge clk); #1;
            check(wave_out, ref_wave_out);
        end
        freq = 8'd8;
        for (i = 0; i < 5; i = i + 1) begin
            @(posedge clk); #1;
            check(wave_out, ref_wave_out);
        end
        freq = 8'd16;
        for (i = 0; i < 5; i = i + 1) begin
            @(posedge clk); #1;
            check(wave_out, ref_wave_out);
        end
        freq = 8'd32;
        for (i = 0; i < 5; i = i + 1) begin
            @(posedge clk); #1;
            check(wave_out, ref_wave_out);
        end
        freq = 8'd64;
        for (i = 0; i < 5; i = i + 1) begin
            @(posedge clk); #1;
            check(wave_out, ref_wave_out);
        end
        freq = 8'd128;
        for (i = 0; i < 5; i = i + 1) begin
            @(posedge clk); #1;
            check(wave_out, ref_wave_out);
        end

        // D4: Sustained run with freq=7 to see multiple toggles
        freq = 8'd7;
        for (i = 0; i < 30; i = i + 1) begin
            @(posedge clk); #1;
            check(wave_out, ref_wave_out);
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
module golden_square_wave(
    input clk,
    input [7:0] freq,
    output reg wave_out
);

reg [7:0] count;

initial begin
    wave_out = 0;
    count = 0;
end

always @(posedge clk) begin
    if(count == freq - 1 ) begin
        count <= 0;
        wave_out <=  ~wave_out ;

    end else begin
        count <= count + 1;
    end
end

endmodule
