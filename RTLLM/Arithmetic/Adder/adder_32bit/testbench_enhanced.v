`timescale 1ns/1ps

module testbench_enhanced;

    // SECTION 1: Signal declarations
    reg [32:1] A;
    reg [32:1] B;

    wire [32:1] S_dut, S_ref;
    wire C32_dut, C32_ref;

    // SECTION 3: Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // SECTION 4: DUT instantiation
    adder_32bit uut (
        .A(A),
        .B(B),
        .S(S_dut),
        .C32(C32_dut)
    );

    // SECTION 5: Golden reference instantiation
    golden_adder_32bit ref_model (
        .A(A),
        .B(B),
        .S(S_ref),
        .C32(C32_ref)
    );

    // SECTION 6: Check task
    task check_outputs;
        input [255:0] description;
        begin
            check_id = check_id + 1;
            total_checks = total_checks + 1;
            if (S_dut !== S_ref || C32_dut !== C32_ref) begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL | %0s | expected S=%h C32=%b got S=%h C32=%b | time=%0t",
                    check_id, description, S_ref, C32_ref, S_dut, C32_dut, $time);
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
        A = 0; B = 0;

        // ---- Group A: Original testbench-style random cases ----
        for (i = 0; i < 5; i = i + 1) begin
            A = $random(seed);
            B = $random(seed);
            #1;
            check_outputs("A: original-style random");
        end

        // ---- Group B: Boundary/corner cases ----
        // B1: All zeros
        A = 32'h00000000; B = 32'h00000000; #1;
        check_outputs("B1: all zeros");

        // B2: Max + 0
        A = 32'hFFFFFFFF; B = 32'h00000000; #1;
        check_outputs("B2: FFFFFFFF+0");

        // B3: 0 + Max
        A = 32'h00000000; B = 32'hFFFFFFFF; #1;
        check_outputs("B3: 0+FFFFFFFF");

        // B4: Max + Max
        A = 32'hFFFFFFFF; B = 32'hFFFFFFFF; #1;
        check_outputs("B4: FFFFFFFF+FFFFFFFF");

        // B5: Max + 1 (overflow)
        A = 32'hFFFFFFFF; B = 32'h00000001; #1;
        check_outputs("B5: FFFFFFFF+1");

        // B6: 1 + 1
        A = 32'h00000001; B = 32'h00000001; #1;
        check_outputs("B6: 1+1");

        // B7: Carry propagation across 16-bit boundary
        A = 32'h0000FFFF; B = 32'h00000001; #1;
        check_outputs("B7: 0000FFFF+1");

        // B8: Carry across nibble
        A = 32'h0000000F; B = 32'h00000001; #1;
        check_outputs("B8: F+1 nibble carry");

        // B9: MSB carry
        A = 32'h80000000; B = 32'h80000000; #1;
        check_outputs("B9: 80000000+80000000");

        // B10: Alternating bits
        A = 32'hAAAAAAAA; B = 32'h55555555; #1;
        check_outputs("B10: AAAA+5555");

        // B11: Nibble boundary
        A = 32'h0F0F0F0F; B = 32'hF0F0F0F0; #1;
        check_outputs("B11: 0F0F+F0F0");

        // B12: Power of 2
        A = 32'h00010000; B = 32'h00010000; #1;
        check_outputs("B12: power of 2");

        // B13: Large carry chain
        A = 32'h7FFFFFFF; B = 32'h00000001; #1;
        check_outputs("B13: 7FFFFFFF+1");

        // B14: Walking ones
        A = 32'h00000001; B = 32'h00000002; #1;
        check_outputs("B14: walking ones 1+2");

        // B15: Walking ones 2
        A = 32'h00000004; B = 32'h00000008; #1;
        check_outputs("B15: walking ones 4+8");

        // B16: Byte boundary carry
        A = 32'h000000FF; B = 32'h00000001; #1;
        check_outputs("B16: FF+1 byte carry");

        // B17: Word boundary carry
        A = 32'h0000FFFF; B = 32'h0000FFFF; #1;
        check_outputs("B17: FFFF+FFFF");

        // B18: FFFE + 1
        A = 32'hFFFFFFFE; B = 32'h00000001; #1;
        check_outputs("B18: FFFFFFFE+1");

        // B19: FFFE + 2
        A = 32'hFFFFFFFE; B = 32'h00000002; #1;
        check_outputs("B19: FFFFFFFE+2");

        // B20: Complementary high/low
        A = 32'hFFFF0000; B = 32'h0000FFFF; #1;
        check_outputs("B20: FFFF0000+0000FFFF");

        // ---- Group C: Randomized stress tests ----
        for (i = 0; i < 50; i = i + 1) begin
            A = $random(seed);
            B = $random(seed);
            #1;
            check_outputs("C: random stress test");
        end

        // More boundary
        // B21-B25: Edge patterns
        A = 32'h12345678; B = 32'hEDCBA988; #1;
        check_outputs("B21: complementary sum");

        A = 32'h00FF00FF; B = 32'h00FF00FF; #1;
        check_outputs("B22: byte pattern");

        A = 32'hF0F0F0F0; B = 32'h0F0F0F0F; #1;
        check_outputs("B23: nibble complement");

        A = 32'h11111111; B = 32'h22222222; #1;
        check_outputs("B24: uniform nibbles");

        A = 32'hDEADBEEF; B = 32'hCAFEBABE; #1;
        check_outputs("B25: DEADBEEF+CAFEBABE");

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

module golden_adder_32bit(A,B,S,C32);
     input [32:1] A;
     input [32:1] B;
     output [32:1] S;
     output C32;

     wire px1,gx1,px2,gx2;
     wire c16;

  golden_CLA_16 CLA1(
      .A(A[16:1]),
        .B(B[16:1]),
        .c0(0),
        .S(S[16:1]),
        .px(px1),
        .gx(gx1)
    );

  golden_CLA_16 CLA2(
        .A(A[32:17]),
          .B(B[32:17]),
          .c0(c16),
          .S(S[32:17]),
          .px(px2),
          .gx(gx2)
    );

  assign c16 = gx1 ^ (px1 && 0),
         C32 = gx2 ^ (px2 && c16);
endmodule

module golden_CLA_16(A,B,c0,S,px,gx);
    input [16:1] A;
    input [16:1] B;
    input c0;
    output gx,px;
    output [16:1] S;

    wire c4,c8,c12;
    wire Pm1,Gm1,Pm2,Gm2,Pm3,Gm3,Pm4,Gm4;

    golden_adder_4 adder1(
         .x(A[4:1]),
          .y(B[4:1]),
          .c0(c0),
          .c4(),
          .F(S[4:1]),
          .Gm(Gm1),
          .Pm(Pm1)
    );

    golden_adder_4 adder2(
         .x(A[8:5]),
          .y(B[8:5]),
          .c0(c4),
          .c4(),
          .F(S[8:5]),
          .Gm(Gm2),
          .Pm(Pm2)
    );

    golden_adder_4 adder3(
         .x(A[12:9]),
          .y(B[12:9]),
          .c0(c8),
          .c4(),
          .F(S[12:9]),
          .Gm(Gm3),
          .Pm(Pm3)
    );

    golden_adder_4 adder4(
         .x(A[16:13]),
          .y(B[16:13]),
          .c0(c12),
          .c4(),
          .F(S[16:13]),
          .Gm(Gm4),
          .Pm(Pm4)
    );

    assign   c4 = Gm1 ^ (Pm1 & c0),
             c8 = Gm2 ^ (Pm2 & Gm1) ^ (Pm2 & Pm1 & c0),
             c12 = Gm3 ^ (Pm3 & Gm2) ^ (Pm3 & Pm2 & Gm1) ^ (Pm3 & Pm2 & Pm1 & c0);

    assign  px = Pm1 & Pm2 & Pm3 & Pm4,
            gx = Gm4 ^ (Pm4 & Gm3) ^ (Pm4 & Pm3 & Gm2) ^ (Pm4 & Pm3 & Pm2 & Gm1);
endmodule

module golden_adder_4(x,y,c0,c4,F,Gm,Pm);
      input [4:1] x;
      input [4:1] y;
      input c0;
      output c4,Gm,Pm;
      output [4:1] F;

      wire p1,p2,p3,p4,g1,g2,g3,g4;
      wire c1,c2,c3;
      golden_adder golden_adder1(
                 .X(x[1]),
                     .Y(y[1]),
                     .Cin(c0),
                     .F(F[1]),
                     .Cout()
                );

      golden_adder golden_adder2(
                 .X(x[2]),
                     .Y(y[2]),
                     .Cin(c1),
                     .F(F[2]),
                     .Cout()
                );

      golden_adder golden_adder3(
                 .X(x[3]),
                     .Y(y[3]),
                     .Cin(c2),
                     .F(F[3]),
                     .Cout()
                );

      golden_adder golden_adder4(
                 .X(x[4]),
                     .Y(y[4]),
                     .Cin(c3),
                     .F(F[4]),
                     .Cout()
                );

        golden_CLA golden_CLA_inst(
            .c0(c0),
            .c1(c1),
            .c2(c2),
            .c3(c3),
            .c4(c4),
            .p1(p1),
            .p2(p2),
            .p3(p3),
            .p4(p4),
            .g1(g1),
            .g2(g2),
            .g3(g3),
            .g4(g4)
        );

  assign   p1 = x[1] ^ y[1],
           p2 = x[2] ^ y[2],
           p3 = x[3] ^ y[3],
           p4 = x[4] ^ y[4];

  assign   g1 = x[1] & y[1],
           g2 = x[2] & y[2],
           g3 = x[3] & y[3],
           g4 = x[4] & y[4];

  assign Pm = p1 & p2 & p3 & p4,
         Gm = g4 ^ (p4 & g3) ^ (p4 & p3 & g2) ^ (p4 & p3 & p2 & g1);
endmodule

module golden_CLA(c0,c1,c2,c3,c4,p1,p2,p3,p4,g1,g2,g3,g4);

     input c0,g1,g2,g3,g4,p1,p2,p3,p4;
     output c1,c2,c3,c4;

     assign c1 = g1 ^ (p1 & c0),
            c2 = g2 ^ (p2 & g1) ^ (p2 & p1 & c0),
            c3 = g3 ^ (p3 & g2) ^ (p3 & p2 & g1) ^ (p3 & p2 & p1 & c0),
            c4 = g4^(p4&g3)^(p4&p3&g2)^(p4&p3&p2&g1)^(p4&p3&p2&p1&c0);
endmodule

module golden_adder(X,Y,Cin,F,Cout);

  input X,Y,Cin;
  output F,Cout;

  assign F = X ^ Y ^ Cin;
  assign Cout = (X ^ Y) & Cin | X & Y;
endmodule
