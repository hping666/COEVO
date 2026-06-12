`timescale 1ns/1ps

module testbench_enhanced;

    // Signal declarations
    reg clk;
    reg rst;
    reg [31:0] a, b;
    wire [31:0] c;
    wire [31:0] c_ref;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk;

    // DUT instantiation
    pe uut (
        .clk(clk), .rst(rst), .a(a), .b(b), .c(c)
    );

    // Golden reference instantiation
    golden_pe ref_model (
        .clk(clk), .rst(rst), .a(a), .b(b), .c(c_ref)
    );

    // Check task
    task check_output;
        begin
            check_id = check_id + 1;
            total_checks = total_checks + 1;
            if (c === c_ref) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL c: expected=%h actual=%h (a=%h b=%h)", check_id, c_ref, c, a, b);
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
        a = 0;
        b = 0;
        rst = 1;

        // ===================== Group A: Original testbench cases =====================
        @(posedge clk); #1;
        check_output;

        rst = 0;
        @(posedge clk); #1;
        check_output;

        a = 1; b = 1;
        @(posedge clk); #1;
        check_output; // c should be 1

        a = 2; b = 2;
        @(posedge clk); #1;
        check_output; // c should be 1+4=5

        a = 3; b = 3;
        @(posedge clk); #1;
        check_output; // c should be 5+9=14=0xE

        // ===================== Group B: Boundary/corner cases =====================

        // B1: Reset during accumulation
        rst = 1;
        @(posedge clk); #1;
        check_output; // c should be 0

        rst = 0;
        @(posedge clk); #1;
        check_output;

        // B2: Zero operands
        a = 0; b = 0;
        @(posedge clk); #1;
        check_output;
        @(posedge clk); #1;
        check_output;

        // B3: One operand zero
        a = 32'h12345678; b = 0;
        @(posedge clk); #1;
        check_output;

        a = 0; b = 32'h12345678;
        @(posedge clk); #1;
        check_output;

        // B4: Multiply by 1
        a = 1; b = 32'hABCDEF01;
        @(posedge clk); #1;
        check_output;

        a = 32'hABCDEF01; b = 1;
        @(posedge clk); #1;
        check_output;

        // B5: Max values
        rst = 1;
        @(posedge clk); #1;
        check_output;
        rst = 0;
        a = 32'hFFFFFFFF; b = 32'hFFFFFFFF;
        @(posedge clk); #1;
        check_output;

        // B6: Power of 2
        rst = 1;
        @(posedge clk); #1;
        check_output;
        rst = 0;
        a = 32'h00000002; b = 32'h00000004;
        @(posedge clk); #1;
        check_output; // 8

        a = 32'h00000008; b = 32'h00000010;
        @(posedge clk); #1;
        check_output; // 8 + 128 = 136

        // B7: Async reset (posedge rst)
        a = 32'h100; b = 32'h100;
        rst = 1; #1;
        check_output; // Should reset immediately
        rst = 0;
        @(posedge clk); #1;
        check_output;

        // B8: Continuous accumulation
        rst = 1;
        @(posedge clk); #1;
        check_output;
        rst = 0;
        a = 10; b = 10;
        for (i = 0; i < 5; i = i + 1) begin
            @(posedge clk); #1;
            check_output; // 100, 200, 300, 400, 500
        end

        // ===================== Group C: Randomized stress =====================
        rst = 1;
        @(posedge clk); #1;
        check_output;
        rst = 0;

        for (i = 0; i < 20; i = i + 1) begin
            a = $random(seed);
            b = $random(seed);
            @(posedge clk); #1;
            check_output;
        end

        // Random with occasional resets
        for (i = 0; i < 15; i = i + 1) begin
            if (i % 5 == 0) begin
                rst = 1;
                @(posedge clk); #1;
                check_output;
                rst = 0;
            end
            a = $random(seed);
            b = $random(seed);
            @(posedge clk); #1;
            check_output;
        end

        // ===================== Group D: Protocol/timing tests =====================

        // D1: Reset pulse width
        rst = 1;
        @(posedge clk); #1;
        check_output;
        rst = 0;
        a = 5; b = 5;
        @(posedge clk); #1;
        check_output;

        // D2: Same inputs for multiple cycles
        a = 7; b = 3;
        @(posedge clk); #1;
        check_output;
        @(posedge clk); #1;
        check_output;
        @(posedge clk); #1;
        check_output;

        // D3: Change inputs mid-cycle (shouldn't affect until next edge)
        a = 100; b = 200;
        #3;
        a = 1; b = 1;
        @(posedge clk); #1;
        check_output;

        // D4: Multiple resets in sequence
        rst = 1;
        @(posedge clk); #1;
        check_output;
        @(posedge clk); #1;
        check_output;
        rst = 0;
        @(posedge clk); #1;
        check_output;

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
// Golden reference model - copy of verified_pe.v renamed
// ============================================================
module golden_pe(
    input clk,
    input rst,
    input [31:0] a,
    input [31:0] b,
    output [31:0] c
);

    reg [31:0] cc;
    assign c = cc;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cc <= 0;
        end else begin
            cc <= cc + a * b;
        end
    end

endmodule
