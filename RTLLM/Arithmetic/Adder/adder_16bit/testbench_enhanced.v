`timescale 1ns/1ps

module testbench_enhanced;

    // SECTION 1: Signal declarations
    reg [15:0] a;
    reg [15:0] b;
    reg Cin;

    wire [15:0] y_dut, y_ref;
    wire Co_dut, Co_ref;

    // SECTION 3: Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // SECTION 4: DUT instantiation
    adder_16bit uut (
        .a(a),
        .b(b),
        .Cin(Cin),
        .y(y_dut),
        .Co(Co_dut)
    );

    // SECTION 5: Golden reference instantiation
    golden_adder_16bit ref_model (
        .a(a),
        .b(b),
        .Cin(Cin),
        .y(y_ref),
        .Co(Co_ref)
    );

    // SECTION 6: Check task
    task check_outputs;
        input [255:0] description;
        begin
            check_id = check_id + 1;
            total_checks = total_checks + 1;
            if (y_dut !== y_ref || Co_dut !== Co_ref) begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL | %0s | expected y=%h Co=%b got y=%h Co=%b | time=%0t",
                    check_id, description, y_ref, Co_ref, y_dut, Co_dut, $time);
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
        a = 0; b = 0; Cin = 0;

        // ---- Group A: Original testbench-style random cases (Cin=0) ----
        for (i = 0; i < 5; i = i + 1) begin
            a = $random(seed);
            b = $random(seed);
            Cin = 0;
            #1;
            check_outputs("A: random with Cin=0");
        end

        // ---- Group B: Boundary/corner cases ----
        // B1: All zeros
        a = 16'h0000; b = 16'h0000; Cin = 0; #1;
        check_outputs("B1: all zeros, Cin=0");

        // B2: All zeros with carry
        a = 16'h0000; b = 16'h0000; Cin = 1; #1;
        check_outputs("B2: all zeros, Cin=1");

        // B3: Max + 0
        a = 16'hFFFF; b = 16'h0000; Cin = 0; #1;
        check_outputs("B3: FFFF+0, Cin=0");

        // B4: Max + 0 + carry
        a = 16'hFFFF; b = 16'h0000; Cin = 1; #1;
        check_outputs("B4: FFFF+0, Cin=1");

        // B5: Max + Max
        a = 16'hFFFF; b = 16'hFFFF; Cin = 0; #1;
        check_outputs("B5: FFFF+FFFF, Cin=0");

        // B6: Max + Max + carry
        a = 16'hFFFF; b = 16'hFFFF; Cin = 1; #1;
        check_outputs("B6: FFFF+FFFF, Cin=1");

        // B7: Max + 1
        a = 16'hFFFF; b = 16'h0001; Cin = 0; #1;
        check_outputs("B7: FFFF+1, Cin=0");

        // B8: Power of 2 boundaries
        a = 16'h8000; b = 16'h8000; Cin = 0; #1;
        check_outputs("B8: 8000+8000, Cin=0");

        // B9: Carry propagation across byte boundary
        a = 16'h00FF; b = 16'h0001; Cin = 0; #1;
        check_outputs("B9: 00FF+0001, Cin=0");

        // B10: Carry propagation across nibble
        a = 16'h000F; b = 16'h0001; Cin = 0; #1;
        check_outputs("B10: 000F+0001, Cin=0");

        // B11: All ones in low byte
        a = 16'h00FF; b = 16'h00FF; Cin = 0; #1;
        check_outputs("B11: 00FF+00FF, Cin=0");

        // B12: All ones in high byte
        a = 16'hFF00; b = 16'hFF00; Cin = 0; #1;
        check_outputs("B12: FF00+FF00, Cin=0");

        // B13: Alternating bits
        a = 16'hAAAA; b = 16'h5555; Cin = 0; #1;
        check_outputs("B13: AAAA+5555, Cin=0");

        // B14: Alternating bits with carry
        a = 16'hAAAA; b = 16'h5555; Cin = 1; #1;
        check_outputs("B14: AAAA+5555, Cin=1");

        // B15: Single bit set
        a = 16'h0001; b = 16'h0000; Cin = 0; #1;
        check_outputs("B15: 0001+0000, Cin=0");

        // B16: Single high bit
        a = 16'h8000; b = 16'h0000; Cin = 0; #1;
        check_outputs("B16: 8000+0000, Cin=0");

        // B17: Carry chain test
        a = 16'h7FFF; b = 16'h0001; Cin = 0; #1;
        check_outputs("B17: 7FFF+0001, Cin=0");

        // B18: Full carry chain
        a = 16'hFFFE; b = 16'h0001; Cin = 1; #1;
        check_outputs("B18: FFFE+0001, Cin=1");

        // B19: Complementary pattern
        a = 16'hF0F0; b = 16'h0F0F; Cin = 0; #1;
        check_outputs("B19: F0F0+0F0F, Cin=0");

        // B20: Complementary with carry
        a = 16'hF0F0; b = 16'h0F0F; Cin = 1; #1;
        check_outputs("B20: F0F0+0F0F, Cin=1");

        // B21: Walking ones
        a = 16'h0001; b = 16'h0001; Cin = 0; #1;
        check_outputs("B21: walking ones 1+1");
        a = 16'h0002; b = 16'h0002; Cin = 0; #1;
        check_outputs("B22: walking ones 2+2");
        a = 16'h0004; b = 16'h0004; Cin = 0; #1;
        check_outputs("B23: walking ones 4+4");
        a = 16'h0008; b = 16'h0008; Cin = 0; #1;
        check_outputs("B24: walking ones 8+8");
        a = 16'h0010; b = 16'h0010; Cin = 0; #1;
        check_outputs("B25: walking ones 10+10");

        // ---- Group C: Randomized stress tests ----
        for (i = 0; i < 50; i = i + 1) begin
            a = $random(seed);
            b = $random(seed);
            Cin = $random(seed) % 2;
            #1;
            check_outputs("C: random stress test");
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

// SECTION 10: Golden reference model - all modules renamed with golden_ prefix

module golden_adder_16bit (
    input wire [15:0] a,
    input wire [15:0] b,
    input wire Cin,
    output wire [15:0] y,
    output wire Co
);

    wire Co_temp;

    golden_add8 golden_add8_inst1 (
        .a(a[15:8]),
        .b(b[15:8]),
        .Cin(Co_temp),
        .y(y[15:8]),
        .Co(Co)
    );

    golden_add8 golden_add8_inst2 (
        .a(a[7:0]),
        .b(b[7:0]),
        .Cin(Cin),
        .y(y[7:0]),
        .Co(Co_temp)
    );

endmodule

module golden_add8 (
    input wire [7:0] a,
    input wire [7:0] b,
    input wire Cin,
    output wire [7:0] y,
    output wire Co
);

    wire Co_temp;

    golden_add4 golden_add4_inst1 (
        .a(a[7:4]),
        .b(b[7:4]),
        .Cin(Co_temp),
        .y(y[7:4]),
        .Co(Co)
    );

    golden_add4 golden_add4_inst2 (
        .a(a[3:0]),
        .b(b[3:0]),
        .Cin(Cin),
        .y(y[3:0]),
        .Co(Co_temp)
    );

endmodule

module golden_add4 (
    input wire [3:0] a,
    input wire [3:0] b,
    input wire Cin,
    output wire [3:0] y,
    output wire Co
);

    wire Co_temp;

    golden_add2 golden_add2_inst1 (
        .a(a[3:2]),
        .b(b[3:2]),
        .Cin(Co_temp),
        .y(y[3:2]),
        .Co(Co)
    );

    golden_add2 golden_add2_inst2 (
        .a(a[1:0]),
        .b(b[1:0]),
        .Cin(Cin),
        .y(y[1:0]),
        .Co(Co_temp)
    );

endmodule

module golden_add2 (
    input wire [1:0] a,
    input wire [1:0] b,
    input wire Cin,
    output wire [1:0] y,
    output wire Co
);

    wire Co_temp;

    golden_add1 golden_add1_inst1 (
        .a(a[1]),
        .b(b[1]),
        .Cin(Co_temp),
        .y(y[1]),
        .Co(Co)
    );

    golden_add1 golden_add1_inst2 (
        .a(a[0]),
        .b(b[0]),
        .Cin(Cin),
        .y(y[0]),
        .Co(Co_temp)
    );

endmodule

module golden_add1 (
    input wire a,
    input wire b,
    input wire Cin,
    output wire y,
    output wire Co
);
    assign y = ((~a) & (~b) & Cin | (~a) & b & (~Cin) | a & (~b) & (~Cin) | (a & b & Cin));
    assign Co = ((~a & b & Cin) | (a & ~b & Cin) | (a & b & ~Cin) | (a & b & Cin));

endmodule
