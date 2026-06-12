`timescale 1ns/1ps

module tb_multi_pipe_4bit_enhanced;

    parameter SIZE = 4;

    // Signal declarations
    reg clk;
    reg rst_n;
    reg [SIZE-1:0] mul_a;
    reg [SIZE-1:0] mul_b;
    wire [SIZE*2-1:0] mul_out;
    wire [SIZE*2-1:0] ref_mul_out;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // Store inputs for pipeline delay tracking
    reg [SIZE-1:0] a_d1, a_d2, b_d1, b_d2;

    // DUT instantiation
    multi_pipe_4bit #(.size(SIZE)) uut (
        .clk(clk),
        .rst_n(rst_n),
        .mul_a(mul_a),
        .mul_b(mul_b),
        .mul_out(mul_out)
    );

    // Golden reference instantiation
    golden_multi_pipe_4bit #(.size(SIZE)) ref_model (
        .clk(clk),
        .rst_n(rst_n),
        .mul_a(mul_a),
        .mul_b(mul_b),
        .mul_out(ref_mul_out)
    );

    // Clock generation: 10ns period
    always #5 clk = ~clk;

    // Track pipeline delay
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_d1 <= 0; a_d2 <= 0;
            b_d1 <= 0; b_d2 <= 0;
        end else begin
            a_d1 <= mul_a; a_d2 <= a_d1;
            b_d1 <= mul_b; b_d2 <= b_d1;
        end
    end

    // Check task - compare DUT vs golden
    task check_outputs;
        begin
            total_checks = total_checks + 1;
            check_id = check_id + 1;
            if (mul_out !== ref_mul_out) begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL: a_delayed=%h b_delayed=%h | DUT: mul_out=%h | REF: mul_out=%h",
                         check_id, a_d2, b_d2, mul_out, ref_mul_out);
            end else begin
                passed_checks = passed_checks + 1;
            end
        end
    endtask

    // Task: apply inputs and wait for pipeline (2 cycles), then check
    task apply_and_check;
        input [SIZE-1:0] a_val;
        input [SIZE-1:0] b_val;
        begin
            mul_a = a_val;
            mul_b = b_val;
            @(posedge clk); #1;
            @(posedge clk); #1;
            check_outputs;
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
        clk = 0;
        rst_n = 0;
        mul_a = 0;
        mul_b = 0;

        // Reset
        #20;
        rst_n = 1;
        #10;

        // =====================================================
        // Group A: Original testbench cases
        // =====================================================
        $display("--- Group A: Original testbench cases ---");

        apply_and_check(4'd3, 4'd5);
        apply_and_check(4'd7, 4'd9);
        apply_and_check(4'd12, 4'd11);
        apply_and_check(4'd1, 4'd15);
        apply_and_check(4'd8, 4'd6);

        // =====================================================
        // Group B: Boundary/corner cases
        // =====================================================
        $display("--- Group B: Boundary/corner cases ---");

        // All zeros
        apply_and_check(4'h0, 4'h0);
        // Zero * max
        apply_and_check(4'h0, 4'hF);
        apply_and_check(4'hF, 4'h0);
        // Max * max
        apply_and_check(4'hF, 4'hF);
        // One * values
        apply_and_check(4'h1, 4'h1);
        apply_and_check(4'h1, 4'hF);
        apply_and_check(4'hF, 4'h1);
        apply_and_check(4'h1, 4'h0);
        apply_and_check(4'h0, 4'h1);
        // Power of 2
        apply_and_check(4'h2, 4'h2);
        apply_and_check(4'h4, 4'h4);
        apply_and_check(4'h8, 4'h8);
        apply_and_check(4'h2, 4'h8);
        apply_and_check(4'h8, 4'h2);
        apply_and_check(4'h4, 4'h2);
        apply_and_check(4'h2, 4'h4);
        // Alternating bits
        apply_and_check(4'hA, 4'h5);
        apply_and_check(4'h5, 4'hA);
        apply_and_check(4'hA, 4'hA);
        apply_and_check(4'h5, 4'h5);
        // Carry propagation
        apply_and_check(4'hF, 4'h2);
        apply_and_check(4'h2, 4'hF);
        apply_and_check(4'hF, 4'hE);
        apply_and_check(4'hE, 4'hF);
        // Near max
        apply_and_check(4'hE, 4'hE);
        apply_and_check(4'hD, 4'hD);
        apply_and_check(4'h7, 4'h7);
        // Single bit patterns
        apply_and_check(4'h1, 4'h8);
        apply_and_check(4'h8, 4'h1);
        apply_and_check(4'h4, 4'h8);
        apply_and_check(4'h8, 4'h4);
        // Low/high nibble
        apply_and_check(4'h3, 4'hC);
        apply_and_check(4'hC, 4'h3);
        apply_and_check(4'h6, 4'h9);
        apply_and_check(4'h9, 4'h6);

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
        mul_a = 4'hA;
        mul_b = 4'hB;
        @(posedge clk); #1;
        rst_n = 0;
        #20;
        rst_n = 1;
        #10;
        // Verify recovery
        apply_and_check(4'h3, 4'h4);

        // Rapid input changes (pipeline stress)
        mul_a = 4'h1; mul_b = 4'h2; @(posedge clk); #1;
        mul_a = 4'h3; mul_b = 4'h4; @(posedge clk); #1;
        mul_a = 4'h5; mul_b = 4'h6; @(posedge clk); #1;
        // Check that pipeline output matches golden for each cycle
        check_outputs;
        mul_a = 4'h7; mul_b = 4'h8; @(posedge clk); #1;
        check_outputs;
        @(posedge clk); #1;
        check_outputs;

        // Back-to-back with constant inputs
        apply_and_check(4'hB, 4'hC);
        apply_and_check(4'hB, 4'hC);
        apply_and_check(4'hD, 4'hE);

        // Exhaustive small values
        for (i = 0; i < 16; i = i + 1) begin
            apply_and_check(i[3:0], (15-i));
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
// Golden Reference Model - copy of verified_multi_pipe_4bit.v
// =========================================================
module golden_multi_pipe_4bit#(
    parameter size = 4
)(
    input                       clk         ,
    input                       rst_n       ,
    input   [size-1:0]          mul_a       ,
    input   [size-1:0]          mul_b       ,

    output  reg [size*2-1:0]    mul_out
);

parameter N = 2 * size;

reg     [N-1:0]     sum_tmp1                ;
reg     [N-1:0]     sum_tmp2                ;
wire    [N-1:0]     mul_a_extend            ;
wire    [N-1:0]     mul_b_extend            ;

wire    [N-1:0]     mul_result[size-1:0]    ;

genvar gi;
generate
    for(gi = 0; gi < size; gi = gi + 1) begin:add
        assign mul_result[gi] = mul_b[gi] ? mul_a_extend << gi : 'd0;
    end
endgenerate

assign mul_a_extend = {{size{1'b0}}, mul_a};
assign mul_b_extend = {{size{1'b0}}, mul_b};

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        sum_tmp1 <= 'd0;
        sum_tmp2 <= 'd0;
    end
    else begin
        sum_tmp1 <= mul_result[0] + mul_result[1];
        sum_tmp2 <= mul_result[2] + mul_result[3];
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        mul_out <= 'd0;
    end
    else begin
        mul_out <= sum_tmp1 + sum_tmp2;
    end
end

endmodule
