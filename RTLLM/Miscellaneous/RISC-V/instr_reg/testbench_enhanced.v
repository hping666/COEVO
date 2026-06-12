`timescale 1ns/1ps

module testbench_enhanced;

    // Signal declarations
    reg clk;
    reg rst;
    reg [1:0] fetch;
    reg [7:0] data;

    // DUT outputs
    wire [2:0] ins;
    wire [4:0] ad1;
    wire [7:0] ad2;

    // Golden reference outputs
    wire [2:0] ins_ref;
    wire [4:0] ad1_ref;
    wire [7:0] ad2_ref;

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
    instr_reg uut (
        .clk(clk), .rst(rst), .fetch(fetch), .data(data),
        .ins(ins), .ad1(ad1), .ad2(ad2)
    );

    // Golden reference instantiation
    golden_instr_reg ref_model (
        .clk(clk), .rst(rst), .fetch(fetch), .data(data),
        .ins(ins_ref), .ad1(ad1_ref), .ad2(ad2_ref)
    );

    // Check task
    task check_outputs;
        begin
            check_id = check_id + 1;

            // Check ins
            total_checks = total_checks + 1;
            if (ins === ins_ref) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL ins: expected=%b actual=%b (fetch=%b data=%h)", check_id, ins_ref, ins, fetch, data);
            end

            // Check ad1
            total_checks = total_checks + 1;
            if (ad1 === ad1_ref) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL ad1: expected=%b actual=%b (fetch=%b data=%h)", check_id, ad1_ref, ad1, fetch, data);
            end

            // Check ad2
            total_checks = total_checks + 1;
            if (ad2 === ad2_ref) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL ad2: expected=%h actual=%h (fetch=%b data=%h)", check_id, ad2_ref, ad2, fetch, data);
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
        rst = 0;
        fetch = 2'b00;
        data = 8'h00;

        // ===================== Group A: Original testbench cases =====================
        // Hold reset for some clocks
        #100;
        @(posedge clk); #1;
        check_outputs; // Check reset state

        // De-assert reset
        rst = 1;
        #10;

        // Fetch operation 1 from register
        fetch = 2'b01;
        data = 8'b01011100;
        @(posedge clk); #1;
        check_outputs;
        @(posedge clk); #1;
        check_outputs;

        // ===================== Group B: Boundary/corner cases =====================

        // B1: Reset behavior
        rst = 0;
        @(posedge clk); #1;
        check_outputs; // Should be all zeros after reset
        @(posedge clk); #1;
        check_outputs;

        rst = 1;
        @(posedge clk); #1;
        check_outputs;

        // B2: Load ins_p1 with all 1s
        fetch = 2'b01;
        data = 8'hFF;
        @(posedge clk); #1;
        check_outputs;

        // B3: Load ins_p2 with all 1s
        fetch = 2'b10;
        data = 8'hFF;
        @(posedge clk); #1;
        check_outputs;

        // B4: Load ins_p1 with all 0s
        fetch = 2'b01;
        data = 8'h00;
        @(posedge clk); #1;
        check_outputs;

        // B5: Load ins_p2 with all 0s
        fetch = 2'b10;
        data = 8'h00;
        @(posedge clk); #1;
        check_outputs;

        // B6: No fetch - retain values
        fetch = 2'b00;
        data = 8'hAB;
        @(posedge clk); #1;
        check_outputs;
        @(posedge clk); #1;
        check_outputs;

        // B7: Fetch with 2'b11 (invalid) - retain values
        fetch = 2'b11;
        data = 8'hCD;
        @(posedge clk); #1;
        check_outputs;

        // B8: Alternating fetches
        fetch = 2'b01;
        data = 8'hA5;
        @(posedge clk); #1;
        check_outputs;

        fetch = 2'b10;
        data = 8'h5A;
        @(posedge clk); #1;
        check_outputs;

        // B9: Load specific patterns to test field extraction
        fetch = 2'b01;
        data = 8'b11100000; // ins=111, ad1=00000
        @(posedge clk); #1;
        check_outputs;

        fetch = 2'b01;
        data = 8'b00011111; // ins=000, ad1=11111
        @(posedge clk); #1;
        check_outputs;

        // B10: Reset during active operation
        fetch = 2'b01;
        data = 8'hBB;
        @(posedge clk); #1;
        check_outputs;
        rst = 0;
        @(posedge clk); #1;
        check_outputs;
        rst = 1;
        @(posedge clk); #1;
        check_outputs;

        // ===================== Group C: Randomized stress =====================
        for (i = 0; i < 20; i = i + 1) begin
            fetch = $random(seed) % 4;
            data = $random(seed);
            @(posedge clk); #1;
            check_outputs;
        end

        // Random with occasional resets
        for (i = 0; i < 10; i = i + 1) begin
            if (i % 5 == 0) begin
                rst = 0;
                @(posedge clk); #1;
                check_outputs;
                rst = 1;
            end
            fetch = $random(seed) % 4;
            data = $random(seed);
            @(posedge clk); #1;
            check_outputs;
        end

        // ===================== Group D: Protocol/timing tests =====================

        // D1: Back-to-back fetch to same register
        rst = 1;
        fetch = 2'b01;
        data = 8'h11;
        @(posedge clk); #1;
        check_outputs;
        data = 8'h22;
        @(posedge clk); #1;
        check_outputs;
        data = 8'h33;
        @(posedge clk); #1;
        check_outputs;

        // D2: Back-to-back fetch to other register
        fetch = 2'b10;
        data = 8'h44;
        @(posedge clk); #1;
        check_outputs;
        data = 8'h55;
        @(posedge clk); #1;
        check_outputs;

        // D3: Rapid alternation between fetch modes
        fetch = 2'b01; data = 8'hAA;
        @(posedge clk); #1; check_outputs;
        fetch = 2'b10; data = 8'hBB;
        @(posedge clk); #1; check_outputs;
        fetch = 2'b01; data = 8'hCC;
        @(posedge clk); #1; check_outputs;
        fetch = 2'b10; data = 8'hDD;
        @(posedge clk); #1; check_outputs;
        fetch = 2'b00; data = 8'hEE;
        @(posedge clk); #1; check_outputs;

        // D4: Async reset test (negedge rst)
        rst = 0; #1;
        check_outputs;
        #4;
        rst = 1;
        @(posedge clk); #1;
        check_outputs;

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
// Golden reference model - copy of verified_instr_reg.v renamed
// ============================================================
module golden_instr_reg (
    input clk,
    input rst,
    input [1:0] fetch,
    input [7:0] data,
    output [2:0] ins,
    output [4:0] ad1,
    output [7:0] ad2
);

    reg [7:0] ins_p1, ins_p2;
    reg [2:0] state;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            ins_p1 <= 8'd0;
            ins_p2 <= 8'd0;
        end else begin
            if (fetch == 2'b01) begin
                ins_p1 <= data;
                ins_p2 <= ins_p2;
            end else if (fetch == 2'b10) begin
                ins_p1 <= ins_p1;
                ins_p2 <= data;
            end else begin
                ins_p1 <= ins_p1;
                ins_p2 <= ins_p2;
            end
        end
    end

    assign ins = ins_p1[7:5];
    assign ad1 = ins_p1[4:0];
    assign ad2 = ins_p2;
endmodule
