`timescale 1ns/1ps

module tb_multi_pipe_8bit_enhanced;

    // Signal declarations
    reg clk;
    reg rst_n;
    reg mul_en_in;
    reg [7:0] mul_a;
    reg [7:0] mul_b;
    wire mul_en_out;
    wire [15:0] mul_out;
    wire ref_mul_en_out;
    wire [15:0] ref_mul_out;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;
    integer timeout_cnt;

    // DUT instantiation
    multi_pipe_8bit uut (
        .clk(clk),
        .rst_n(rst_n),
        .mul_en_in(mul_en_in),
        .mul_a(mul_a),
        .mul_b(mul_b),
        .mul_en_out(mul_en_out),
        .mul_out(mul_out)
    );

    // Golden reference instantiation
    golden_multi_pipe_8bit ref_model (
        .clk(clk),
        .rst_n(rst_n),
        .mul_en_in(mul_en_in),
        .mul_a(mul_a),
        .mul_b(mul_b),
        .mul_en_out(ref_mul_en_out),
        .mul_out(ref_mul_out)
    );

    // Clock generation: 20ns period
    always #10 clk = ~clk;

    // Check task
    task check_outputs;
        begin
            total_checks = total_checks + 1;
            check_id = check_id + 1;
            if (mul_out !== ref_mul_out || mul_en_out !== ref_mul_en_out) begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL: a=%h b=%h | DUT: out=%h en_out=%b | REF: out=%h en_out=%b",
                         check_id, mul_a, mul_b, mul_out, mul_en_out, ref_mul_out, ref_mul_en_out);
            end else begin
                passed_checks = passed_checks + 1;
            end
        end
    endtask

    // Task: apply inputs, assert mul_en_in for 1 cycle, wait for ref_mul_en_out, check
    task apply_and_check;
        input [7:0] a_val;
        input [7:0] b_val;
        begin
            mul_a = a_val;
            mul_b = b_val;
            mul_en_in = 1;
            @(posedge clk); #1;
            mul_en_in = 0;
            // Wait for ref_mul_en_out to assert, checking every cycle
            timeout_cnt = 0;
            while (ref_mul_en_out !== 1'b1 && timeout_cnt < 100) begin
                @(posedge clk); #1;
                timeout_cnt = timeout_cnt + 1;
                check_outputs;  // catches DUT asserting en_out early
            end
            check_outputs;  // check when golden asserts
            // Wait one more cycle for enable to deassert
            @(posedge clk); #1;
            check_outputs;  // check deassert behavior
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
        clk = 1;
        rst_n = 0;
        mul_a = 0;
        mul_b = 0;
        mul_en_in = 0;

        // Reset
        #200;
        rst_n = 1;
        #200;

        // =====================================================
        // Group A: Original testbench cases
        // =====================================================
        $display("--- Group A: Original testbench cases ---");

        apply_and_check(8'd35, 8'd20);
        apply_and_check(8'd100, 8'd50);
        apply_and_check(8'd255, 8'd255);
        apply_and_check(8'd17, 8'd13);
        apply_and_check(8'd200, 8'd150);

        // =====================================================
        // Group B: Boundary/corner cases
        // =====================================================
        $display("--- Group B: Boundary/corner cases ---");

        // All zeros
        apply_and_check(8'h00, 8'h00);
        // Zero * max
        apply_and_check(8'h00, 8'hFF);
        apply_and_check(8'hFF, 8'h00);
        // Max * max
        apply_and_check(8'hFF, 8'hFF);
        // One values
        apply_and_check(8'h01, 8'h01);
        apply_and_check(8'h01, 8'hFF);
        apply_and_check(8'hFF, 8'h01);
        apply_and_check(8'h01, 8'h00);
        apply_and_check(8'h00, 8'h01);
        // Power of 2
        apply_and_check(8'h02, 8'h02);
        apply_and_check(8'h04, 8'h08);
        apply_and_check(8'h10, 8'h10);
        apply_and_check(8'h80, 8'h80);
        apply_and_check(8'h40, 8'h04);
        apply_and_check(8'h80, 8'h01);
        apply_and_check(8'h01, 8'h80);
        // Alternating bits
        apply_and_check(8'hAA, 8'h55);
        apply_and_check(8'h55, 8'hAA);
        apply_and_check(8'hAA, 8'hAA);
        apply_and_check(8'h55, 8'h55);
        // Carry propagation
        apply_and_check(8'hFF, 8'h02);
        apply_and_check(8'h02, 8'hFF);
        apply_and_check(8'hFF, 8'hFE);
        apply_and_check(8'hFE, 8'hFF);
        // Near max
        apply_and_check(8'hFE, 8'hFE);
        apply_and_check(8'hFD, 8'hFD);
        apply_and_check(8'h7F, 8'h7F);
        // Single bit patterns
        apply_and_check(8'h08, 8'h10);
        apply_and_check(8'h20, 8'h40);
        apply_and_check(8'h80, 8'hFF);
        apply_and_check(8'hFF, 8'h80);
        // Nibble patterns
        apply_and_check(8'h0F, 8'h0F);
        apply_and_check(8'hF0, 8'hF0);
        apply_and_check(8'h0F, 8'hF0);
        apply_and_check(8'hF0, 8'h0F);

        // =====================================================
        // Group C: Randomized stress testing
        // =====================================================
        $display("--- Group C: Randomized stress testing ---");

        for (i = 0; i < 50; i = i + 1) begin
            apply_and_check($random(seed), $random(seed));
        end

        // =====================================================
        // Group D: Protocol/timing tests
        // =====================================================
        $display("--- Group D: Protocol/timing tests ---");

        // Reset mid-operation
        mul_a = 8'hAB;
        mul_b = 8'hCD;
        mul_en_in = 1;
        @(posedge clk); #1;
        mul_en_in = 0;
        @(posedge clk); #1;
        // Reset now
        rst_n = 0;
        #100;
        rst_n = 1;
        #100;
        // Verify recovery
        apply_and_check(8'h03, 8'h05);

        // Test with mul_en_in held high for multiple cycles
        mul_a = 8'h11;
        mul_b = 8'h22;
        mul_en_in = 1;
        @(posedge clk); #1;
        mul_a = 8'h33;
        mul_b = 8'h44;
        @(posedge clk); #1;
        mul_a = 8'h55;
        mul_b = 8'h66;
        @(posedge clk); #1;
        mul_en_in = 0;
        // Wait for all outputs
        timeout_cnt = 0;
        while (ref_mul_en_out !== 1'b1 && timeout_cnt < 100) begin
            @(posedge clk); #1;
            timeout_cnt = timeout_cnt + 1;
        end
        check_outputs;
        @(posedge clk); #1;
        if (ref_mul_en_out === 1'b1) check_outputs;
        @(posedge clk); #1;
        if (ref_mul_en_out === 1'b1) check_outputs;
        @(posedge clk); #1;

        // Back-to-back single-cycle enables
        apply_and_check(8'hBB, 8'hCC);
        apply_and_check(8'hDD, 8'hEE);
        apply_and_check(8'h12, 8'h34);

        // Test with enable never asserted (should stay 0)
        mul_en_in = 0;
        mul_a = 8'hFF;
        mul_b = 8'hFF;
        repeat(5) @(posedge clk);
        #1;
        check_outputs;

        // Final recovery test
        apply_and_check(8'h07, 8'h09);

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
// Golden Reference Model - copy of verified_multi_pipe_8bit.v
// =========================================================
module golden_multi_pipe_8bit#(
    parameter size = 8
)(
          clk,
          rst_n,
          mul_a,
          mul_b,
          mul_en_in,

          mul_en_out,
          mul_out
);

   input clk;
   input rst_n;
   input mul_en_in;
   input [size-1:0] mul_a;
   input [size-1:0] mul_b;

   output reg mul_en_out;
   output reg [size*2-1:0] mul_out;


   reg [2:0] mul_en_out_reg;
 always@(posedge clk or negedge rst_n)
       if(!rst_n)begin
            mul_en_out_reg <= 'd0;
            mul_en_out     <= 'd0;
       end
       else begin
            mul_en_out_reg <= {mul_en_out_reg[1:0],mul_en_in};
            mul_en_out     <= mul_en_out_reg[2];
       end


    reg [7:0] mul_a_reg;
    reg [7:0] mul_b_reg;
  always @(posedge clk or negedge rst_n)
         if(!rst_n) begin
              mul_a_reg <= 'd0;
              mul_b_reg <= 'd0;
         end
         else begin
              mul_a_reg <= mul_en_in ? mul_a :'d0;
              mul_b_reg <= mul_en_in ? mul_b :'d0;
         end


     wire [15:0] temp [size-1:0];
  assign temp[0] = mul_b_reg[0]? {8'b0,mul_a_reg} : 'd0;
  assign temp[1] = mul_b_reg[1]? {7'b0,mul_a_reg,1'b0} : 'd0;
  assign temp[2] = mul_b_reg[2]? {6'b0,mul_a_reg,2'b0} : 'd0;
  assign temp[3] = mul_b_reg[3]? {5'b0,mul_a_reg,3'b0} : 'd0;
  assign temp[4] = mul_b_reg[4]? {4'b0,mul_a_reg,4'b0} : 'd0;
  assign temp[5] = mul_b_reg[5]? {3'b0,mul_a_reg,5'b0} : 'd0;
  assign temp[6] = mul_b_reg[6]? {2'b0,mul_a_reg,6'b0} : 'd0;
  assign temp[7] = mul_b_reg[7]? {1'b0,mul_a_reg,7'b0} : 'd0;


     reg [15:0] sum [3:0];
 always @(posedge clk or negedge rst_n)
       if(!rst_n) begin
          sum[0]  <= 'd0;
          sum[1]  <= 'd0;
          sum[2]  <= 'd0;
          sum[3]  <= 'd0;
       end
       else begin
          sum[0] <= temp[0] + temp[1];
          sum[1] <= temp[2] + temp[3];
          sum[2] <= temp[4] + temp[5];
          sum[3] <= temp[6] + temp[7];
       end

     reg [15:0] mul_out_reg;
 always @(posedge clk or negedge rst_n)
       if(!rst_n)
          mul_out_reg <= 'd0;
       else
          mul_out_reg <= sum[0] + sum[1] + sum[2] + sum[3];


 always @(posedge clk or negedge rst_n)
       if(!rst_n)
          mul_out <= 'd0;
       else if(mul_en_out_reg[2])
          mul_out <= mul_out_reg;
       else
          mul_out <= 'd0;


endmodule
