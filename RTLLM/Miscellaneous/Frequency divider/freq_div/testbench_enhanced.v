`timescale 1ns/1ps

module testbench_enhanced;

    // Signal declarations
    reg CLK_in;
    reg RST;
    wire CLK_50, CLK_10, CLK_1;
    wire ref_CLK_50, ref_CLK_10, ref_CLK_1;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // DUT instantiation
    freq_div uut (
        .CLK_in(CLK_in),
        .RST(RST),
        .CLK_50(CLK_50),
        .CLK_10(CLK_10),
        .CLK_1(CLK_1)
    );

    // Golden reference instantiation
    golden_freq_div ref_model (
        .CLK_in(CLK_in),
        .RST(RST),
        .CLK_50(ref_CLK_50),
        .CLK_10(ref_CLK_10),
        .CLK_1(ref_CLK_1)
    );

    // Clock generation: 10ns period (100MHz)
    initial CLK_in = 0;
    always #5 CLK_in = ~CLK_in;

    // Check task - checks all three outputs
    task check;
        input [255:0] description;
        begin
            total_checks = total_checks + 1;
            check_id = check_id + 1;
            if (CLK_50 === ref_CLK_50 && CLK_10 === ref_CLK_10 && CLK_1 === ref_CLK_1) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL | %0s | expected=%b%b%b got=%b%b%b | time=%0t",
                    check_id, description, ref_CLK_50, ref_CLK_10, ref_CLK_1, CLK_50, CLK_10, CLK_1, $time);
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
        RST = 0;
        #10;
        RST = 1;
        #35;
        RST = 0;
        // At time 45
        #1;
        check("GroupA: After reset release");

        // At time 55
        @(posedge CLK_in); #1;
        check("GroupA: t=55 check");

        // Run to ~95
        for (i = 0; i < 4; i = i + 1) begin
            @(posedge CLK_in); #1;
            check("GroupA: Run to t=95");
        end

        // Run many more cycles (to t~225)
        for (i = 0; i < 13; i = i + 1) begin
            @(posedge CLK_in); #1;
            check("GroupA: Run to t=225");
        end

        // Run to t~625
        for (i = 0; i < 40; i = i + 1) begin
            @(posedge CLK_in); #1;
            check("GroupA: Run to t=625");
        end

        // Run to t~1035
        for (i = 0; i < 41; i = i + 1) begin
            @(posedge CLK_in); #1;
            check("GroupA: Run to t=1035");
        end

        // =============================================
        // Group B: Boundary/corner cases
        // =============================================

        // B1: Reset behavior
        RST = 1;
        @(posedge CLK_in); #1;
        check("GroupB: Reset asserted");
        @(posedge CLK_in); #1;
        check("GroupB: Reset held");
        @(posedge CLK_in); #1;
        check("GroupB: Reset still held");

        RST = 0;
        @(posedge CLK_in); #1;
        check("GroupB: Reset released");

        // B2: Verify CLK_50 toggles every clock
        for (i = 0; i < 10; i = i + 1) begin
            @(posedge CLK_in); #1;
            check("GroupB: CLK_50 toggle verify");
        end

        // B3: Verify CLK_10 period (toggles every 5 input clocks)
        // Run for 20 input clocks to see CLK_10 toggle 4 times
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge CLK_in); #1;
            check("GroupB: CLK_10 period verify");
        end

        // B4: Run long enough to verify CLK_1 (toggles every 50 input clocks)
        for (i = 0; i < 100; i = i + 1) begin
            @(posedge CLK_in); #1;
            check("GroupB: CLK_1 period verify");
        end

        // =============================================
        // Group C: Randomized stress tests
        // =============================================
        // Random reset insertions during operation
        RST = 1;
        @(posedge CLK_in); #1;
        check("GroupC: Initial reset");
        RST = 0;

        for (i = 0; i < 50; i = i + 1) begin
            if (($random(seed) % 20) == 0) begin
                RST = 1;
                @(posedge CLK_in); #1;
                check("GroupC: Random reset asserted");
                RST = 0;
            end
            @(posedge CLK_in); #1;
            check("GroupC: Random cycle");
        end

        // =============================================
        // Group D: Protocol/timing tests
        // =============================================

        // D1: Reset during operation
        RST = 1;
        @(posedge CLK_in); #1;
        check("GroupD: Reset for protocol test");
        RST = 0;

        for (i = 0; i < 10; i = i + 1) begin
            @(posedge CLK_in); #1;
            check("GroupD: Pre-reset run");
        end

        RST = 1;
        @(posedge CLK_in); #1;
        check("GroupD: Mid-operation reset");
        RST = 0;

        for (i = 0; i < 10; i = i + 1) begin
            @(posedge CLK_in); #1;
            check("GroupD: Post-reset run");
        end

        // D2: Multiple rapid resets
        for (i = 0; i < 5; i = i + 1) begin
            RST = 1;
            @(posedge CLK_in); #1;
            check("GroupD: Rapid reset on");
            RST = 0;
            @(posedge CLK_in); #1;
            check("GroupD: Rapid reset off");
        end

        // D3: Long continuous run
        RST = 1;
        @(posedge CLK_in); #1;
        RST = 0;
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge CLK_in); #1;
            check("GroupD: Long continuous run");
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
module golden_freq_div (CLK_in, CLK_50, CLK_10, CLK_1, RST);
input CLK_in, RST;
output reg CLK_50, CLK_10, CLK_1;

reg [3:0] cnt_10;
reg [6:0] cnt_100;

always @(posedge CLK_in or posedge RST) begin
    if (RST) begin
        CLK_50 <= 1'b0;
    end
    else begin
        CLK_50 <= ~CLK_50;
    end
end

always @(posedge CLK_in or posedge RST) begin
    if (RST) begin
        CLK_10 <= 1'b0;
        cnt_10 <= 0;
    end
    else if (cnt_10 == 4) begin
        CLK_10 <= ~CLK_10;
        cnt_10 <= 0;
    end
    else begin
        cnt_10 <= cnt_10 + 1;
    end
end

always @(posedge CLK_in or posedge RST) begin
    if (RST) begin
        CLK_1 <= 1'b0;
        cnt_100 <= 0;
    end
    else if (cnt_100 == 49) begin
        CLK_1 <= ~CLK_1;
        cnt_100 <= 0;
    end
    else begin
        cnt_100 <= cnt_100 + 1;
    end
end

endmodule
