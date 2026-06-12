`timescale 1ns/1ps

module testbench_enhanced;

    // SECTION 1: Signal declarations
    reg [3:0] A;
    reg [3:0] B;
    reg Cin;

    wire [3:0] Sum_dut, Sum_ref;
    wire Cout_dut, Cout_ref;

    // SECTION 3: Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i, j, k;

    // SECTION 4: DUT instantiation
    adder_bcd uut (
        .A(A),
        .B(B),
        .Cin(Cin),
        .Sum(Sum_dut),
        .Cout(Cout_dut)
    );

    // SECTION 5: Golden reference instantiation
    golden_adder_bcd ref_model (
        .A(A),
        .B(B),
        .Cin(Cin),
        .Sum(Sum_ref),
        .Cout(Cout_ref)
    );

    // SECTION 6: Check task
    task check_outputs;
        input [255:0] description;
        begin
            check_id = check_id + 1;
            total_checks = total_checks + 1;
            if (Sum_dut !== Sum_ref || Cout_dut !== Cout_ref) begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL | %0s | expected Sum=%h Cout=%b got Sum=%h Cout=%b | time=%0t",
                    check_id, description, Sum_ref, Cout_ref, Sum_dut, Cout_dut, $time);
            end else begin
                passed_checks = passed_checks + 1;
            end
        end
    endtask

    // SECTION 7: Watchdog timer
    initial begin
        #5000000;
        $display("[FORGE_RESULT] TIMEOUT");
        $finish;
    end

    // SECTION 8: Test cases
    initial begin
        A = 0; B = 0; Cin = 0;

        // ---- Group A: Original testbench-style random BCD cases ----
        for (i = 0; i < 5; i = i + 1) begin
            A = $random(seed) % 10;
            B = $random(seed) % 10;
            Cin = $random(seed) % 2;
            #1;
            check_outputs("A: original-style random BCD");
        end

        // ---- Group B: Boundary/corner cases ----

        // B1: 0+0+0
        A = 4'd0; B = 4'd0; Cin = 0; #1;
        check_outputs("B1: 0+0, cin=0");

        // B2: 0+0+1
        A = 4'd0; B = 4'd0; Cin = 1; #1;
        check_outputs("B2: 0+0, cin=1");

        // B3: 9+0+0
        A = 4'd9; B = 4'd0; Cin = 0; #1;
        check_outputs("B3: 9+0, cin=0");

        // B4: 9+0+1 (should produce carry)
        A = 4'd9; B = 4'd0; Cin = 1; #1;
        check_outputs("B4: 9+0, cin=1");

        // B5: 0+9+0
        A = 4'd0; B = 4'd9; Cin = 0; #1;
        check_outputs("B5: 0+9, cin=0");

        // B6: 0+9+1
        A = 4'd0; B = 4'd9; Cin = 1; #1;
        check_outputs("B6: 0+9, cin=1");

        // B7: 9+9+0 = 18, BCD carry
        A = 4'd9; B = 4'd9; Cin = 0; #1;
        check_outputs("B7: 9+9, cin=0");

        // B8: 9+9+1 = 19, BCD carry
        A = 4'd9; B = 4'd9; Cin = 1; #1;
        check_outputs("B8: 9+9, cin=1");

        // B9: 5+5+0 = 10, just at BCD boundary
        A = 4'd5; B = 4'd5; Cin = 0; #1;
        check_outputs("B9: 5+5, cin=0 (boundary)");

        // B10: 5+4+1 = 10
        A = 4'd5; B = 4'd4; Cin = 1; #1;
        check_outputs("B10: 5+4, cin=1 (boundary)");

        // B11: 4+5+0 = 9, just below boundary
        A = 4'd4; B = 4'd5; Cin = 0; #1;
        check_outputs("B11: 4+5, cin=0 (below boundary)");

        // B12: 1+1+0
        A = 4'd1; B = 4'd1; Cin = 0; #1;
        check_outputs("B12: 1+1, cin=0");

        // B13: 1+1+1
        A = 4'd1; B = 4'd1; Cin = 1; #1;
        check_outputs("B13: 1+1, cin=1");

        // B14: 8+1+0
        A = 4'd8; B = 4'd1; Cin = 0; #1;
        check_outputs("B14: 8+1, cin=0");

        // B15: 8+1+1
        A = 4'd8; B = 4'd1; Cin = 1; #1;
        check_outputs("B15: 8+1, cin=1");

        // B16: 8+2+0
        A = 4'd8; B = 4'd2; Cin = 0; #1;
        check_outputs("B16: 8+2, cin=0");

        // B17: 7+3+0
        A = 4'd7; B = 4'd3; Cin = 0; #1;
        check_outputs("B17: 7+3, cin=0");

        // B18: 6+4+0
        A = 4'd6; B = 4'd4; Cin = 0; #1;
        check_outputs("B18: 6+4, cin=0");

        // B19: 6+4+1
        A = 4'd6; B = 4'd4; Cin = 1; #1;
        check_outputs("B19: 6+4, cin=1");

        // B20: 3+3+0
        A = 4'd3; B = 4'd3; Cin = 0; #1;
        check_outputs("B20: 3+3, cin=0");

        // ---- Exhaustive sweep of all valid BCD combinations ----
        // This covers 10*10*2 = 200 combinations but we only need ~50 from Group C
        // We'll use a subset via random seed

        // ---- Group C: Randomized stress tests ----
        for (i = 0; i < 50; i = i + 1) begin
            A = $random(seed) % 10;
            B = $random(seed) % 10;
            Cin = $random(seed) % 2;
            #1;
            check_outputs("C: random BCD stress test");
        end

        // Additional boundary tests for completeness
        A = 4'd2; B = 4'd8; Cin = 0; #1;
        check_outputs("B21: 2+8, cin=0");
        A = 4'd2; B = 4'd8; Cin = 1; #1;
        check_outputs("B22: 2+8, cin=1");
        A = 4'd7; B = 4'd7; Cin = 0; #1;
        check_outputs("B23: 7+7, cin=0");
        A = 4'd7; B = 4'd7; Cin = 1; #1;
        check_outputs("B24: 7+7, cin=1");
        A = 4'd6; B = 4'd6; Cin = 0; #1;
        check_outputs("B25: 6+6, cin=0");

        // SECTION 9: Score reporting
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

// SECTION 10: Golden reference model

module golden_adder_bcd (
    input  [3:0] A,
    input  [3:0] B,
    input  Cin,
    output [3:0] Sum,
    output Cout
);
    wire [4:0] temp_sum;
    wire [3:0] corrected_sum;
    wire carry_out;

    assign temp_sum = A + B + Cin;

    assign carry_out = (temp_sum > 9) ? 1 : 0;
    assign corrected_sum = (temp_sum > 9) ? (temp_sum + 4'b0110) : temp_sum;

    assign Sum = corrected_sum[3:0];
    assign Cout = carry_out;
endmodule
