`timescale 1ns/1ps

module tb_multi_8bit_enhanced;

    // Signal declarations
    reg [7:0] A;
    reg [7:0] B;
    wire [15:0] product;
    wire [15:0] ref_product;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // DUT instantiation
    multi_8bit uut (
        .A(A),
        .B(B),
        .product(product)
    );

    // Golden reference instantiation
    golden_multi_8bit ref_model (
        .A(A),
        .B(B),
        .product(ref_product)
    );

    // Check task
    task check_outputs;
        begin
            total_checks = total_checks + 1;
            check_id = check_id + 1;
            if (product !== ref_product) begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL: A=%h B=%h | DUT: product=%h | REF: product=%h",
                         check_id, A, B, product, ref_product);
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

    // Main test
    initial begin
        A = 0;
        B = 0;

        // =====================================================
        // Group A: Original testbench cases
        // =====================================================
        $display("--- Group A: Original testbench cases ---");

        for (i = 0; i < 5; i = i + 1) begin
            A = $random(seed);
            B = $random(seed);
            #10;
            check_outputs;
        end

        // =====================================================
        // Group B: Boundary/corner cases
        // =====================================================
        $display("--- Group B: Boundary/corner cases ---");

        // All zeros
        A = 8'h00; B = 8'h00; #10; check_outputs;
        // Zero * max
        A = 8'h00; B = 8'hFF; #10; check_outputs;
        A = 8'hFF; B = 8'h00; #10; check_outputs;
        // Max * max
        A = 8'hFF; B = 8'hFF; #10; check_outputs;
        // One * values
        A = 8'h01; B = 8'h01; #10; check_outputs;
        A = 8'h01; B = 8'hFF; #10; check_outputs;
        A = 8'hFF; B = 8'h01; #10; check_outputs;
        A = 8'h01; B = 8'h00; #10; check_outputs;
        A = 8'h00; B = 8'h01; #10; check_outputs;
        // Power of 2
        A = 8'h02; B = 8'h02; #10; check_outputs;
        A = 8'h04; B = 8'h08; #10; check_outputs;
        A = 8'h10; B = 8'h10; #10; check_outputs;
        A = 8'h80; B = 8'h80; #10; check_outputs;
        A = 8'h40; B = 8'h04; #10; check_outputs;
        A = 8'h80; B = 8'h01; #10; check_outputs;
        A = 8'h01; B = 8'h80; #10; check_outputs;
        // Alternating bits
        A = 8'hAA; B = 8'h55; #10; check_outputs;
        A = 8'h55; B = 8'hAA; #10; check_outputs;
        A = 8'hAA; B = 8'hAA; #10; check_outputs;
        A = 8'h55; B = 8'h55; #10; check_outputs;
        // Carry propagation
        A = 8'hFF; B = 8'h02; #10; check_outputs;
        A = 8'h02; B = 8'hFF; #10; check_outputs;
        A = 8'hFF; B = 8'hFE; #10; check_outputs;
        A = 8'hFE; B = 8'hFF; #10; check_outputs;
        // Near max
        A = 8'hFE; B = 8'hFE; #10; check_outputs;
        A = 8'hFD; B = 8'hFD; #10; check_outputs;
        A = 8'h7F; B = 8'h7F; #10; check_outputs;
        // Single bit set
        A = 8'h01; B = 8'h02; #10; check_outputs;
        A = 8'h02; B = 8'h04; #10; check_outputs;
        A = 8'h08; B = 8'h10; #10; check_outputs;
        A = 8'h20; B = 8'h40; #10; check_outputs;
        A = 8'h80; B = 8'hFF; #10; check_outputs;
        A = 8'hFF; B = 8'h80; #10; check_outputs;
        // Low byte patterns
        A = 8'h0F; B = 8'h0F; #10; check_outputs;
        A = 8'hF0; B = 8'hF0; #10; check_outputs;
        A = 8'h0F; B = 8'hF0; #10; check_outputs;
        A = 8'hF0; B = 8'h0F; #10; check_outputs;

        // =====================================================
        // Group C: Randomized stress testing
        // =====================================================
        $display("--- Group C: Randomized stress testing ---");

        for (i = 0; i < 50; i = i + 1) begin
            A = $random(seed);
            B = $random(seed);
            #10;
            check_outputs;
        end

        // =====================================================
        // Group D: Exhaustive small values (combinational)
        // =====================================================
        $display("--- Group D: Small value sweep ---");

        for (i = 0; i < 16; i = i + 1) begin
            A = i[7:0];
            B = i[7:0];
            #10;
            check_outputs;
        end

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

// =========================================================
// Golden Reference Model - copy of verified_multi_8bit.v
// =========================================================
module golden_multi_8bit (
  input [7:0] A,
  input [7:0] B,
  output reg [15:0] product
);

  reg [7:0] multiplicand;
  reg [3:0] shift_count;
  integer i;

  always @* begin
    product = 16'b0;
    multiplicand = A;
    shift_count = 0;

    for (i = 0; i < 8; i = i + 1) begin
      if (B[i] == 1) begin
        product = product + (multiplicand << shift_count);
      end
      shift_count = shift_count + 1;
    end
  end

endmodule
