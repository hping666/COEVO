`timescale 1ns/1ps

module testbench_enhanced;

    // Signal declarations
    reg clk;
    reg rst_n;
    wire clk_div;
    wire clk_div_ref;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // DUT instantiation
    freq_divbyodd uut (
        .clk(clk),
        .rst_n(rst_n),
        .clk_div(clk_div)
    );

    // Golden reference instantiation
    golden_freq_divbyodd ref_model (
        .clk(clk),
        .rst_n(rst_n),
        .clk_div(clk_div_ref)
    );

    // Clock generation: 10ns period
    initial clk = 0;
    always #5 clk = ~clk;

    // Check task
    task check;
        input [255:0] test_name;
        begin
            check_id = check_id + 1;
            total_checks = total_checks + 1;
            if (clk_div !== clk_div_ref) begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL %0s | DUT=%b, REF=%b at time %0t", check_id, test_name, clk_div, clk_div_ref, $time);
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
        @(posedge clk); #1;
        check("A: reset state");

        @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;
        check("A: after reset release posedge 1");

        // Run for several full periods of div-by-5
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge clk); #1;
            check("A: posedge running");
        end

        for (i = 0; i < 10; i = i + 1) begin
            @(negedge clk); #1;
            check("A: negedge running");
        end

        // =============================================
        // Group B: Boundary/corner cases
        // =============================================

        // B1: Assert reset mid-operation
        rst_n = 0;
        @(posedge clk); #1;
        check("B: reset mid-operation");
        @(posedge clk); #1;
        check("B: held in reset");
        @(negedge clk); #1;
        check("B: reset at negedge");

        // B2: Release reset
        rst_n = 1;
        @(posedge clk); #1;
        check("B: release reset posedge");
        @(negedge clk); #1;
        check("B: release reset negedge");

        // B3: Run exactly one full div-by-5 cycle (5 clk posedges)
        for (i = 0; i < 5; i = i + 1) begin
            @(posedge clk); #1;
            check("B: exact one period");
        end

        // B4: Run exactly two full div-by-5 cycles
        for (i = 0; i < 10; i = i + 1) begin
            @(posedge clk); #1;
            check("B: exact two periods");
        end

        // B5: Multiple rapid reset toggles
        rst_n = 0;
        #2;
        rst_n = 1;
        @(posedge clk); #1;
        check("B: quick reset toggle 1");
        rst_n = 0;
        #3;
        rst_n = 1;
        @(posedge clk); #1;
        check("B: quick reset toggle 2");

        // B6: Reset at different phases of counter
        for (i = 0; i < 3; i = i + 1) begin
            @(posedge clk); #1;
            check("B: pre-reset phase");
        end
        rst_n = 0;
        @(posedge clk); #1;
        check("B: reset at cnt=3 phase");
        rst_n = 1;
        @(posedge clk); #1;
        check("B: recovery from mid-cnt reset");

        // =============================================
        // Group C: Randomized stress tests
        // =============================================
        rst_n = 1;
        for (i = 0; i < 30; i = i + 1) begin
            if (($random(seed) % 10) < 2) begin
                rst_n = 0;
                @(posedge clk); #1;
                check("C: random reset assert");
                rst_n = 1;
            end
            @(posedge clk); #1;
            check("C: random stress posedge");
        end

        // =============================================
        // Group D: Protocol/timing tests
        // =============================================

        // D1: Observe complete divided clock cycles after clean reset
        rst_n = 0;
        @(posedge clk); #1;
        rst_n = 1;
        // Let it run for 4 full divided periods (4 * 5 = 20 clk cycles)
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge clk); #1;
            check("D: full period observation posedge");
        end

        // D2: Check at negedge as well (important for odd divider)
        rst_n = 0;
        @(posedge clk); #1;
        rst_n = 1;
        for (i = 0; i < 10; i = i + 1) begin
            @(negedge clk); #1;
            check("D: full period observation negedge");
        end

        // D3: Long run to verify stability
        for (i = 0; i < 15; i = i + 1) begin
            @(posedge clk); #1;
            check("D: long run stability");
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
module golden_freq_divbyodd(
    clk,
    rst_n,
    clk_div
);
    input clk;
    input rst_n;
    output clk_div;

    parameter NUM_DIV = 5;
    reg[2:0] cnt1;
    reg[2:0] cnt2;
    reg    clk_div1, clk_div2;

always @(posedge clk or negedge rst_n)
    if(!rst_n)
        cnt1 <= 0;
    else if(cnt1 < NUM_DIV - 1)
        cnt1 <= cnt1 + 1'b1;
    else
        cnt1 <= 0;

always @(posedge clk or negedge rst_n)
    if(!rst_n)
        clk_div1 <= 1'b1;
    else if(cnt1 < NUM_DIV / 2)
        clk_div1 <= 1'b1;
    else
        clk_div1 <= 1'b0;

always @(negedge clk or negedge rst_n)
    if(!rst_n)
       cnt2 <= 0;
    else if(cnt2 < NUM_DIV - 1)
       cnt2 <= cnt2 + 1'b1;
    else
       cnt2 <= 0;

always @(negedge clk or negedge rst_n)
    if(!rst_n)
        clk_div2 <= 1'b1;
    else if(cnt2 < NUM_DIV / 2)
        clk_div2 <= 1'b1;
    else
        clk_div2 <= 1'b0;

    assign clk_div = clk_div1 | clk_div2;
endmodule
