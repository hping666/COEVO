`timescale 1ns/1ps

module testbench_enhanced;

    // Signal declarations
    reg clk;
    reg rst_n;
    reg valid_in;
    reg [7:0] data_in;
    wire valid_out;
    wire [15:0] data_out;

    // Golden reference outputs
    wire ref_valid_out;
    wire [15:0] ref_data_out;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // Clock generation: 10ns period
    initial clk = 1;
    always #5 clk = ~clk;

    // DUT instantiation
    width_8to16 uut (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .data_in(data_in),
        .valid_out(valid_out),
        .data_out(data_out)
    );

    // Golden reference instantiation
    golden_width_8to16 ref_model (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .data_in(data_in),
        .valid_out(ref_valid_out),
        .data_out(ref_data_out)
    );

    // Check task
    task check_outputs;
    begin
        check_id = check_id + 1;
        total_checks = total_checks + 1;
        if (valid_out !== ref_valid_out || data_out !== ref_data_out) begin
            $display("[FORGE_CHECK %0d] FAIL: DUT valid_out=%b data_out=%h, GOLD valid_out=%b data_out=%h at time %0t",
                     check_id, valid_out, data_out, ref_valid_out, ref_data_out, $time);
            failed_checks = failed_checks + 1;
        end else begin
            passed_checks = passed_checks + 1;
        end
    end
    endtask

    // Task: send one 8-bit value with valid_in high for one clock
    task send_byte;
        input [7:0] val;
    begin
        @(posedge clk);
        valid_in <= 1;
        data_in <= val;
        @(posedge clk);
        valid_in <= 0;
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
        rst_n = 0;
        valid_in = 0;
        data_in = 0;

        // =============================================
        // Group A: Original testbench cases
        // =============================================

        // Reset
        #10;
        rst_n = 1;
        valid_in = 1;
        data_in = 8'b10100000;
        #1;
        check_outputs; // A1: valid_out should be 0 after first byte

        @(posedge clk);
        data_in = 8'b10100001;
        #1;
        check_outputs; // A2

        @(posedge clk);
        data_in = 8'b10110000;
        #1;
        check_outputs; // A3: data_out should be 16'b1010000010100001, valid_out=1

        @(posedge clk);
        valid_in = 0;
        #1;
        check_outputs; // A4

        @(posedge clk); #1;
        @(posedge clk);
        valid_in = 1;
        data_in = 8'b10110001;
        #1;
        check_outputs; // A5

        @(posedge clk);
        valid_in = 0;
        #1;
        check_outputs; // A6: data_out should be 16'b1011000010110001, valid_out=1

        @(posedge clk); #1;
        check_outputs; // A7: valid_out should go back to 0

        // =============================================
        // Group B: Boundary/corner cases
        // =============================================

        // B1: Full reset
        rst_n = 0;
        valid_in = 0;
        data_in = 0;
        @(posedge clk); #1;
        check_outputs; // B1: everything zero after reset
        @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;
        check_outputs; // B2: after reset release

        // B3: Two consecutive bytes -> full 16-bit conversion (0xFF, 0x00)
        @(posedge clk);
        valid_in = 1;
        data_in = 8'hFF;
        @(posedge clk);
        data_in = 8'h00;
        @(posedge clk); #1;
        check_outputs; // B3: data_out = FF00, valid_out=1
        valid_in = 0;
        @(posedge clk); #1;
        check_outputs; // B4: valid_out should go to 0

        // B5: Two consecutive bytes (0x00, 0xFF)
        @(posedge clk);
        valid_in = 1;
        data_in = 8'h00;
        @(posedge clk);
        data_in = 8'hFF;
        @(posedge clk); #1;
        check_outputs; // B5: data_out = 00FF, valid_out=1
        valid_in = 0;
        @(posedge clk); #1;
        check_outputs; // B6: valid_out = 0

        // B7: Alternating patterns (0xAA, 0x55)
        @(posedge clk);
        valid_in = 1;
        data_in = 8'hAA;
        @(posedge clk);
        data_in = 8'h55;
        @(posedge clk); #1;
        check_outputs; // B7: data_out = AA55
        valid_in = 0;
        @(posedge clk); #1;
        check_outputs; // B8

        // B9: Reset mid-conversion (after first byte, before second)
        @(posedge clk);
        valid_in = 1;
        data_in = 8'hDE;
        @(posedge clk);
        valid_in = 0;
        // Now reset
        rst_n = 0;
        @(posedge clk); #1;
        check_outputs; // B9: reset clears everything
        @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;
        check_outputs; // B10: clean state

        // B11: Send two bytes after mid-reset recovery
        @(posedge clk);
        valid_in = 1;
        data_in = 8'h12;
        @(posedge clk);
        data_in = 8'h34;
        @(posedge clk); #1;
        check_outputs; // B11: data_out = 1234
        valid_in = 0;
        @(posedge clk); #1;
        check_outputs; // B12

        // B13: Four consecutive bytes -> two outputs
        @(posedge clk);
        valid_in = 1;
        data_in = 8'hAB;
        @(posedge clk);
        data_in = 8'hCD;
        @(posedge clk); #1;
        check_outputs; // B13: data_out = ABCD
        data_in = 8'hEF;
        @(posedge clk);
        data_in = 8'h01;
        @(posedge clk); #1;
        check_outputs; // B14: data_out = EF01
        valid_in = 0;
        @(posedge clk); #1;
        check_outputs; // B15

        // B16: Single byte then gap then single byte
        @(posedge clk);
        valid_in = 1;
        data_in = 8'h5A;
        @(posedge clk);
        valid_in = 0;
        repeat(5) @(posedge clk);
        #1;
        check_outputs; // B16: valid_out should still be 0

        @(posedge clk);
        valid_in = 1;
        data_in = 8'hA5;
        @(posedge clk); #1;
        check_outputs; // B17: data_out = 5AA5, valid_out=1
        valid_in = 0;
        @(posedge clk); #1;
        check_outputs; // B18

        // =============================================
        // Group C: Randomized stress
        // =============================================

        // Reset
        rst_n = 0;
        valid_in = 0;
        data_in = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;

        // Send 10 pairs of random bytes
        for (i = 0; i < 10; i = i + 1) begin
            @(posedge clk);
            valid_in = 1;
            data_in = $random(seed);
            @(posedge clk);
            data_in = $random(seed);
            @(posedge clk); #1;
            check_outputs; // should have valid output
            valid_in = 0;
            @(posedge clk); #1;
            check_outputs; // valid_out should be 0
        end

        // Random valid_in toggling
        for (i = 0; i < 5; i = i + 1) begin
            // Send first byte
            @(posedge clk);
            valid_in = 1;
            data_in = $random(seed);
            @(posedge clk);
            valid_in = 0;
            // Random gap
            repeat(($random(seed) & 3) + 1) @(posedge clk);
            #1;
            check_outputs;
            // Send second byte
            @(posedge clk);
            valid_in = 1;
            data_in = $random(seed);
            @(posedge clk); #1;
            check_outputs;
            valid_in = 0;
            @(posedge clk); #1;
            check_outputs;
        end

        // =============================================
        // Group D: Protocol/timing tests
        // =============================================

        // Reset
        rst_n = 0;
        valid_in = 0;
        data_in = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;

        // D1: valid_in stays high for 6 consecutive bytes -> 3 outputs
        @(posedge clk);
        valid_in = 1;
        data_in = 8'h11;
        @(posedge clk);
        data_in = 8'h22;
        @(posedge clk); #1;
        check_outputs; // D1: 1122
        data_in = 8'h33;
        @(posedge clk);
        data_in = 8'h44;
        @(posedge clk); #1;
        check_outputs; // D2: 3344
        data_in = 8'h55;
        @(posedge clk);
        data_in = 8'h66;
        @(posedge clk); #1;
        check_outputs; // D3: 5566
        valid_in = 0;
        @(posedge clk); #1;
        check_outputs; // D4: valid_out = 0

        // D5: data_in changes while valid_in=0 (should not affect)
        data_in = 8'hFF;
        @(posedge clk); #1;
        check_outputs; // D5
        data_in = 8'h00;
        @(posedge clk); #1;
        check_outputs; // D6

        // D7: Reset during output valid cycle
        @(posedge clk);
        valid_in = 1;
        data_in = 8'hBB;
        @(posedge clk);
        data_in = 8'hCC;
        @(posedge clk); #1;
        check_outputs; // D7: BBCC, valid=1
        // Reset immediately
        rst_n = 0;
        @(posedge clk); #1;
        check_outputs; // D8: reset
        rst_n = 1;
        valid_in = 0;
        @(posedge clk); #1;
        check_outputs; // D9: clean state

        // D10: Verify data_out holds its value when valid_out=0
        @(posedge clk);
        valid_in = 1;
        data_in = 8'h77;
        @(posedge clk);
        data_in = 8'h88;
        @(posedge clk); #1;
        check_outputs; // D10: 7788
        valid_in = 0;
        @(posedge clk); #1;
        check_outputs; // D11: valid=0 but data_out holds
        @(posedge clk); #1;
        check_outputs; // D12: still holds

        // =============================================
        // Score reporting
        // =============================================
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
// Golden Reference Model
// =============================================
module golden_width_8to16(
    input               clk,
    input               rst_n,
    input               valid_in,
    input   [7:0]       data_in,

    output  reg         valid_out,
    output  reg [15:0]  data_out
);

    reg [7:0] data_lock;
    reg       flag;

    // Input data buffer in data_lock
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            data_lock <= 'd0;
        else if (valid_in && !flag)
            data_lock <= data_in;
    end

    // Generate flag
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            flag <= 'd0;
        else if (valid_in)
            flag <= ~flag;
    end

    // Generate valid_out
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            valid_out <= 'd0;
        else if (valid_in && flag)
            valid_out <= 1'd1;
        else
            valid_out <= 'd0;
    end

    // Data stitching
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            data_out <= 'd0;
        else if (valid_in && flag)
            data_out <= {data_lock, data_in};
    end

endmodule
