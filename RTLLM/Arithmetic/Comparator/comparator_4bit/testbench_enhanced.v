`timescale 1ns/1ps

module testbench_enhanced;

    // SECTION 1: Signal declarations
    reg [3:0] A;
    reg [3:0] B;

    wire dut_A_greater, dut_A_equal, dut_A_less;
    wire ref_A_greater, ref_A_equal, ref_A_less;

    // SECTION 3: Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i, j;

    // SECTION 4: DUT instantiation
    comparator_4bit uut (
        .A(A),
        .B(B),
        .A_greater(dut_A_greater),
        .A_equal(dut_A_equal),
        .A_less(dut_A_less)
    );

    // SECTION 5: Golden reference instantiation
    golden_comparator_4bit ref_model (
        .A(A),
        .B(B),
        .A_greater(ref_A_greater),
        .A_equal(ref_A_equal),
        .A_less(ref_A_less)
    );

    // SECTION 6: Check task
    task check_outputs;
        input [255:0] description;
        begin
            check_id = check_id + 1;
            total_checks = total_checks + 1;
            if (dut_A_greater !== ref_A_greater ||
                dut_A_equal !== ref_A_equal ||
                dut_A_less !== ref_A_less) begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL | %0s | A=%b B=%b | expected gt=%b eq=%b lt=%b got gt=%b eq=%b lt=%b | time=%0t",
                    check_id, description, A, B,
                    ref_A_greater, ref_A_equal, ref_A_less,
                    dut_A_greater, dut_A_equal, dut_A_less, $time);
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
        A = 0; B = 0;
        #1;

        // =============================================
        // Group A: Original testbench style random tests
        // =============================================
        for (i = 0; i < 5; i = i + 1) begin
            A = $random(seed) % 16;
            B = $random(seed) % 16;
            #1;
            check_outputs("GroupA: random from original");
        end

        // =============================================
        // Group B: Exhaustive - all 256 combinations
        // =============================================
        for (i = 0; i < 16; i = i + 1) begin
            for (j = 0; j < 16; j = j + 1) begin
                A = i[3:0];
                B = j[3:0];
                #1;
                check_outputs("GroupB: exhaustive");
            end
        end

        // =============================================
        // Group C: Randomized stress tests
        // =============================================
        for (i = 0; i < 30; i = i + 1) begin
            A = $random(seed) % 16;
            B = $random(seed) % 16;
            #1;
            check_outputs("GroupC: random stress");
        end

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

// =============================================
// Golden reference model
// =============================================
module golden_comparator_4bit(
    input [3:0] A,
    input [3:0] B,
    output A_greater,
    output A_equal,
    output A_less
);

    wire [3:0] diff;
    wire cout;

    assign {cout, diff} = A - B;

    assign A_greater = (~cout && diff != 4'b0000);
    assign A_equal = (A == B);
    assign A_less = cout;

endmodule
