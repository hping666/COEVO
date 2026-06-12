`timescale 1ns/1ps

module testbench_enhanced;

    // SECTION 1: Signal declarations
    reg [7:0] a;
    reg [7:0] b;
    reg cin;

    wire [7:0] sum_dut, sum_ref;
    wire cout_dut, cout_ref;

    // SECTION 3: Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // SECTION 4: DUT instantiation
    adder_8bit uut (
        .a(a),
        .b(b),
        .cin(cin),
        .sum(sum_dut),
        .cout(cout_dut)
    );

    // SECTION 5: Golden reference instantiation
    golden_adder_8bit ref_model (
        .a(a),
        .b(b),
        .cin(cin),
        .sum(sum_ref),
        .cout(cout_ref)
    );

    // SECTION 6: Check task
    task check_outputs;
        input [255:0] description;
        begin
            check_id = check_id + 1;
            total_checks = total_checks + 1;
            if (sum_dut !== sum_ref || cout_dut !== cout_ref) begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL | %0s | expected sum=%h cout=%b got sum=%h cout=%b | time=%0t",
                    check_id, description, sum_ref, cout_ref, sum_dut, cout_dut, $time);
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
        a = 0; b = 0; cin = 0;

        // ---- Group A: Original testbench-style random cases ----
        for (i = 0; i < 5; i = i + 1) begin
            a = $random(seed) & 8'hFF;
            b = $random(seed) & 8'hFF;
            cin = $random(seed) & 1'b1;
            #1;
            check_outputs("A: original-style random");
        end

        // ---- Group B: Boundary/corner cases ----
        // B1: All zeros, no carry
        a = 8'h00; b = 8'h00; cin = 0; #1;
        check_outputs("B1: 00+00, cin=0");

        // B2: All zeros, carry in
        a = 8'h00; b = 8'h00; cin = 1; #1;
        check_outputs("B2: 00+00, cin=1");

        // B3: Max + 0
        a = 8'hFF; b = 8'h00; cin = 0; #1;
        check_outputs("B3: FF+00, cin=0");

        // B4: Max + 0 + carry
        a = 8'hFF; b = 8'h00; cin = 1; #1;
        check_outputs("B4: FF+00, cin=1");

        // B5: Max + Max
        a = 8'hFF; b = 8'hFF; cin = 0; #1;
        check_outputs("B5: FF+FF, cin=0");

        // B6: Max + Max + carry
        a = 8'hFF; b = 8'hFF; cin = 1; #1;
        check_outputs("B6: FF+FF, cin=1");

        // B7: Max + 1
        a = 8'hFF; b = 8'h01; cin = 0; #1;
        check_outputs("B7: FF+01, cin=0");

        // B8: Max + 1 + carry
        a = 8'hFF; b = 8'h01; cin = 1; #1;
        check_outputs("B8: FF+01, cin=1");

        // B9: Carry propagation from bit 3 to 4
        a = 8'h0F; b = 8'h01; cin = 0; #1;
        check_outputs("B9: 0F+01 nibble carry");

        // B10: Carry propagation full chain
        a = 8'h7F; b = 8'h01; cin = 0; #1;
        check_outputs("B10: 7F+01 carry chain");

        // B11: Alternating bits
        a = 8'hAA; b = 8'h55; cin = 0; #1;
        check_outputs("B11: AA+55, cin=0");

        // B12: Alternating bits + carry
        a = 8'hAA; b = 8'h55; cin = 1; #1;
        check_outputs("B12: AA+55, cin=1");

        // B13: MSB carry
        a = 8'h80; b = 8'h80; cin = 0; #1;
        check_outputs("B13: 80+80, cin=0");

        // B14: Single bit
        a = 8'h01; b = 8'h00; cin = 0; #1;
        check_outputs("B14: 01+00, cin=0");

        // B15: Complementary nibbles
        a = 8'hF0; b = 8'h0F; cin = 0; #1;
        check_outputs("B15: F0+0F, cin=0");

        // B16: Complementary nibbles + carry
        a = 8'hF0; b = 8'h0F; cin = 1; #1;
        check_outputs("B16: F0+0F, cin=1");

        // B17: FE + 1
        a = 8'hFE; b = 8'h01; cin = 0; #1;
        check_outputs("B17: FE+01, cin=0");

        // B18: FE + 1 + carry
        a = 8'hFE; b = 8'h01; cin = 1; #1;
        check_outputs("B18: FE+01, cin=1");

        // B19: Powers of 2
        a = 8'h40; b = 8'h40; cin = 0; #1;
        check_outputs("B19: 40+40");

        // B20: Small values
        a = 8'h01; b = 8'h01; cin = 1; #1;
        check_outputs("B20: 01+01, cin=1");

        // ---- Group C: Randomized stress tests ----
        for (i = 0; i < 50; i = i + 1) begin
            a = $random(seed) & 8'hFF;
            b = $random(seed) & 8'hFF;
            cin = $random(seed) & 1'b1;
            #1;
            check_outputs("C: random stress test");
        end

        // More boundary tests
        a = 8'h10; b = 8'h10; cin = 0; #1;
        check_outputs("B21: 10+10");
        a = 8'h20; b = 8'h20; cin = 0; #1;
        check_outputs("B22: 20+20");
        a = 8'hC0; b = 8'hC0; cin = 0; #1;
        check_outputs("B23: C0+C0");
        a = 8'h55; b = 8'hAA; cin = 1; #1;
        check_outputs("B24: 55+AA, cin=1");
        a = 8'h33; b = 8'hCC; cin = 0; #1;
        check_outputs("B25: 33+CC, cin=0");

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

// SECTION 10: Golden reference model

module golden_adder_8bit(
    input [7:0] a, b,
    input cin,
    output [7:0] sum,
    output cout);

    wire [8:0] c;

    golden_full_adder FA0 (.a(a[0]), .b(b[0]), .cin(cin),  .sum(sum[0]), .cout(c[0]));
    golden_full_adder FA1 (.a(a[1]), .b(b[1]), .cin(c[0]), .sum(sum[1]), .cout(c[1]));
    golden_full_adder FA2 (.a(a[2]), .b(b[2]), .cin(c[1]), .sum(sum[2]), .cout(c[2]));
    golden_full_adder FA3 (.a(a[3]), .b(b[3]), .cin(c[2]), .sum(sum[3]), .cout(c[3]));
    golden_full_adder FA4 (.a(a[4]), .b(b[4]), .cin(c[3]), .sum(sum[4]), .cout(c[4]));
    golden_full_adder FA5 (.a(a[5]), .b(b[5]), .cin(c[4]), .sum(sum[5]), .cout(c[5]));
    golden_full_adder FA6 (.a(a[6]), .b(b[6]), .cin(c[5]), .sum(sum[6]), .cout(c[6]));
    golden_full_adder FA7 (.a(a[7]), .b(b[7]), .cin(c[6]), .sum(sum[7]), .cout(c[7]));

    assign cout = c[7];
endmodule

module golden_full_adder (input a, b, cin, output sum, cout);
    assign {cout, sum} = a + b + cin;
endmodule
