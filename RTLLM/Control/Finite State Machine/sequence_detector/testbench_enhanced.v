`timescale 1ns/1ps

module testbench_enhanced;

    // Signal declarations
    reg clk, rst_n, data_in;
    wire sequence_detected;
    wire sequence_detected_ref;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // DUT instantiation
    sequence_detector uut (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(data_in),
        .sequence_detected(sequence_detected)
    );

    // Golden reference instantiation
    golden_sequence_detector ref_model (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(data_in),
        .sequence_detected(sequence_detected_ref)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Check task
    task check;
        input [199:0] test_name;
        begin
            check_id = check_id + 1;
            total_checks = total_checks + 1;
            if (sequence_detected === sequence_detected_ref) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FAIL] Check %0d: %s - DUT=%b, REF=%b at time %0t", check_id, test_name, sequence_detected, sequence_detected_ref, $time);
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
        data_in = 0;
        rst_n = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;

        // =============================================
        // Group A: Original testbench cases
        // =============================================
        // Sequence: 1,1,0,0,1 then check, 1,0,0,1 then check
        data_in = 1; @(posedge clk); #1;
        check("A: IN=1");
        data_in = 1; @(posedge clk); #1;
        check("A: IN=1 (11)");
        data_in = 0; @(posedge clk); #1;
        check("A: IN=0 (110)");
        data_in = 0; @(posedge clk); #1;
        check("A: IN=0 (1100)");
        data_in = 1; @(posedge clk); #1;
        check("A: IN=1 (11001) detect");
        data_in = 1; @(posedge clk); #1;
        check("A: IN=1 after detect");
        data_in = 1; @(posedge clk); #1;
        check("A: IN=1");
        data_in = 0; @(posedge clk); #1;
        check("A: IN=0");
        data_in = 0; @(posedge clk); #1;
        check("A: IN=0");
        data_in = 1; @(posedge clk); #1;
        check("A: IN=1 detect");

        // =============================================
        // Group B: Boundary/corner cases
        // =============================================

        // B1: Full sequence 1001 from clean state
        rst_n = 0; @(posedge clk); #1;
        check("B: reset");
        rst_n = 1; @(posedge clk); #1;
        check("B: after reset");
        data_in = 1; @(posedge clk); #1;
        check("B: 1");
        data_in = 0; @(posedge clk); #1;
        check("B: 10");
        data_in = 0; @(posedge clk); #1;
        check("B: 100");
        data_in = 1; @(posedge clk); #1;
        check("B: 1001 detect");

        // B2: All zeros
        rst_n = 0; @(posedge clk); #1;
        rst_n = 1; @(posedge clk); #1;
        for (i = 0; i < 5; i = i + 1) begin
            data_in = 0; @(posedge clk); #1;
            check("B: all zeros");
        end

        // B3: All ones
        rst_n = 0; @(posedge clk); #1;
        rst_n = 1; @(posedge clk); #1;
        for (i = 0; i < 5; i = i + 1) begin
            data_in = 1; @(posedge clk); #1;
            check("B: all ones");
        end

        // B4: Overlapping sequences: 1001001
        rst_n = 0; @(posedge clk); #1;
        rst_n = 1; @(posedge clk); #1;
        data_in = 1; @(posedge clk); #1;
        check("B: overlap 1");
        data_in = 0; @(posedge clk); #1;
        check("B: overlap 10");
        data_in = 0; @(posedge clk); #1;
        check("B: overlap 100");
        data_in = 1; @(posedge clk); #1;
        check("B: overlap 1001 det");
        data_in = 0; @(posedge clk); #1;
        check("B: overlap 10010");
        data_in = 0; @(posedge clk); #1;
        check("B: overlap 100100");
        data_in = 1; @(posedge clk); #1;
        check("B: overlap 1001001 det");

        // B5: Reset from each state
        // IDLE state reset
        rst_n = 0; @(posedge clk); #1;
        rst_n = 1; @(posedge clk); #1;
        rst_n = 0; @(posedge clk); #1;
        check("B: reset from IDLE");
        rst_n = 1; @(posedge clk); #1;

        // S1 state reset (after seeing 1)
        data_in = 1; @(posedge clk); #1;
        rst_n = 0; @(posedge clk); #1;
        check("B: reset from S1");
        rst_n = 1; @(posedge clk); #1;

        // S2 state reset (after 10)
        data_in = 1; @(posedge clk); #1;
        data_in = 0; @(posedge clk); #1;
        rst_n = 0; @(posedge clk); #1;
        check("B: reset from S2");
        rst_n = 1; @(posedge clk); #1;

        // S3 state reset (after 100)
        data_in = 1; @(posedge clk); #1;
        data_in = 0; @(posedge clk); #1;
        data_in = 0; @(posedge clk); #1;
        rst_n = 0; @(posedge clk); #1;
        check("B: reset from S3");
        rst_n = 1; @(posedge clk); #1;

        // S4 state reset (after 1001)
        data_in = 1; @(posedge clk); #1;
        data_in = 0; @(posedge clk); #1;
        data_in = 0; @(posedge clk); #1;
        data_in = 1; @(posedge clk); #1;
        rst_n = 0; @(posedge clk); #1;
        check("B: reset from S4");
        rst_n = 1; @(posedge clk); #1;

        // B6: All state transitions
        // IDLE->IDLE (0), IDLE->S1 (1)
        rst_n = 0; @(posedge clk); #1; rst_n = 1; @(posedge clk); #1;
        data_in = 0; @(posedge clk); #1;
        check("B: IDLE->IDLE");
        data_in = 1; @(posedge clk); #1;
        check("B: IDLE->S1");
        // S1->S1 (1), S1->S2 (0)
        data_in = 1; @(posedge clk); #1;
        check("B: S1->S1");
        data_in = 0; @(posedge clk); #1;
        check("B: S1->S2");
        // S2->S1 (1)
        data_in = 1; @(posedge clk); #1;
        check("B: S2->S1");
        // S2->S3 (0)
        rst_n = 0; @(posedge clk); #1; rst_n = 1; @(posedge clk); #1;
        data_in = 1; @(posedge clk); #1;
        data_in = 0; @(posedge clk); #1;
        data_in = 0; @(posedge clk); #1;
        check("B: S2->S3");
        // S3->IDLE (0)
        data_in = 0; @(posedge clk); #1;
        check("B: S3->IDLE");
        // S3->S4 (1)
        rst_n = 0; @(posedge clk); #1; rst_n = 1; @(posedge clk); #1;
        data_in = 1; @(posedge clk); #1;
        data_in = 0; @(posedge clk); #1;
        data_in = 0; @(posedge clk); #1;
        data_in = 1; @(posedge clk); #1;
        check("B: S3->S4 detect");
        // S4->S1 (1)
        data_in = 1; @(posedge clk); #1;
        check("B: S4->S1");
        // S4->S2 (0)
        rst_n = 0; @(posedge clk); #1; rst_n = 1; @(posedge clk); #1;
        data_in = 1; @(posedge clk); #1;
        data_in = 0; @(posedge clk); #1;
        data_in = 0; @(posedge clk); #1;
        data_in = 1; @(posedge clk); #1;
        data_in = 0; @(posedge clk); #1;
        check("B: S4->S2");

        // =============================================
        // Group C: Randomized stress tests
        // =============================================
        rst_n = 0; @(posedge clk); #1;
        rst_n = 1; @(posedge clk); #1;
        for (i = 0; i < 30; i = i + 1) begin
            data_in = $random(seed) % 2;
            @(posedge clk); #1;
            check("C: random");
        end

        // =============================================
        // Group D: Protocol/timing tests
        // =============================================

        // D1: Reset during operation
        rst_n = 0; @(posedge clk); #1; rst_n = 1; @(posedge clk); #1;
        data_in = 1; @(posedge clk); #1;
        check("D: start 1");
        data_in = 0; @(posedge clk); #1;
        check("D: 10");
        rst_n = 0; @(posedge clk); #1;
        check("D: reset mid");
        rst_n = 1; @(posedge clk); #1;
        check("D: after reset");
        data_in = 1; @(posedge clk); #1;
        check("D: new 1");
        data_in = 0; @(posedge clk); #1;
        check("D: new 10");
        data_in = 0; @(posedge clk); #1;
        check("D: new 100");
        data_in = 1; @(posedge clk); #1;
        check("D: new 1001 detect");

        // D2: Back-to-back valid sequences via overlap
        // After 1001 (S4), feed 0,0,1 to get another 1001
        data_in = 0; @(posedge clk); #1;
        check("D: bb 0");
        data_in = 0; @(posedge clk); #1;
        check("D: bb 00");
        data_in = 1; @(posedge clk); #1;
        check("D: bb 001 detect");

        // D3: Idle periods
        rst_n = 0; @(posedge clk); #1; rst_n = 1; @(posedge clk); #1;
        for (i = 0; i < 3; i = i + 1) begin
            data_in = 0; @(posedge clk); #1;
            check("D: idle");
        end
        data_in = 1; @(posedge clk); #1;
        check("D: after idle 1");
        data_in = 0; @(posedge clk); #1;
        check("D: after idle 10");
        data_in = 0; @(posedge clk); #1;
        check("D: after idle 100");
        data_in = 1; @(posedge clk); #1;
        check("D: after idle 1001");

        // D4: Alternating input
        rst_n = 0; @(posedge clk); #1; rst_n = 1; @(posedge clk); #1;
        for (i = 0; i < 6; i = i + 1) begin
            data_in = i % 2;
            @(posedge clk); #1;
            check("D: alternating");
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
// Golden reference model
// =============================================
module golden_sequence_detector(
    input  clk,
    input  rst_n,
    input  data_in,
    output sequence_detected
);

parameter        IDLE = 5'b00001;
parameter        S1   = 5'b00010;
parameter        S2   = 5'b00100;
parameter        S3   = 5'b01000;
parameter        S4   = 5'b10000;

reg [4:0]        curr_state;
reg [4:0]        next_state;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        curr_state <= IDLE;
    end
    else begin
        curr_state <= next_state;
    end
end

always @(*) begin
    if (!rst_n) begin
        next_state <= IDLE;
    end
    else begin
        case (curr_state)
            IDLE  : next_state = data_in ? S1 : IDLE;
            S1    : next_state = data_in ? S1 : S2;
            S2    : next_state = data_in ? S1 : S3;
            S3    : next_state = data_in ? S4 : IDLE;
            S4    : next_state = data_in ? S1 : S2;
            default: next_state = IDLE;
        endcase
    end
end

assign sequence_detected = (curr_state == S4) ? 1'b1 : 1'b0;

endmodule
