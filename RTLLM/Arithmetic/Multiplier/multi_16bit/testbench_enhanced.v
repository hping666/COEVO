`timescale 1ns/1ps

module tb_multi_16bit_enhanced;

    // Signal declarations
    reg clk;
    reg rst_n;
    reg start;
    reg [15:0] ain;
    reg [15:0] bin;
    wire [31:0] yout;
    wire done;
    wire [31:0] ref_yout;
    wire ref_done;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;
    integer timeout_cnt;

    // DUT instantiation
    multi_16bit uut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .ain(ain),
        .bin(bin),
        .yout(yout),
        .done(done)
    );

    // Golden reference instantiation
    golden_multi_16bit ref_model (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .ain(ain),
        .bin(bin),
        .yout(ref_yout),
        .done(ref_done)
    );

    // Clock generation: 10ns period
    always #5 clk = ~clk;

    // Check task
    task check_outputs;
        begin
            total_checks = total_checks + 1;
            check_id = check_id + 1;
            if (yout !== ref_yout || done !== ref_done) begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL: ain=%h bin=%h | DUT: yout=%h done=%b | REF: yout=%h done=%b",
                         check_id, ain, bin, yout, done, ref_yout, ref_done);
            end else begin
                passed_checks = passed_checks + 1;
            end
        end
    endtask

    // Task to run one multiplication and wait for done
    task run_multiply;
        input [15:0] a_val;
        input [15:0] b_val;
        begin
            // Reset
            rst_n = 0;
            start = 0;
            #100;
            rst_n = 1;
            #50;
            ain = a_val;
            bin = b_val;
            #10;
            start = 1;
            // Wait for DUT's done signal (spec: done=1 at i=16)
            timeout_cnt = 0;
            while (done !== 1'b1 && timeout_cnt < 500) begin
                #10;
                timeout_cnt = timeout_cnt + 1;
            end
            // Check DUT vs reference at the moment DUT asserts done
            check_outputs;
            start = 0;
            #20;
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
        rst_n = 1;
        start = 0;
        ain = 0;
        bin = 0;

        // =====================================================
        // Group A: Original testbench cases (replicate)
        // =====================================================
        $display("--- Group A: Original testbench cases ---");

        // Reset
        rst_n = 0;
        #100;
        rst_n = 1;
        #50;

        // Run 5 random-ish multiplications similar to original TB
        run_multiply(16'h1234, 16'h5678);
        run_multiply(16'hABCD, 16'hEF01);
        run_multiply(16'h0001, 16'hFFFF);
        run_multiply(16'hFFFF, 16'h0001);
        run_multiply(16'h00FF, 16'h00FF);

        // =====================================================
        // Group B: Boundary/corner cases
        // =====================================================
        $display("--- Group B: Boundary/corner cases ---");

        // All zeros
        run_multiply(16'h0000, 16'h0000);
        // Zero * max
        run_multiply(16'h0000, 16'hFFFF);
        run_multiply(16'hFFFF, 16'h0000);
        // Max * max
        run_multiply(16'hFFFF, 16'hFFFF);
        // One * values
        run_multiply(16'h0001, 16'h0001);
        run_multiply(16'h0001, 16'h0000);
        run_multiply(16'h0000, 16'h0001);
        run_multiply(16'h0001, 16'h8000);
        run_multiply(16'h8000, 16'h0001);
        // Power of 2 values
        run_multiply(16'h0002, 16'h0002);
        run_multiply(16'h0004, 16'h0008);
        run_multiply(16'h0010, 16'h0100);
        run_multiply(16'h8000, 16'h8000);
        run_multiply(16'h4000, 16'h0004);
        // Alternating bits
        run_multiply(16'hAAAA, 16'h5555);
        run_multiply(16'h5555, 16'hAAAA);
        run_multiply(16'hAAAA, 16'hAAAA);
        run_multiply(16'h5555, 16'h5555);
        // Carry propagation
        run_multiply(16'hFFFF, 16'h0002);
        run_multiply(16'h0002, 16'hFFFF);
        run_multiply(16'hFFFF, 16'hFFFE);
        run_multiply(16'hFFFE, 16'hFFFF);
        // Single bit patterns
        run_multiply(16'h0001, 16'hFFFF);
        run_multiply(16'h0080, 16'h0080);
        run_multiply(16'h0100, 16'h0100);
        run_multiply(16'h8000, 16'hFFFF);
        run_multiply(16'hFFFF, 16'h8000);
        // Near max
        run_multiply(16'hFFFE, 16'hFFFE);
        run_multiply(16'hFFFD, 16'hFFFD);
        run_multiply(16'h7FFF, 16'h7FFF);

        // =====================================================
        // Group C: Randomized stress testing
        // =====================================================
        $display("--- Group C: Randomized stress testing ---");

        for (i = 0; i < 50; i = i + 1) begin
            run_multiply($random(seed), $random(seed));
        end

        // =====================================================
        // Group D: Protocol/timing tests
        // =====================================================
        $display("--- Group D: Protocol/timing tests ---");

        // Test reset during operation
        rst_n = 0;
        start = 0;
        #100;
        rst_n = 1;
        #50;
        ain = 16'h1234;
        bin = 16'h5678;
        start = 1;
        #80; // Partial operation
        rst_n = 0; // Reset mid-operation
        #100;
        rst_n = 1;
        #50;
        // Now do a proper multiply to make sure it recovers
        run_multiply(16'h0003, 16'h0005);

        // Test start deassertion
        rst_n = 0;
        start = 0;
        #100;
        rst_n = 1;
        #50;
        ain = 16'h000A;
        bin = 16'h000B;
        start = 1;
        #40;
        start = 0; // Deassert start early
        #100;
        // Recover with proper multiply
        run_multiply(16'h0007, 16'h0009);

        // Back-to-back multiplications
        run_multiply(16'h1111, 16'h2222);
        run_multiply(16'h3333, 16'h4444);
        run_multiply(16'h5555, 16'h6666);

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
// Golden Reference Model - copy of verified_multi_16bit.v
// =========================================================
module golden_multi_16bit(
    input clk,
    input rst_n,
    input start,
    input [15:0] ain,
    input [15:0] bin,

    output [31:0] yout,
    output done
);

reg [15:0] areg;
reg [15:0] breg;
reg [31:0] yout_r;
reg done_r;
reg [4:0] i;

always @(posedge clk or negedge rst_n)
    if (!rst_n) i <= 5'd0;
    else if (start && i < 5'd17) i <= i + 1'b1;
    else if (!start) i <= 5'd0;

always @(posedge clk or negedge rst_n)
    if (!rst_n) done_r <= 1'b0;
    else if (i == 5'd16) done_r <= 1'b1;
    else if (i == 5'd17) done_r <= 1'b0;

assign done = done_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        areg <= 16'h0000;
        breg <= 16'h0000;
        yout_r <= 32'h00000000;
    end
    else if (start) begin
        if (i == 5'd0) begin
            areg <= ain;
            breg <= bin;
            yout_r <= 32'h00000000;
        end
        else if (i > 5'd0 && i < 5'd17) begin
            if (areg[i-1])
            yout_r <= yout_r + ({16'h0000, breg} << (i-1));
        end
    end
end

assign yout = yout_r;

endmodule
