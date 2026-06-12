`timescale 1ns/1ps

module testbench_enhanced;

    // SECTION 1: Signal declarations
    reg clk;
    reg rst;
    reg [7:0] dividend;
    reg [7:0] divisor;
    reg sign;
    reg opn_valid;
    reg res_ready;

    wire dut_res_valid;
    wire [15:0] dut_result;
    wire ref_res_valid;
    wire [15:0] ref_result;

    // SECTION 2: Clock generation
    initial clk = 0;
    always #5 clk = ~clk;

    // SECTION 3: Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;
    integer timeout_cnt;

    // SECTION 4: DUT instantiation
    radix2_div uut (
        .clk(clk),
        .rst(rst),
        .dividend(dividend),
        .divisor(divisor),
        .sign(sign),
        .opn_valid(opn_valid),
        .res_valid(dut_res_valid),
        .res_ready(res_ready),
        .result(dut_result)
    );

    // SECTION 5: Golden reference instantiation
    golden_radix2_div ref_model (
        .clk(clk),
        .rst(rst),
        .dividend(dividend),
        .divisor(divisor),
        .sign(sign),
        .opn_valid(opn_valid),
        .res_valid(ref_res_valid),
        .res_ready(res_ready),
        .result(ref_result)
    );

    // SECTION 6: Check task
    task check_outputs;
        input [255:0] description;
        begin
            check_id = check_id + 1;
            total_checks = total_checks + 1;
            if (dut_result !== ref_result || dut_res_valid !== ref_res_valid) begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL | %0s | expected result=%h res_valid=%b got result=%h res_valid=%b | time=%0t",
                    check_id, description, ref_result, ref_res_valid, dut_result, dut_res_valid, $time);
            end else begin
                passed_checks = passed_checks + 1;
            end
        end
    endtask

    // Task to perform a division and check
    task do_division;
        input [7:0] a;
        input [7:0] b;
        input s;
        input [255:0] description;
        begin
            // Set inputs
            @(posedge clk); #1;
            dividend = a;
            divisor = b;
            sign = s;
            opn_valid = 1'b1;
            @(posedge clk); #1;
            opn_valid = 1'b0;

            // Wait for GOLDEN res_valid, check every cycle
            timeout_cnt = 0;
            while (ref_res_valid !== 1'b1 && timeout_cnt < 20) begin
                @(posedge clk); #1;
                timeout_cnt = timeout_cnt + 1;
                // Per-cycle: catches DUT asserting res_valid at wrong time
                check_outputs(description);
            end

            // Final check when golden says result is valid
            check_outputs(description);

            // Consume result
            res_ready = 1'b1;
            @(posedge clk); #1;
            res_ready = 1'b1;
            @(posedge clk); #1;
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
        // Initialize
        rst = 1;
        opn_valid = 0;
        res_ready = 1;
        dividend = 0;
        divisor = 0;
        sign = 0;

        // Reset
        @(posedge clk); #1;
        @(posedge clk); #1;
        @(posedge clk); #1;
        rst = 0;
        @(posedge clk); #1;

        // =============================================
        // Group A: Original testbench cases
        // =============================================
        do_division(8'd100, 8'd10, 0, "GroupA: 100/10 unsigned");
        do_division(-8'd100, 8'd10, 1, "GroupA: -100/10 signed");
        do_division(8'd100, -8'd10, 1, "GroupA: 100/-10 signed");
        do_division(-8'd100, -8'd10, 1, "GroupA: -100/-10 signed");
        do_division(8'd123, 8'd123, 0, "GroupA: 123/123 unsigned");

        // =============================================
        // Group B: Boundary/corner cases
        // =============================================
        // Zero dividend
        do_division(8'd0, 8'd1, 0, "GroupB: 0/1 unsigned");
        do_division(8'd0, 8'd255, 0, "GroupB: 0/255 unsigned");
        do_division(8'd0, 8'd127, 1, "GroupB: 0/127 signed");

        // Dividend = 1
        do_division(8'd1, 8'd1, 0, "GroupB: 1/1 unsigned");
        do_division(8'd1, 8'd2, 0, "GroupB: 1/2 unsigned");
        do_division(8'd1, 8'd255, 0, "GroupB: 1/255 unsigned");

        // Max unsigned values
        do_division(8'd255, 8'd1, 0, "GroupB: 255/1 unsigned");
        do_division(8'd255, 8'd255, 0, "GroupB: 255/255 unsigned");
        do_division(8'd255, 8'd7, 0, "GroupB: 255/7 unsigned");
        do_division(8'd255, 8'd128, 0, "GroupB: 255/128 unsigned");

        // Signed boundary values
        do_division(8'h80, 8'd1, 1, "GroupB: -128/1 signed");
        do_division(8'h7F, 8'd1, 1, "GroupB: 127/1 signed");
        do_division(8'h80, 8'hFF, 1, "GroupB: -128/-1 signed");
        do_division(8'hFF, 8'h7F, 1, "GroupB: -1/127 signed");

        // Dividend < Divisor
        do_division(8'd5, 8'd10, 0, "GroupB: 5/10 unsigned");
        do_division(8'd1, 8'd100, 0, "GroupB: 1/100 unsigned");

        // Exact division
        do_division(8'd100, 8'd25, 0, "GroupB: 100/25 exact unsigned");
        do_division(8'd200, 8'd50, 0, "GroupB: 200/50 exact unsigned");
        do_division(8'd128, 8'd64, 0, "GroupB: 128/64 exact unsigned");

        // Powers of 2
        do_division(8'd128, 8'd2, 0, "GroupB: 128/2 unsigned");
        do_division(8'd64, 8'd4, 0, "GroupB: 64/4 unsigned");
        do_division(8'd32, 8'd8, 0, "GroupB: 32/8 unsigned");

        // =============================================
        // Group C: Randomized stress tests
        // =============================================
        for (i = 0; i < 30; i = i + 1) begin
            do_division(
                $random(seed),
                ($random(seed) % 255) + 1,
                0,
                "GroupC: random unsigned"
            );
        end

        for (i = 0; i < 20; i = i + 1) begin
            do_division(
                $random(seed),
                ($random(seed) % 127) + 1,
                1,
                "GroupC: random signed"
            );
        end

        // =============================================
        // Group D: Protocol/timing tests
        // =============================================

        // D1: Back-to-back operations
        do_division(8'd50, 8'd7, 0, "GroupD: back-to-back 1");
        do_division(8'd99, 8'd11, 0, "GroupD: back-to-back 2");
        do_division(8'd200, 8'd13, 0, "GroupD: back-to-back 3");

        // D2: Reset during operation
        @(posedge clk); #1;
        dividend = 8'd100;
        divisor = 8'd10;
        sign = 0;
        opn_valid = 1'b1;
        @(posedge clk); #1;
        opn_valid = 1'b0;
        @(posedge clk); #1;
        @(posedge clk); #1;
        // Assert reset mid-operation
        rst = 1;
        @(posedge clk); #1;
        @(posedge clk); #1;
        rst = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;
        check_outputs("GroupD: after mid-op reset");

        // D3: Normal op after reset recovery
        do_division(8'd77, 8'd7, 0, "GroupD: post-reset recovery");

        // D4: res_ready delayed
        @(posedge clk); #1;
        dividend = 8'd60;
        divisor = 8'd7;
        sign = 0;
        opn_valid = 1'b1;
        res_ready = 1'b0;
        @(posedge clk); #1;
        opn_valid = 1'b0;
        // Wait for res_valid
        timeout_cnt = 0;
        while (ref_res_valid !== 1'b1 && timeout_cnt < 20) begin
            @(posedge clk); #1;
            timeout_cnt = timeout_cnt + 1;
            check_outputs("GroupD: res_ready delayed - wait");
        end
        // Final check when golden says result is valid
        check_outputs("GroupD: res_ready delayed - valid");
        // Now assert res_ready
        @(posedge clk); #1;
        res_ready = 1'b1;
        @(posedge clk); #1;
        @(posedge clk); #1;

        // D5: Normal op after delayed ready
        do_division(8'd33, 8'd5, 0, "GroupD: after delayed ready");

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
`timescale 1ns/1ps
module golden_radix2_div(
    input wire clk,
    input wire rst,
    input wire [7:0] dividend,
    input wire [7:0] divisor,
    input wire sign,

    input wire opn_valid,
    output reg res_valid,
    input wire res_ready,
    output wire [15:0] result
);

    reg [7:0] dividend_save, divisor_save;
    reg [15:0] SR;
    reg [8:0] NEG_DIVISOR;

    wire [7:0] REMAINER = SR[15:8];
    wire [7:0] QUOTIENT = SR[7:0];
    wire [7:0] remainer = (sign & dividend_save[7]) ? ((~REMAINER) + 8'd1) : REMAINER;
    wire [7:0] quotient = (sign & (dividend_save[7] ^ divisor_save[7])) ? ((~QUOTIENT) + 8'd1) : QUOTIENT;
    assign result = {remainer, quotient};

    wire CO;
    wire [8:0] sub_result;
    assign {CO, sub_result} = {1'b0, REMAINER} + NEG_DIVISOR;
    wire [8:0] mux_result = CO ? sub_result : {1'b0, REMAINER};

    reg [3:0] cnt;
    reg start_cnt;
    reg [7:0] dividend_abs_reg;
    reg [8:0] neg_divisor_reg;

    always @(*) begin
        if (sign & dividend[7])
            dividend_abs_reg = (~dividend) + 8'd1;
        else
            dividend_abs_reg = dividend;
    end

    always @(*) begin
        if (sign & divisor[7])
            neg_divisor_reg = {1'b1, divisor};
        else
            neg_divisor_reg = (~{1'b0, divisor}) + 9'd1;
    end

    always @(posedge clk) begin
        if (rst) begin
            SR <= 16'b0;
            dividend_save <= 8'b0;
            divisor_save <= 8'b0;
            cnt <= 4'b0;
            start_cnt <= 1'b0;
            NEG_DIVISOR <= 9'b0;
        end
        else if (~start_cnt & opn_valid & ~res_valid) begin
            cnt <= 4'd1;
            start_cnt <= 1'b1;
            dividend_save <= dividend;
            divisor_save <= divisor;
            SR <= {7'b0, dividend_abs_reg, 1'b0};
            NEG_DIVISOR <= neg_divisor_reg;
        end
        else if (start_cnt) begin
            if (cnt[3]) begin
                cnt <= 4'b0;
                start_cnt <= 1'b0;
                SR[15:8] <= mux_result[7:0];
                SR[0] <= CO;
            end
            else begin
                cnt <= cnt + 4'd1;
                SR <= {mux_result[6:0], SR[7:1], CO, 1'b0};
            end
        end
    end

    wire data_go = res_valid & res_ready;
    always @(posedge clk) begin
        res_valid <= rst ? 1'b0 : cnt[3] ? 1'b1 : data_go ? 1'b0 : res_valid;
    end
endmodule
