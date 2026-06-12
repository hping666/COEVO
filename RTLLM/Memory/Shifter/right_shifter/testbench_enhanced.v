`timescale 1ns/1ps

module testbench_enhanced;

    // Signal declarations
    reg clk;
    reg d;
    wire [7:0] q;
    wire [7:0] ref_q;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // DUT instantiation
    right_shifter uut (
        .clk(clk),
        .d(d),
        .q(q)
    );

    // Golden reference instantiation
    golden_right_shifter ref_model (
        .clk(clk),
        .d(d),
        .q(ref_q)
    );

    // Clock generation: 10ns period
    initial clk = 0;
    always #5 clk = ~clk;

    // Check task
    task check;
        input [255:0] description;
        begin
            total_checks = total_checks + 1;
            check_id = check_id + 1;
            if (q === ref_q) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL | %0s | expected=%b got=%b | time=%0t", check_id, description, ref_q, q, $time);
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
        // =============================================
        // Group A: Original testbench cases
        // =============================================
        d = 0;
        // Run 2 clocks with d=0
        @(posedge clk); #1;
        check("GroupA: d=0 cycle 1");
        @(posedge clk); #1;
        check("GroupA: d=0 cycle 2");

        d = 1;
        @(posedge clk); #1;
        check("GroupA: d=1 first");

        d = 0;
        @(posedge clk); #1;
        check("GroupA: d=0 after 1");

        d = 1;
        @(posedge clk); #1;
        check("GroupA: d=1 second");

        d = 0;
        @(posedge clk); #1;
        check("GroupA: d=0 second");

        d = 1;
        @(posedge clk); #1;
        check("GroupA: d=1 third");

        d = 1;
        @(posedge clk); #1;
        check("GroupA: d=1 fourth");

        d = 1;
        @(posedge clk); #1;
        check("GroupA: d=1 fifth");

        // =============================================
        // Group B: Boundary/corner cases
        // =============================================

        // B1: Shift all zeros
        d = 0;
        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk); #1;
            check("GroupB: Shift all zeros");
        end

        // B2: Shift all ones
        d = 1;
        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk); #1;
            check("GroupB: Shift all ones");
        end

        // B3: Shift single bit through register
        d = 0;
        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk); #1;
            check("GroupB: Clear register");
        end

        // Insert single 1
        d = 1;
        @(posedge clk); #1;
        check("GroupB: Insert single 1");

        // Shift it through
        d = 0;
        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk); #1;
            check("GroupB: Single bit shifting");
        end

        // B4: Alternating pattern 10101010
        for (i = 0; i < 8; i = i + 1) begin
            d = (i % 2 == 0) ? 1 : 0;
            @(posedge clk); #1;
            check("GroupB: Alternating pattern");
        end

        // =============================================
        // Group C: Randomized stress tests
        // =============================================
        for (i = 0; i < 30; i = i + 1) begin
            d = $random(seed) % 2;
            @(posedge clk); #1;
            check("GroupC: Random input");
        end

        // =============================================
        // Group D: Protocol/timing tests
        // =============================================

        // D1: Rapid toggling of d
        for (i = 0; i < 8; i = i + 1) begin
            d = ~d;
            @(posedge clk); #1;
            check("GroupD: Rapid toggle");
        end

        // D2: Hold d=1 for many cycles
        d = 1;
        for (i = 0; i < 10; i = i + 1) begin
            @(posedge clk); #1;
            check("GroupD: Hold d=1");
        end

        // D3: Hold d=0 for many cycles
        d = 0;
        for (i = 0; i < 10; i = i + 1) begin
            @(posedge clk); #1;
            check("GroupD: Hold d=0");
        end

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
module golden_right_shifter(clk, q, d);

    input  clk;
    input d;
    output  [7:0] q;
    reg   [7:0]  q;
    initial q = 0;

    always @(posedge clk)
          begin
            q <= (q >> 1);
            q[7] <= d;
          end

endmodule
