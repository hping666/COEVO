`timescale 1ns/1ps

module testbench_enhanced;

    // Signal declarations
    reg clk;
    reg rst_n;
    reg pass_request;
    wire [7:0] clock_out;
    wire red, yellow, green;

    // Golden reference outputs
    wire [7:0] ref_clock_out;
    wire ref_red, ref_yellow, ref_green;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // Clock generation: 10ns period
    initial clk = 0;
    always #5 clk = ~clk;

    // DUT instantiation
    traffic_light uut (
        .rst_n(rst_n),
        .clk(clk),
        .pass_request(pass_request),
        .clock(clock_out),
        .red(red),
        .yellow(yellow),
        .green(green)
    );

    // Golden reference instantiation
    golden_traffic_light ref_model (
        .rst_n(rst_n),
        .clk(clk),
        .pass_request(pass_request),
        .clock(ref_clock_out),
        .red(ref_red),
        .yellow(ref_yellow),
        .green(ref_green)
    );

    // Check task
    task check_outputs;
    begin
        check_id = check_id + 1;
        total_checks = total_checks + 1;
        if (red !== ref_red || yellow !== ref_yellow || green !== ref_green || clock_out !== ref_clock_out) begin
            $display("[FORGE_CHECK %0d] FAIL: DUT r=%b y=%b g=%b clk=%0d, GOLD r=%b y=%b g=%b clk=%0d at time %0t",
                     check_id, red, yellow, green, clock_out,
                     ref_red, ref_yellow, ref_green, ref_clock_out, $time);
            failed_checks = failed_checks + 1;
        end else begin
            passed_checks = passed_checks + 1;
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
        // Initialize
        rst_n = 1;
        pass_request = 0;

        // =============================================
        // Group A: Original testbench cases
        // =============================================

        // Perform reset
        rst_n = 0;
        #10;
        rst_n = 1;

        // Wait 3 cycles + check (should be in red state)
        #30;
        @(posedge clk); #1;
        check_outputs; // A1: red phase

        // Wait more, should transition to green
        #100;
        @(posedge clk); #1;
        check_outputs; // A2: green phase

        // Wait through green phase
        #600;
        @(posedge clk); #1;
        check_outputs; // A3: yellow phase

        // Wait a bit
        #150;
        @(posedge clk); #1;
        check_outputs; // A4

        // Test pass_request
        #30;
        @(posedge clk); #1;
        check_outputs; // A5

        pass_request = 1;
        #10;
        @(posedge clk); #1;
        check_outputs; // A6: pass_request active
        pass_request = 0;

        // =============================================
        // Group B: Boundary/corner cases
        // =============================================

        // B1: Full reset from each state
        // Reset
        rst_n = 0;
        @(posedge clk); #1;
        check_outputs; // B1a: reset check
        @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;
        check_outputs; // B1b: after reset release

        // B2: Run through complete cycle: idle -> red -> green -> yellow -> red
        // Wait for full red phase (10 cycles from reset cnt=10, decrements)
        repeat(12) begin
            @(posedge clk); #1;
            check_outputs;
        end

        // B3: Check green phase start
        @(posedge clk); #1;
        check_outputs;

        // B4: Run through some green cycles
        repeat(10) @(posedge clk);
        #1;
        check_outputs;

        // B5: pass_request during green with cnt > 10
        pass_request = 1;
        @(posedge clk); #1;
        check_outputs;
        pass_request = 0;
        @(posedge clk); #1;
        check_outputs;

        // B6: Continue through rest of green after pass_request
        repeat(12) @(posedge clk);
        #1;
        check_outputs;

        // B7: Run to yellow phase
        repeat(50) @(posedge clk);
        #1;
        check_outputs;

        // B8: Run through yellow to red transition
        repeat(10) @(posedge clk);
        #1;
        check_outputs;

        // B9: Reset from green state
        // First get to green
        rst_n = 0;
        @(posedge clk); #1;
        rst_n = 1;
        // idle -> red
        repeat(13) @(posedge clk);
        #1;
        check_outputs; // should be in green now
        // Reset from green
        rst_n = 0;
        @(posedge clk); #1;
        check_outputs;
        rst_n = 1;
        @(posedge clk); #1;
        check_outputs;

        // B10: Reset from yellow state
        // Get to green first
        repeat(13) @(posedge clk);
        #1;
        // Run through green to yellow
        repeat(60) @(posedge clk);
        #1;
        check_outputs; // should be in yellow
        rst_n = 0;
        @(posedge clk); #1;
        check_outputs;
        rst_n = 1;

        // =============================================
        // Group C: Randomized stress
        // =============================================

        // Reset
        rst_n = 0;
        @(posedge clk); #1;
        rst_n = 1;

        // Random pass_request toggling during normal operation
        for (i = 0; i < 15; i = i + 1) begin
            repeat(($random(seed) % 8) + 1) @(posedge clk);
            pass_request = $random(seed) & 1;
            #1;
            check_outputs;
        end
        pass_request = 0;

        // Continue running and checking periodically
        for (i = 0; i < 10; i = i + 1) begin
            repeat(5) @(posedge clk);
            #1;
            check_outputs;
        end

        // =============================================
        // Group D: Protocol/timing tests
        // =============================================

        // D1: Fresh start, verify exact state sequence
        rst_n = 0;
        @(posedge clk); #1;
        check_outputs; // reset state
        rst_n = 1;

        // D2: Verify idle to red transition (1 cycle for idle)
        @(posedge clk); #1;
        check_outputs; // idle->red transition

        @(posedge clk); #1;
        check_outputs; // in red

        // D3: pass_request during red (should have no special effect)
        pass_request = 1;
        @(posedge clk); #1;
        check_outputs;
        pass_request = 0;
        @(posedge clk); #1;
        check_outputs;

        // D4: pass_request during yellow (should have no special effect)
        // Run to yellow
        repeat(70) @(posedge clk);
        #1;
        check_outputs;
        pass_request = 1;
        @(posedge clk); #1;
        check_outputs;
        pass_request = 0;

        // D5: pass_request when green cnt <= 10 (should not shorten)
        rst_n = 0;
        @(posedge clk); #1;
        rst_n = 1;
        // Run to green: idle(1) + red(10) = 11 cycles
        repeat(13) @(posedge clk);
        #1;
        check_outputs;
        // Now in green with cnt=60, wait until cnt is around 8
        repeat(53) @(posedge clk);
        #1;
        check_outputs; // cnt should be low
        pass_request = 1;
        @(posedge clk); #1;
        check_outputs; // cnt <= 10, should NOT change
        pass_request = 0;

        // D6: Run to completion of yellow -> red cycle
        repeat(15) @(posedge clk);
        #1;
        check_outputs;

        // D7: Multiple consecutive pass_requests
        rst_n = 0;
        @(posedge clk); #1;
        rst_n = 1;
        repeat(13) @(posedge clk);
        #1;
        // In green, cnt should be high
        pass_request = 1;
        @(posedge clk); #1;
        check_outputs;
        @(posedge clk); #1;
        check_outputs;
        @(posedge clk); #1;
        check_outputs;
        pass_request = 0;
        @(posedge clk); #1;
        check_outputs;

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
// Golden Reference Model
// =============================================
module golden_traffic_light
    (
        input rst_n,
        input clk,
        input pass_request,
        output wire [7:0] clock,
        output reg red,
        output reg yellow,
        output reg green
    );

    parameter idle = 2'd0,
              s1_red = 2'd1,
              s2_yellow = 2'd2,
              s3_green = 2'd3;
    reg [7:0] cnt;
    reg [1:0] state;
    reg p_red, p_yellow, p_green;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= idle;
            p_red <= 1'b0;
            p_green <= 1'b0;
            p_yellow <= 1'b0;
        end
        else case (state)
            idle: begin
                p_red <= 1'b0;
                p_green <= 1'b0;
                p_yellow <= 1'b0;
                state <= s1_red;
            end
            s1_red: begin
                p_red <= 1'b1;
                p_green <= 1'b0;
                p_yellow <= 1'b0;
                if (cnt == 3)
                    state <= s3_green;
                else
                    state <= s1_red;
            end
            s2_yellow: begin
                p_red <= 1'b0;
                p_green <= 1'b0;
                p_yellow <= 1'b1;
                if (cnt == 3)
                    state <= s1_red;
                else
                    state <= s2_yellow;
            end
            s3_green: begin
                p_red <= 1'b0;
                p_green <= 1'b1;
                p_yellow <= 1'b0;
                if (cnt == 3)
                    state <= s2_yellow;
                else
                    state <= s3_green;
            end
        endcase
    end

    always @(posedge clk or negedge rst_n)
        if (!rst_n)
            cnt <= 7'd10;
        else if (pass_request && green && (cnt > 10))
            cnt <= 7'd10;
        else if (!green && p_green)
            cnt <= 7'd60;
        else if (!yellow && p_yellow)
            cnt <= 7'd5;
        else if (!red && p_red)
            cnt <= 7'd10;
        else
            cnt <= cnt - 1;

    assign clock = cnt;

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            yellow <= 1'd0;
            red <= 1'd0;
            green <= 1'd0;
        end
        else begin
            yellow <= p_yellow;
            red <= p_red;
            green <= p_green;
        end

endmodule
