`timescale 1ns/1ps

module testbench_enhanced;

    // Signal declarations
    reg clk;
    reg rst_n;
    wire clk_div;
    wire ref_clk_div;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // DUT instantiation
    freq_divbyeven uut (
        .clk(clk),
        .rst_n(rst_n),
        .clk_div(clk_div)
    );

    // Golden reference instantiation
    golden_freq_divbyeven ref_model (
        .clk(clk),
        .rst_n(rst_n),
        .clk_div(ref_clk_div)
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
            if (clk_div === ref_clk_div) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL | %0s | expected=%b got=%b | time=%0t", check_id, description, ref_clk_div, clk_div, $time);
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
        // Mimic original: clk=1 start, rst_n=0, then release after 10ns
        rst_n = 0;
        @(posedge clk); #1;
        check("GroupA: In reset");

        rst_n = 1;
        @(posedge clk); #1;
        check("GroupA: Reset released");

        // Run for 10 clock cycles (matching original ~100ns)
        for (i = 0; i < 10; i = i + 1) begin
            @(posedge clk); #1;
            check("GroupA: Running cycle");
        end

        // =============================================
        // Group B: Boundary/corner cases
        // =============================================

        // B1: Reset initializes outputs to 0
        rst_n = 0;
        @(posedge clk); #1;
        check("GroupB: Reset assert");
        @(posedge clk); #1;
        check("GroupB: Reset held 1");
        @(posedge clk); #1;
        check("GroupB: Reset held 2");

        // B2: Release and verify frequency division by 6
        // NUM_DIV=6, so clk_div toggles every 3 input clocks
        rst_n = 1;
        for (i = 0; i < 24; i = i + 1) begin
            @(posedge clk); #1;
            check("GroupB: Freq div by 6 verify");
        end

        // B3: Immediate re-reset after one cycle
        rst_n = 0;
        @(posedge clk); #1;
        check("GroupB: Quick reset");
        rst_n = 1;
        @(posedge clk); #1;
        check("GroupB: Quick release");

        // B4: Run for multiple full periods
        for (i = 0; i < 18; i = i + 1) begin
            @(posedge clk); #1;
            check("GroupB: Multiple periods");
        end

        // =============================================
        // Group C: Randomized stress tests
        // =============================================
        rst_n = 0;
        @(posedge clk); #1;
        check("GroupC: Reset for random");
        rst_n = 1;

        for (i = 0; i < 30; i = i + 1) begin
            if (($random(seed) % 15) == 0) begin
                rst_n = 0;
                @(posedge clk); #1;
                check("GroupC: Random reset assert");
                rst_n = 1;
            end
            @(posedge clk); #1;
            check("GroupC: Random cycle");
        end

        // =============================================
        // Group D: Protocol/timing tests
        // =============================================

        // D1: Reset during operation
        rst_n = 0;
        @(posedge clk); #1;
        check("GroupD: Protocol reset");
        rst_n = 1;

        for (i = 0; i < 5; i = i + 1) begin
            @(posedge clk); #1;
            check("GroupD: Pre-mid-reset run");
        end

        rst_n = 0;
        @(posedge clk); #1;
        check("GroupD: Mid-operation reset");
        rst_n = 1;

        for (i = 0; i < 5; i = i + 1) begin
            @(posedge clk); #1;
            check("GroupD: Post-mid-reset run");
        end

        // D2: Multiple rapid resets
        for (i = 0; i < 5; i = i + 1) begin
            rst_n = 0;
            @(posedge clk); #1;
            check("GroupD: Rapid reset on");
            rst_n = 1;
            @(posedge clk); #1;
            check("GroupD: Rapid reset off");
        end

        // D3: Long run after resets
        rst_n = 0;
        @(posedge clk); #1;
        rst_n = 1;
        for (i = 0; i < 12; i = i + 1) begin
            @(posedge clk); #1;
            check("GroupD: Long run after resets");
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
module golden_freq_divbyeven(
    clk,
    rst_n,
    clk_div
);
    input clk;
    input rst_n;
    output clk_div;
    reg clk_div;

    parameter NUM_DIV = 6;
    reg    [3:0] cnt;

always @(posedge clk or negedge rst_n)
    if(!rst_n) begin
        cnt     <= 4'd0;
        clk_div    <= 1'b0;
    end
    else if(cnt < NUM_DIV / 2 - 1) begin
        cnt     <= cnt + 1'b1;
        clk_div    <= clk_div;
    end
    else begin
        cnt     <= 4'd0;
        clk_div    <= ~clk_div;
    end
endmodule
