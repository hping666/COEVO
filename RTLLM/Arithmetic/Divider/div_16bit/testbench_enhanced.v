`timescale 1ns/1ps

module testbench_enhanced;

    // SECTION 1: Signal declarations
    reg [15:0] A;
    reg [7:0] B;

    wire [15:0] dut_result, dut_odd;
    wire [15:0] ref_result, ref_odd;

    // SECTION 3: Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // SECTION 4: DUT instantiation
    div_16bit uut (
        .A(A),
        .B(B),
        .result(dut_result),
        .odd(dut_odd)
    );

    // SECTION 5: Golden reference instantiation
    golden_div_16bit ref_model (
        .A(A),
        .B(B),
        .result(ref_result),
        .odd(ref_odd)
    );

    // SECTION 6: Check task
    task check_outputs;
        input [255:0] description;
        begin
            check_id = check_id + 1;
            total_checks = total_checks + 1;
            if (dut_result !== ref_result || dut_odd !== ref_odd) begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL | %0s | A=%0d B=%0d | expected result=%0d odd=%0d got result=%0d odd=%0d | time=%0t",
                    check_id, description, A, B,
                    ref_result, ref_odd, dut_result, dut_odd, $time);
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
        A = 0; B = 1;
        #1;

        // =============================================
        // Group A: Original testbench-style cases
        // =============================================
        A = 16'd100; B = 8'd10; #1; check_outputs("GroupA: 100/10");
        A = 16'd255; B = 8'd16; #1; check_outputs("GroupA: 255/16");
        A = 16'd1000; B = 8'd33; #1; check_outputs("GroupA: 1000/33");
        A = 16'd65535; B = 8'd255; #1; check_outputs("GroupA: max/255");
        A = 16'd12345; B = 8'd123; #1; check_outputs("GroupA: 12345/123");

        // =============================================
        // Group B: Boundary/corner cases
        // =============================================
        // Dividend = 0
        A = 16'd0; B = 8'd1; #1; check_outputs("GroupB: 0/1");
        A = 16'd0; B = 8'd255; #1; check_outputs("GroupB: 0/255");
        A = 16'd0; B = 8'd128; #1; check_outputs("GroupB: 0/128");

        // Divisor = 1
        A = 16'd1; B = 8'd1; #1; check_outputs("GroupB: 1/1");
        A = 16'd65535; B = 8'd1; #1; check_outputs("GroupB: 65535/1");
        A = 16'd32768; B = 8'd1; #1; check_outputs("GroupB: 32768/1");

        // Dividend < Divisor
        A = 16'd1; B = 8'd2; #1; check_outputs("GroupB: 1/2");
        A = 16'd5; B = 8'd10; #1; check_outputs("GroupB: 5/10");
        A = 16'd127; B = 8'd255; #1; check_outputs("GroupB: 127/255");
        A = 16'd254; B = 8'd255; #1; check_outputs("GroupB: 254/255");

        // Dividend == Divisor
        A = 16'd1; B = 8'd1; #1; check_outputs("GroupB: 1==1");
        A = 16'd255; B = 8'd255; #1; check_outputs("GroupB: 255==255");
        A = 16'd100; B = 8'd100; #1; check_outputs("GroupB: 100==100");

        // Exact division (no remainder)
        A = 16'd256; B = 8'd2; #1; check_outputs("GroupB: 256/2 exact");
        A = 16'd1000; B = 8'd8; #1; check_outputs("GroupB: 1000/8");
        A = 16'd65280; B = 8'd255; #1; check_outputs("GroupB: 65280/255 exact");

        // Max values
        A = 16'hFFFF; B = 8'hFF; #1; check_outputs("GroupB: 0xFFFF/0xFF");
        A = 16'hFFFF; B = 8'd1; #1; check_outputs("GroupB: 0xFFFF/1");
        A = 16'hFFFF; B = 8'd2; #1; check_outputs("GroupB: 0xFFFF/2");
        A = 16'hFFFF; B = 8'd128; #1; check_outputs("GroupB: 0xFFFF/128");

        // Powers of 2
        A = 16'd256; B = 8'd1; #1; check_outputs("GroupB: 256/1");
        A = 16'd256; B = 8'd128; #1; check_outputs("GroupB: 256/128");
        A = 16'd512; B = 8'd64; #1; check_outputs("GroupB: 512/64");
        A = 16'd1024; B = 8'd32; #1; check_outputs("GroupB: 1024/32");
        A = 16'd32768; B = 8'd128; #1; check_outputs("GroupB: 32768/128");

        // =============================================
        // Group C: Randomized stress tests
        // =============================================
        for (i = 0; i < 50; i = i + 1) begin
            A = $random(seed);
            B = ($random(seed) % 255) + 1;  // avoid division by zero
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
module golden_div_16bit(
    input wire [15:0] A,
    input wire [7:0] B,
    output wire [15:0] result,
    output wire [15:0] odd
    );

reg [15:0] a_reg;
reg [15:0] b_reg;
reg [31:0] tmp_a;
reg [31:0] tmp_b;
integer i;

always@(*) begin
    a_reg = A;
    b_reg = B;
end

always@(*) begin
    begin
        tmp_a = {16'b0, a_reg};
        tmp_b = {b_reg, 16'b0};
        for(i = 0;i < 16;i = i+1) begin
            tmp_a = tmp_a << 1;
            if (tmp_a >= tmp_b) begin
                tmp_a = tmp_a - tmp_b + 1;
            end
            else begin
                tmp_a = tmp_a;
            end
        end
    end
end

assign odd = tmp_a[31:16];
assign result = tmp_a[15:0];

endmodule
