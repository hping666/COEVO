`timescale 1ns/1ps

module testbench_enhanced;

    // Signal declarations
    reg clk;
    reg rst_n;
    reg data_in;
    wire data_out;
    wire data_out_ref;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // DUT instantiation
    pulse_detect uut (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(data_in),
        .data_out(data_out)
    );

    // Golden reference instantiation
    golden_pulse_detect ref_model (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(data_in),
        .data_out(data_out_ref)
    );

    // Clock generation: 10ns period
    initial clk = 0;
    always #5 clk = ~clk;

    // Check task - since data_out is combinational, check after posedge clk + settle
    task check;
        input [255:0] test_name;
        begin
            check_id = check_id + 1;
            total_checks = total_checks + 1;
            if (data_out !== data_out_ref) begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL %0s | DUT=%b, REF=%b, data_in=%b at time %0t",
                    check_id, test_name, data_out, data_out_ref, data_in, $time);
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

    // Main test stimulus
    initial begin
        // =============================================
        // Group A: Original testbench cases
        // =============================================
        rst_n = 0;
        data_in = 0;
        @(posedge clk); #1;
        check("A: reset state");
        @(posedge clk); #1;
        check("A: still in reset");

        rst_n = 1;
        @(posedge clk); #1;
        check("A: after reset");

        // Original sequence: 0,0,0,1,0,1,0,1,1,0
        data_in = 0; @(posedge clk); #1; check("A: seq 0");
        data_in = 0; @(posedge clk); #1; check("A: seq 0");
        data_in = 0; @(posedge clk); #1; check("A: seq 0");
        data_in = 1; @(posedge clk); #1; check("A: seq 1");
        data_in = 0; @(posedge clk); #1; check("A: seq 0 pulse end");
        data_in = 1; @(posedge clk); #1; check("A: seq 1");
        data_in = 0; @(posedge clk); #1; check("A: seq 0 pulse end");
        data_in = 1; @(posedge clk); #1; check("A: seq 1");
        data_in = 1; @(posedge clk); #1; check("A: seq 1 no pulse");
        data_in = 0; @(posedge clk); #1; check("A: seq 0");

        // =============================================
        // Group B: Boundary/corner cases
        // =============================================

        // B1: Single pulse 0->1->0
        rst_n = 0;
        data_in = 0;
        @(posedge clk); #1;
        rst_n = 1;
        data_in = 0; @(posedge clk); #1; check("B: before pulse 0");
        data_in = 1; @(posedge clk); #1; check("B: pulse high");
        data_in = 0; @(posedge clk); #1; check("B: pulse end detect");
        @(posedge clk); #1; check("B: after pulse");

        // B2: No pulse - all zeros
        rst_n = 0; @(posedge clk); #1; rst_n = 1;
        for (i = 0; i < 5; i = i + 1) begin
            data_in = 0;
            @(posedge clk); #1;
            check("B: all zeros");
        end

        // B3: No pulse - all ones
        data_in = 1;
        for (i = 0; i < 5; i = i + 1) begin
            @(posedge clk); #1;
            check("B: all ones");
        end

        // B4: Two consecutive pulses: 0,1,0,1,0
        rst_n = 0; @(posedge clk); #1; rst_n = 1;
        data_in = 0; @(posedge clk); #1; check("B: consec pulse setup");
        data_in = 1; @(posedge clk); #1; check("B: consec pulse1 high");
        data_in = 0; @(posedge clk); #1; check("B: consec pulse1 end");
        data_in = 1; @(posedge clk); #1; check("B: consec pulse2 high");
        data_in = 0; @(posedge clk); #1; check("B: consec pulse2 end");
        @(posedge clk); #1; check("B: after consec pulses");

        // B5: Long high then low (no pulse because 0 never preceded the 1)
        rst_n = 0; @(posedge clk); #1; rst_n = 1;
        data_in = 1; @(posedge clk); #1; check("B: start with 1");
        data_in = 1; @(posedge clk); #1; check("B: stay 1");
        data_in = 1; @(posedge clk); #1; check("B: stay 1");
        data_in = 0; @(posedge clk); #1; check("B: fall from 1 no pulse");

        // B6: Pulse after long zeros
        data_in = 0; @(posedge clk); #1; check("B: long zero 1");
        data_in = 0; @(posedge clk); #1; check("B: long zero 2");
        data_in = 0; @(posedge clk); #1; check("B: long zero 3");
        data_in = 1; @(posedge clk); #1; check("B: pulse after long zero");
        data_in = 0; @(posedge clk); #1; check("B: pulse end after long zero");

        // B7: Reset during pulse detection
        rst_n = 0; @(posedge clk); #1; rst_n = 1;
        data_in = 0; @(posedge clk); #1;
        data_in = 1; @(posedge clk); #1;
        rst_n = 0; @(posedge clk); #1; check("B: reset mid pulse");
        rst_n = 1;
        data_in = 0; @(posedge clk); #1; check("B: after mid-pulse reset");

        // B8: Pattern 1,0 without preceding 0 (from reset state s0)
        rst_n = 0; @(posedge clk); #1; rst_n = 1;
        data_in = 1; @(posedge clk); #1; check("B: 1 from s0");
        data_in = 0; @(posedge clk); #1; check("B: 0 from s0->stays s0");

        // =============================================
        // Group C: Randomized stress tests
        // =============================================
        rst_n = 0; @(posedge clk); #1; rst_n = 1;

        for (i = 0; i < 30; i = i + 1) begin
            data_in = $random(seed) % 2;
            if (($random(seed) % 20) < 1) begin
                rst_n = 0;
                @(posedge clk); #1;
                check("C: random reset");
                rst_n = 1;
            end
            @(posedge clk); #1;
            check("C: random stimulus");
        end

        // =============================================
        // Group D: Protocol/timing tests
        // =============================================

        // D1: Multiple pulses with gaps
        rst_n = 0; @(posedge clk); #1; rst_n = 1;
        data_in = 0; @(posedge clk); #1; check("D: gap before pulse1");
        data_in = 1; @(posedge clk); #1; check("D: pulse1 high");
        data_in = 0; @(posedge clk); #1; check("D: pulse1 end");
        data_in = 0; @(posedge clk); #1; check("D: gap");
        data_in = 0; @(posedge clk); #1; check("D: gap");
        data_in = 1; @(posedge clk); #1; check("D: pulse2 high");
        data_in = 0; @(posedge clk); #1; check("D: pulse2 end");

        // D2: Glitch-like pattern (0,1,1,0 - no pulse because 1 held for 2 cycles)
        data_in = 0; @(posedge clk); #1; check("D: glitch 0");
        data_in = 1; @(posedge clk); #1; check("D: glitch 1a");
        data_in = 1; @(posedge clk); #1; check("D: glitch 1b");
        data_in = 0; @(posedge clk); #1; check("D: glitch end 0");

        // D3: Alternating 0,1,0,1,0,1,0 - should detect pulses at each 0->1->0
        data_in = 0; @(posedge clk); #1; check("D: alt 0");
        data_in = 1; @(posedge clk); #1; check("D: alt 1");
        data_in = 0; @(posedge clk); #1; check("D: alt pulse1");
        data_in = 1; @(posedge clk); #1; check("D: alt 1");
        data_in = 0; @(posedge clk); #1; check("D: alt pulse2");
        data_in = 1; @(posedge clk); #1; check("D: alt 1");
        data_in = 0; @(posedge clk); #1; check("D: alt pulse3");

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
module golden_pulse_detect(
    input clk,
    input rst_n,
    input data_in,
    output reg data_out
);

parameter s0 = 2'b00; // initial
parameter s1 = 2'b01; // 0, 00
parameter s2 = 2'b10; // 01
parameter s3 = 2'b11; // 010

reg [1:0] pulse_level1, pulse_level2;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        pulse_level1 <= s0;
    else
        pulse_level1 <= pulse_level2;
end

always @(*) begin
    case (pulse_level1)
        s0: begin
            if (data_in == 0)
                pulse_level2 = s1;
            else
                pulse_level2 = s0;
        end

        s1: begin
            if (data_in == 1)
                pulse_level2 = s2;
            else
                pulse_level2 = s1;
        end

        s2: begin
            if (data_in == 0)
                pulse_level2 = s3;
            else
                pulse_level2 = s0;
        end

        s3: begin
            if (data_in == 1)
                pulse_level2 = s2;
            else
                pulse_level2 = s1;
        end
    endcase
end

always @(*) begin
    if (~rst_n)
        data_out = 0;
    else if (pulse_level1 == s2 && data_in == 0)
        data_out = 1;
    else
        data_out = 0;
end

endmodule
