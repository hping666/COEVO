`timescale 1ns/1ps

module testbench_enhanced;

    // Signal declarations
    reg IN, CLK, RST;
    wire MATCH;
    wire MATCH_ref;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // DUT instantiation
    fsm uut (
        .IN(IN),
        .MATCH(MATCH),
        .CLK(CLK),
        .RST(RST)
    );

    // Golden reference instantiation
    golden_fsm ref_model (
        .IN(IN),
        .MATCH(MATCH_ref),
        .CLK(CLK),
        .RST(RST)
    );

    // Clock generation: 10ns period
    initial begin
        CLK = 0;
        forever #5 CLK = ~CLK;
    end

    // Check task
    task check;
        input [199:0] test_name;
        begin
            check_id = check_id + 1;
            total_checks = total_checks + 1;
            if (MATCH === MATCH_ref) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FAIL] Check %0d: %s - DUT MATCH=%b, REF MATCH=%b at time %0t", check_id, test_name, MATCH, MATCH_ref, $time);
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
        // Initialize
        IN = 0;
        RST = 1;
        @(posedge CLK); #1;
        @(posedge CLK); #1;
        RST = 0;
        @(posedge CLK); #1;

        // =============================================
        // Group A: Original testbench cases
        // =============================================
        // Sequence: 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1
        // From original TB (after reset, IN starts at 0)

        IN = 0; @(posedge CLK); #1;
        check("A: IN=0 (seq 0)");

        IN = 0; @(posedge CLK); #1;
        check("A: IN=0 (seq 00)");

        IN = 1; @(posedge CLK); #1;
        check("A: IN=1 (seq 001)");

        IN = 1; @(posedge CLK); #1;
        check("A: IN=1 (seq 0011)");

        IN = 0; @(posedge CLK); #1;
        check("A: IN=0 (seq 00110)");

        IN = 0; @(posedge CLK); #1;
        check("A: IN=0 (seq 001100)");

        IN = 1; @(posedge CLK); #1;
        check("A: IN=1 (seq 0011001)");

        IN = 1; @(posedge CLK); #1;
        check("A: IN=1 (seq 00110011 MATCH)");

        IN = 0; @(posedge CLK); #1;
        check("A: IN=0 (seq 001100110)");

        IN = 0; @(posedge CLK); #1;
        check("A: IN=0 (seq 0011001100)");

        IN = 1; @(posedge CLK); #1;
        check("A: IN=1 (seq 00110011001)");

        IN = 1; @(posedge CLK); #1;
        check("A: IN=1 (seq 001100110011 MATCH)");

        // =============================================
        // Group B: Boundary/corner cases
        // =============================================

        // B1: Reset and detect full sequence 10011
        RST = 1;
        @(posedge CLK); #1;
        check("B: After reset");
        RST = 0;
        @(posedge CLK); #1;

        IN = 1; @(posedge CLK); #1;
        check("B: seq 1");
        IN = 0; @(posedge CLK); #1;
        check("B: seq 10");
        IN = 0; @(posedge CLK); #1;
        check("B: seq 100");
        IN = 1; @(posedge CLK); #1;
        check("B: seq 1001");
        IN = 1; @(posedge CLK); #1;
        check("B: seq 10011 MATCH");

        // B2: All zeros - stay in s0
        RST = 1; @(posedge CLK); #1;
        RST = 0; @(posedge CLK); #1;
        for (i = 0; i < 5; i = i + 1) begin
            IN = 0; @(posedge CLK); #1;
            check("B: all zeros");
        end

        // B3: All ones - toggle s1
        RST = 1; @(posedge CLK); #1;
        RST = 0; @(posedge CLK); #1;
        for (i = 0; i < 5; i = i + 1) begin
            IN = 1; @(posedge CLK); #1;
            check("B: all ones");
        end

        // B4: Reset from each state
        // s0: reset from idle
        RST = 1; @(posedge CLK); #1;
        RST = 0; @(posedge CLK); #1;
        check("B: reset from s0");

        // s1: go to s1 (IN=1), then reset
        IN = 1; @(posedge CLK); #1;
        RST = 1; @(posedge CLK); #1;
        check("B: reset from s1");
        RST = 0; @(posedge CLK); #1;

        // s2: go 1,0 => s2, then reset
        IN = 1; @(posedge CLK); #1;
        IN = 0; @(posedge CLK); #1;
        RST = 1; @(posedge CLK); #1;
        check("B: reset from s2");
        RST = 0; @(posedge CLK); #1;

        // s3: go 1,0,0 => s3, then reset
        IN = 1; @(posedge CLK); #1;
        IN = 0; @(posedge CLK); #1;
        IN = 0; @(posedge CLK); #1;
        RST = 1; @(posedge CLK); #1;
        check("B: reset from s3");
        RST = 0; @(posedge CLK); #1;

        // s4: go 1,0,0,1 => s4, then reset
        IN = 1; @(posedge CLK); #1;
        IN = 0; @(posedge CLK); #1;
        IN = 0; @(posedge CLK); #1;
        IN = 1; @(posedge CLK); #1;
        RST = 1; @(posedge CLK); #1;
        check("B: reset from s4");
        RST = 0; @(posedge CLK); #1;

        // s5: go 1,0,0,1,1 => s5, then reset
        IN = 1; @(posedge CLK); #1;
        IN = 0; @(posedge CLK); #1;
        IN = 0; @(posedge CLK); #1;
        IN = 1; @(posedge CLK); #1;
        IN = 1; @(posedge CLK); #1;
        RST = 1; @(posedge CLK); #1;
        check("B: reset from s5");
        RST = 0; @(posedge CLK); #1;

        // B5: All state transitions explicitly
        // s0 -> s0 (IN=0)
        RST = 1; @(posedge CLK); #1; RST = 0; @(posedge CLK); #1;
        IN = 0; @(posedge CLK); #1;
        check("B: s0->s0 IN=0");
        // s0 -> s1 (IN=1)
        RST = 1; @(posedge CLK); #1; RST = 0; @(posedge CLK); #1;
        IN = 1; @(posedge CLK); #1;
        check("B: s0->s1 IN=1");
        // s1 -> s1 (IN=1)
        IN = 1; @(posedge CLK); #1;
        check("B: s1->s1 IN=1");
        // s1 -> s2 (IN=0)
        IN = 0; @(posedge CLK); #1;
        check("B: s1->s2 IN=0");
        // s2 -> s1 (IN=1)
        IN = 1; @(posedge CLK); #1;
        check("B: s2->s1 IN=1");
        // s2 -> s3 (IN=0): need to get back to s2 first
        RST = 1; @(posedge CLK); #1; RST = 0; @(posedge CLK); #1;
        IN = 1; @(posedge CLK); #1; // s1
        IN = 0; @(posedge CLK); #1; // s2
        IN = 0; @(posedge CLK); #1;
        check("B: s2->s3 IN=0");
        // s3 -> s0 (IN=0)
        IN = 0; @(posedge CLK); #1;
        check("B: s3->s0 IN=0");
        // s3 -> s4 (IN=1): need to get to s3
        RST = 1; @(posedge CLK); #1; RST = 0; @(posedge CLK); #1;
        IN = 1; @(posedge CLK); #1; // s1
        IN = 0; @(posedge CLK); #1; // s2
        IN = 0; @(posedge CLK); #1; // s3
        IN = 1; @(posedge CLK); #1;
        check("B: s3->s4 IN=1");
        // s4 -> s2 (IN=0)
        IN = 0; @(posedge CLK); #1;
        check("B: s4->s2 IN=0");
        // s4 -> s5 (IN=1): get to s4
        RST = 1; @(posedge CLK); #1; RST = 0; @(posedge CLK); #1;
        IN = 1; @(posedge CLK); #1; // s1
        IN = 0; @(posedge CLK); #1; // s2
        IN = 0; @(posedge CLK); #1; // s3
        IN = 1; @(posedge CLK); #1; // s4
        IN = 1; @(posedge CLK); #1;
        check("B: s4->s5 IN=1 MATCH");
        // s5 -> s2 (IN=0)
        IN = 0; @(posedge CLK); #1;
        check("B: s5->s2 IN=0");
        // s5 -> s1 (IN=1): get to s5
        RST = 1; @(posedge CLK); #1; RST = 0; @(posedge CLK); #1;
        IN = 1; @(posedge CLK); #1; // s1
        IN = 0; @(posedge CLK); #1; // s2
        IN = 0; @(posedge CLK); #1; // s3
        IN = 1; @(posedge CLK); #1; // s4
        IN = 1; @(posedge CLK); #1; // s5 (match)
        IN = 1; @(posedge CLK); #1;
        check("B: s5->s1 IN=1");

        // =============================================
        // Group C: Randomized stress tests
        // =============================================
        RST = 1; @(posedge CLK); #1;
        RST = 0; @(posedge CLK); #1;
        for (i = 0; i < 30; i = i + 1) begin
            IN = $random(seed) % 2;
            @(posedge CLK); #1;
            check("C: random");
        end

        // =============================================
        // Group D: Protocol/timing tests
        // =============================================

        // D1: Reset during operation (mid-sequence)
        RST = 1; @(posedge CLK); #1; RST = 0; @(posedge CLK); #1;
        IN = 1; @(posedge CLK); #1;
        check("D: start seq 1");
        IN = 0; @(posedge CLK); #1;
        check("D: seq 10");
        IN = 0; @(posedge CLK); #1;
        check("D: seq 100");
        // Reset in middle
        RST = 1; @(posedge CLK); #1;
        check("D: reset mid-seq");
        RST = 0; @(posedge CLK); #1;
        check("D: after mid-reset");
        // Now try full sequence from scratch
        IN = 1; @(posedge CLK); #1;
        check("D: new 1");
        IN = 0; @(posedge CLK); #1;
        check("D: new 10");
        IN = 0; @(posedge CLK); #1;
        check("D: new 100");
        IN = 1; @(posedge CLK); #1;
        check("D: new 1001");
        IN = 1; @(posedge CLK); #1;
        check("D: new 10011 MATCH");

        // D2: Back-to-back valid sequences
        // After match at s5, continue with 0,0,1,1 to get another match
        IN = 0; @(posedge CLK); #1;
        check("D: bb 0");
        IN = 0; @(posedge CLK); #1;
        check("D: bb 00");
        IN = 1; @(posedge CLK); #1;
        check("D: bb 001");
        IN = 1; @(posedge CLK); #1;
        check("D: bb 0011 MATCH");

        // D3: Idle periods (hold input constant between sequences)
        RST = 1; @(posedge CLK); #1; RST = 0; @(posedge CLK); #1;
        IN = 0; @(posedge CLK); #1;
        check("D: idle 0");
        IN = 0; @(posedge CLK); #1;
        check("D: idle 0");
        IN = 0; @(posedge CLK); #1;
        check("D: idle 0");
        // Now detect
        IN = 1; @(posedge CLK); #1;
        check("D: after idle 1");
        IN = 0; @(posedge CLK); #1;
        check("D: after idle 10");
        IN = 0; @(posedge CLK); #1;
        check("D: after idle 100");
        IN = 1; @(posedge CLK); #1;
        check("D: after idle 1001");
        IN = 1; @(posedge CLK); #1;
        check("D: after idle 10011 MATCH");

        // D4: Quick reset pulse
        RST = 1; @(posedge CLK); #1;
        RST = 0; @(posedge CLK); #1;
        check("D: quick reset");

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
// Golden reference model
// =============================================
module golden_fsm(IN, MATCH, CLK, RST);
    input IN, CLK, RST;
    output reg MATCH;

    reg [2:0] ST_cr, ST_nt;

    parameter s0 = 3'b000;
    parameter s1 = 3'b001;
    parameter s2 = 3'b010;
    parameter s3 = 3'b011;
    parameter s4 = 3'b100;
    parameter s5 = 3'b101;

    always @(posedge CLK or posedge RST) begin
        if (RST)
            ST_cr <= s0;
        else
            ST_cr <= ST_nt;
    end

    always @(*) begin
        case (ST_cr)
            s0: begin
                if (IN == 0)
                    ST_nt = s0;
                else
                    ST_nt = s1;
            end
            s1: begin
                if (IN == 0)
                    ST_nt = s2;
                else
                    ST_nt = s1;
            end
            s2: begin
                if (IN == 0)
                    ST_nt = s3;
                else
                    ST_nt = s1;
            end
            s3: begin
                if (IN == 0)
                    ST_nt = s0;
                else
                    ST_nt = s4;
            end
            s4: begin
                if (IN == 0)
                    ST_nt = s2;
                else
                    ST_nt = s5;
            end
            s5: begin
                if (IN == 0)
                    ST_nt = s2;
                else
                    ST_nt = s1;
            end
            default: ST_nt = s0;
        endcase
    end

    always @(*) begin
        if (RST)
            MATCH = 0;
        else if (ST_cr == s4 && IN == 1)
            MATCH = 1;
        else
            MATCH = 0;
    end

endmodule
