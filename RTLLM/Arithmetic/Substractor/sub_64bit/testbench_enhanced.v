`timescale 1ns/1ps

module testbench_enhanced;

    // Signals
    reg  [63:0] A;
    reg  [63:0] B;
    wire [63:0] result;
    wire        overflow;
    wire [63:0] result_ref;
    wire        overflow_ref;

    // Test infrastructure
    integer total_checks  = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id      = 0;
    integer seed          = 42;
    integer i;

    // DUT instantiation
    sub_64bit uut (
        .A(A),
        .B(B),
        .result(result),
        .overflow(overflow)
    );

    // Golden reference instantiation
    golden_sub_64bit ref_model (
        .A(A),
        .B(B),
        .result(result_ref),
        .overflow(overflow_ref)
    );

    // Check task - checks both result and overflow
    task check;
        begin
            // Check result
            total_checks = total_checks + 1;
            check_id = check_id + 1;
            if (result === result_ref) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL: A=%h B=%h result DUT=%h REF=%h", check_id, A, B, result, result_ref);
            end
            // Check overflow
            total_checks = total_checks + 1;
            check_id = check_id + 1;
            if (overflow === overflow_ref) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL: A=%h B=%h overflow DUT=%b REF=%b", check_id, A, B, overflow, overflow_ref);
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

        // ===== Group A: Original testbench cases (basic random) =====
        $display("--- Group A: Original testbench cases ---");
        for (i = 0; i < 5; i = i + 1) begin
            A = $random(seed);
            B = $random(seed);
            #10;
            check;
        end

        // ===== Group B: Boundary/corner cases =====
        $display("--- Group B: Boundary/corner cases ---");

        // B1: Zero - Zero
        A = 64'h0000_0000_0000_0000;
        B = 64'h0000_0000_0000_0000;
        #10; check;

        // B2: Max positive - 0
        A = 64'h7FFF_FFFF_FFFF_FFFF;
        B = 64'h0000_0000_0000_0000;
        #10; check;

        // B3: 0 - Max positive
        A = 64'h0000_0000_0000_0000;
        B = 64'h7FFF_FFFF_FFFF_FFFF;
        #10; check;

        // B4: Max negative - 0
        A = 64'h8000_0000_0000_0000;
        B = 64'h0000_0000_0000_0000;
        #10; check;

        // B5: 0 - Max negative (should overflow: 0 - (-2^63) = 2^63 which doesn't fit)
        A = 64'h0000_0000_0000_0000;
        B = 64'h8000_0000_0000_0000;
        #10; check;

        // B6: Max positive - Max positive (= 0, no overflow)
        A = 64'h7FFF_FFFF_FFFF_FFFF;
        B = 64'h7FFF_FFFF_FFFF_FFFF;
        #10; check;

        // B7: Max negative - Max negative (= 0, no overflow)
        A = 64'h8000_0000_0000_0000;
        B = 64'h8000_0000_0000_0000;
        #10; check;

        // B8: Max positive - Max negative (positive overflow)
        A = 64'h7FFF_FFFF_FFFF_FFFF;
        B = 64'h8000_0000_0000_0000;
        #10; check;

        // B9: Max negative - Max positive (negative overflow)
        A = 64'h8000_0000_0000_0000;
        B = 64'h7FFF_FFFF_FFFF_FFFF;
        #10; check;

        // B10: 1 - 1
        A = 64'h0000_0000_0000_0001;
        B = 64'h0000_0000_0000_0001;
        #10; check;

        // B11: -1 - 1
        A = 64'hFFFF_FFFF_FFFF_FFFF;
        B = 64'h0000_0000_0000_0001;
        #10; check;

        // B12: 1 - (-1)
        A = 64'h0000_0000_0000_0001;
        B = 64'hFFFF_FFFF_FFFF_FFFF;
        #10; check;

        // B13: -1 - (-1) = 0
        A = 64'hFFFF_FFFF_FFFF_FFFF;
        B = 64'hFFFF_FFFF_FFFF_FFFF;
        #10; check;

        // B14: Max positive - (-1) (positive overflow)
        A = 64'h7FFF_FFFF_FFFF_FFFF;
        B = 64'hFFFF_FFFF_FFFF_FFFF;
        #10; check;

        // B15: Min negative - 1 (negative overflow)
        A = 64'h8000_0000_0000_0000;
        B = 64'h0000_0000_0000_0001;
        #10; check;

        // B16: a > b, both positive
        A = 64'h0000_0000_0000_000A;
        B = 64'h0000_0000_0000_0005;
        #10; check;

        // B17: a < b, both positive
        A = 64'h0000_0000_0000_0005;
        B = 64'h0000_0000_0000_000A;
        #10; check;

        // B18: a == b, positive
        A = 64'h0000_0000_1234_5678;
        B = 64'h0000_0000_1234_5678;
        #10; check;

        // B19: All F's
        A = 64'hFFFF_FFFF_FFFF_FFFF;
        B = 64'hFFFF_FFFF_FFFF_FFFF;
        #10; check;

        // B20: All F's - 0
        A = 64'hFFFF_FFFF_FFFF_FFFF;
        B = 64'h0000_0000_0000_0000;
        #10; check;

        // ===== Group C: Randomized stress tests =====
        $display("--- Group C: Randomized stress tests ---");
        for (i = 0; i < 30; i = i + 1) begin
            A = {$random(seed), $random(seed)};
            B = {$random(seed), $random(seed)};
            #10;
            check;
        end

        // ===== Group D: Directed overflow tests =====
        $display("--- Group D: Directed overflow tests ---");

        // D1: Near positive overflow boundary
        A = 64'h7FFF_FFFF_FFFF_FFFE;
        B = 64'hFFFF_FFFF_FFFF_FFFF; // -1
        #10; check;

        // D2: At positive overflow boundary
        A = 64'h7FFF_FFFF_FFFF_FFFF;
        B = 64'hFFFF_FFFF_FFFF_FFFE; // -2
        #10; check;

        // D3: Near negative overflow boundary
        A = 64'h8000_0000_0000_0001;
        B = 64'h0000_0000_0000_0001;
        #10; check;

        // D4: Exactly at negative overflow
        A = 64'h8000_0000_0000_0000;
        B = 64'h0000_0000_0000_0002;
        #10; check;

        // D5: No overflow, different signs
        A = 64'hFFFF_FFFF_FFFF_FFF0; // -16
        B = 64'hFFFF_FFFF_FFFF_FFF0; // -16
        #10; check;

        // D6: Alternating patterns
        A = 64'h5555_5555_5555_5555;
        B = 64'hAAAA_AAAA_AAAA_AAAA;
        #10; check;

        A = 64'hAAAA_AAAA_AAAA_AAAA;
        B = 64'h5555_5555_5555_5555;
        #10; check;

        // D7: Powers of 2
        A = 64'h4000_0000_0000_0000;
        B = 64'hC000_0000_0000_0000;
        #10; check;

        // D8: Half-word boundaries
        A = 64'h0000_FFFF_0000_FFFF;
        B = 64'hFFFF_0000_FFFF_0000;
        #10; check;

        // D9: Large positive - small negative (no overflow)
        A = 64'h0000_0000_0000_0010;
        B = 64'hFFFF_FFFF_FFFF_FFF0; // -16
        #10; check;

        // ===== Score Reporting =====
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
module golden_sub_64bit(
  input [63:0] A,
  input [63:0] B,
  output reg [63:0] result,
  output reg overflow
);
  always @(*) begin
    result = A - B;

    if ((A[63] != B[63]) && (result[63] != A[63])) begin
      overflow = 1;
    end else begin
      overflow = 0;
    end
  end

endmodule
