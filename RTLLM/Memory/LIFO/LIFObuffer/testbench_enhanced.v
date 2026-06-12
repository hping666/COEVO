`timescale 1ns/1ps

module testbench_enhanced;

    // Signal declarations
    reg [3:0] dataIn;
    reg RW, EN, Rst, Clk;
    wire EMPTY, FULL;
    wire [3:0] dataOut;
    wire EMPTY_ref, FULL_ref;
    wire [3:0] dataOut_ref;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // DUT instantiation
    LIFObuffer uut (
        .dataIn(dataIn),
        .RW(RW),
        .EN(EN),
        .Rst(Rst),
        .Clk(Clk),
        .EMPTY(EMPTY),
        .FULL(FULL),
        .dataOut(dataOut)
    );

    // Golden reference instantiation
    golden_LIFObuffer ref_model (
        .dataIn(dataIn),
        .RW(RW),
        .EN(EN),
        .Rst(Rst),
        .Clk(Clk),
        .EMPTY(EMPTY_ref),
        .FULL(FULL_ref),
        .dataOut(dataOut_ref)
    );

    // Clock generation: 20ns period
    initial begin
        Clk = 0;
        forever #10 Clk = ~Clk;
    end

    // Check task
    task check;
        input [199:0] test_name;
        begin
            check_id = check_id + 1;
            total_checks = total_checks + 1;
            if (EMPTY === EMPTY_ref && FULL === FULL_ref &&
                (dataOut === dataOut_ref || dataOut_ref === 4'hx)) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FAIL] Check %0d: %s - DUT(E=%b,F=%b,d=%h) REF(E=%b,F=%b,d=%h) t=%0t",
                    check_id, test_name, EMPTY, FULL, dataOut, EMPTY_ref, FULL_ref, dataOut_ref, $time);
            end
        end
    endtask

    // Check flags only
    task check_flags;
        input [199:0] test_name;
        begin
            check_id = check_id + 1;
            total_checks = total_checks + 1;
            if (EMPTY === EMPTY_ref && FULL === FULL_ref) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FAIL] Check %0d: %s - DUT(E=%b,F=%b) REF(E=%b,F=%b) t=%0t",
                    check_id, test_name, EMPTY, FULL, EMPTY_ref, FULL_ref, $time);
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
        dataIn = 4'h0;
        RW = 0;
        EN = 0;
        Rst = 1;

        // Wait for a few clocks
        @(posedge Clk); #1;
        @(posedge Clk); #1;

        // Enable and reset
        EN = 1;
        Rst = 1;
        @(posedge Clk); #1;
        @(posedge Clk); #1;
        check("Init: after reset");

        Rst = 0;
        @(posedge Clk); #1;

        // =============================================
        // Group A: Original testbench cases
        // =============================================
        // Push 0, 2, 4, 6 then check FULL, pop 6, pop 4
        RW = 0;
        dataIn = 4'h0;
        @(posedge Clk); #1;
        check("A: push 0");
        dataIn = 4'h2;
        @(posedge Clk); #1;
        check("A: push 2");
        dataIn = 4'h4;
        @(posedge Clk); #1;
        check("A: push 4");
        dataIn = 4'h6;
        @(posedge Clk); #1;
        check("A: push 6");

        // Check full
        check_flags("A: should be full");

        // Pop
        RW = 1;
        @(posedge Clk); #1;
        check("A: pop expect 6");
        @(posedge Clk); #1;
        check("A: pop expect 4");

        // =============================================
        // Group B: Boundary/corner cases
        // =============================================

        // B1: Pop remaining items
        @(posedge Clk); #1;
        check("B: pop expect 2");
        @(posedge Clk); #1;
        check("B: pop expect 0");

        // B2: Empty flag check
        check_flags("B: empty after all pops");

        // B3: Pop when empty
        RW = 1;
        @(posedge Clk); #1;
        check("B: pop when empty");
        @(posedge Clk); #1;
        check("B: pop when empty 2");

        // B4: Push when full
        EN = 1; Rst = 1;
        @(posedge Clk); #1;
        Rst = 0;
        @(posedge Clk); #1;

        RW = 0;
        dataIn = 4'hA;
        @(posedge Clk); #1;
        check("B: push A");
        dataIn = 4'hB;
        @(posedge Clk); #1;
        check("B: push B");
        dataIn = 4'hC;
        @(posedge Clk); #1;
        check("B: push C");
        dataIn = 4'hD;
        @(posedge Clk); #1;
        check("B: push D (full)");

        // Try push when full
        dataIn = 4'hE;
        @(posedge Clk); #1;
        check("B: push when full");
        @(posedge Clk); #1;
        check("B: push when full 2");

        // B5: Single element push/pop
        EN = 1; Rst = 1;
        @(posedge Clk); #1;
        Rst = 0;
        @(posedge Clk); #1;

        RW = 0;
        dataIn = 4'h7;
        @(posedge Clk); #1;
        check("B: single push");
        check_flags("B: not empty after push");

        RW = 1;
        @(posedge Clk); #1;
        check("B: single pop");
        check_flags("B: empty after pop");

        // B6: Reset while non-empty
        EN = 1; Rst = 1;
        @(posedge Clk); #1;
        Rst = 0;
        @(posedge Clk); #1;

        RW = 0;
        dataIn = 4'h3;
        @(posedge Clk); #1;
        check("B: push before reset");
        dataIn = 4'h5;
        @(posedge Clk); #1;
        check("B: push before reset 2");

        // Reset while non-empty
        Rst = 1;
        @(posedge Clk); #1;
        check("B: reset while non-empty");

        Rst = 0;
        @(posedge Clk); #1;
        check_flags("B: empty after mid-reset");

        // B7: Fill then drain completely
        EN = 1; Rst = 1;
        @(posedge Clk); #1;
        Rst = 0;
        @(posedge Clk); #1;

        RW = 0;
        for (i = 0; i < 4; i = i + 1) begin
            dataIn = i[3:0] + 4'h1;
            @(posedge Clk); #1;
            check("B: fill");
        end

        RW = 1;
        for (i = 0; i < 4; i = i + 1) begin
            @(posedge Clk); #1;
            check("B: drain");
        end
        check_flags("B: empty after drain");

        // B8: EN=0 should do nothing
        EN = 1; Rst = 1;
        @(posedge Clk); #1;
        Rst = 0;
        @(posedge Clk); #1;

        RW = 0;
        dataIn = 4'h9;
        @(posedge Clk); #1;
        check("B: push with EN=1");

        EN = 0;
        dataIn = 4'hF;
        @(posedge Clk); #1;
        check("B: push with EN=0 no-op");
        @(posedge Clk); #1;
        check("B: EN=0 still no-op");

        EN = 1;
        RW = 1;
        @(posedge Clk); #1;
        check("B: pop after EN=0");

        // B9: All-ones and all-zeros data
        EN = 1; Rst = 1;
        @(posedge Clk); #1;
        Rst = 0;
        @(posedge Clk); #1;

        RW = 0;
        dataIn = 4'hF;
        @(posedge Clk); #1;
        check("B: push all-ones");
        dataIn = 4'h0;
        @(posedge Clk); #1;
        check("B: push all-zeros");

        RW = 1;
        @(posedge Clk); #1;
        check("B: pop all-zeros");
        @(posedge Clk); #1;
        check("B: pop all-ones");

        // =============================================
        // Group C: Randomized stress tests
        // =============================================
        EN = 1; Rst = 1;
        @(posedge Clk); #1;
        Rst = 0;
        @(posedge Clk); #1;

        for (i = 0; i < 40; i = i + 1) begin
            RW = $random(seed) % 2;
            dataIn = $random(seed);
            @(posedge Clk); #1;
            check("C: random");
        end

        // =============================================
        // Group D: Protocol/timing tests
        // =============================================

        // D1: Reset during operation
        EN = 1; Rst = 1;
        @(posedge Clk); #1;
        Rst = 0;
        @(posedge Clk); #1;

        RW = 0;
        dataIn = 4'hA;
        @(posedge Clk); #1;
        check("D: push A");
        dataIn = 4'hB;
        @(posedge Clk); #1;
        check("D: push B");

        Rst = 1;
        @(posedge Clk); #1;
        check("D: reset mid-op");
        Rst = 0;
        @(posedge Clk); #1;
        check("D: after mid-reset");

        // D2: Back-to-back push/pop
        RW = 0;
        dataIn = 4'h1;
        @(posedge Clk); #1;
        check("D: bb push 1");
        RW = 1;
        @(posedge Clk); #1;
        check("D: bb pop 1");
        RW = 0;
        dataIn = 4'h2;
        @(posedge Clk); #1;
        check("D: bb push 2");
        RW = 1;
        @(posedge Clk); #1;
        check("D: bb pop 2");

        // D3: Fill, pop one, push one, drain
        EN = 1; Rst = 1;
        @(posedge Clk); #1;
        Rst = 0;
        @(posedge Clk); #1;

        RW = 0;
        for (i = 0; i < 4; i = i + 1) begin
            dataIn = i[3:0] + 4'h5;
            @(posedge Clk); #1;
            check("D: fill");
        end

        RW = 1;
        @(posedge Clk); #1;
        check("D: pop one from full");

        RW = 0;
        dataIn = 4'hE;
        @(posedge Clk); #1;
        check("D: push after pop");

        RW = 1;
        for (i = 0; i < 4; i = i + 1) begin
            @(posedge Clk); #1;
            check("D: drain all");
        end

        // D4: Multiple resets
        for (i = 0; i < 3; i = i + 1) begin
            Rst = 1;
            @(posedge Clk); #1;
            check("D: multi-reset");
            Rst = 0;
            @(posedge Clk); #1;
            check("D: after multi-reset");
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
module golden_LIFObuffer (
    input [3:0] dataIn,
    input RW,
    input EN,
    input Rst,
    input Clk,
    output reg EMPTY,
    output reg FULL,
    output reg [3:0] dataOut
);

    reg [3:0] stack_mem[0:3];
    reg [2:0] SP;
    integer i;

    always @(posedge Clk) begin
        if (EN == 0) begin
            // Do nothing if EN is 0
        end else begin
            if (Rst == 1) begin
                SP = 3'd4;
                EMPTY = SP[2];
                FULL = 0;
                dataOut = 4'h0;
                for (i = 0; i < 4; i = i + 1) begin
                    stack_mem[i] = 0;
                end
            end else if (Rst == 0) begin
                FULL = SP ? 0 : 1;
                EMPTY = SP[2];
                dataOut = 4'hx;

                if (FULL == 1'b0 && RW == 1'b0) begin
                    SP = SP - 1'b1;
                    FULL = SP ? 0 : 1;
                    EMPTY = SP[2];
                    stack_mem[SP] = dataIn;
                end else if (EMPTY == 1'b0 && RW == 1'b1) begin
                    dataOut = stack_mem[SP];
                    stack_mem[SP] = 0;
                    SP = SP + 1;
                    FULL = SP ? 0 : 1;
                    EMPTY = SP[2];
                end else begin
                    // Do nothing if neither condition is met
                end
            end else begin
                // Do nothing if neither condition is met
            end
        end
    end
endmodule
