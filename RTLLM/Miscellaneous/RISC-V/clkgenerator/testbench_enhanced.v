`timescale 1ns/1ps

module testbench_enhanced;

    // Signal declarations
    wire clk;
    wire clk_ref;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // DUT instantiation
    clkgenerator uut (
        .clk(clk)
    );

    // Golden reference instantiation
    golden_clkgenerator ref_model (
        .clk(clk_ref)
    );

    // Check task
    task check_clk;
        begin
            check_id = check_id + 1;
            total_checks = total_checks + 1;
            if (clk === clk_ref) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL clk: expected=%b actual=%b at time=%0t", check_id, clk_ref, clk, $time);
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
        #1; // Small initial delay to let both modules initialize

        // ===================== Group A: Original testbench cases =====================
        // Replicate the original 20-cycle test
        for (i = 0; i < 20; i = i + 1) begin
            #5;
            check_clk;
        end

        // ===================== Group B: Boundary/corner cases =====================
        // B1: Check clock at various sub-period points
        // Check at t=0 offset within a period
        #1;
        check_clk;
        #1;
        check_clk;
        #1;
        check_clk;
        #2; // now at next half-period boundary
        check_clk;

        // B2: Check multiple full periods
        for (i = 0; i < 20; i = i + 1) begin
            #5;
            check_clk;
        end

        // ===================== Group C: Randomized stress =====================
        // Check at various time intervals
        #3; check_clk;
        #7; check_clk;
        #2; check_clk;
        #8; check_clk;
        #1; check_clk;
        #9; check_clk;
        #4; check_clk;
        #6; check_clk;
        #3; check_clk;
        #5; check_clk;
        #7; check_clk;
        #1; check_clk;
        #8; check_clk;
        #2; check_clk;
        #6; check_clk;
        #4; check_clk;
        #9; check_clk;
        #3; check_clk;
        #5; check_clk;
        #7; check_clk;

        // ===================== Group D: Protocol/timing tests =====================
        // D1: Check at exact toggle points
        // Wait until a known point; PERIOD=10, half=5
        // Check right before and after toggle edges
        #5;
        check_clk;
        #5;
        check_clk;
        #5;
        check_clk;
        #5;
        check_clk;
        #5;
        check_clk;
        #5;
        check_clk;
        #5;
        check_clk;
        #5;
        check_clk;
        #5;
        check_clk;
        #5;
        check_clk;

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
// Golden reference model - copy of verified_clkgenerator.v renamed
// ============================================================
module golden_clkgenerator (
    output reg clk
);

    parameter PERIOD = 10;

    initial begin
        clk = 0;
    end

    always begin
        # (PERIOD / 2) clk = ~clk;
    end

endmodule
