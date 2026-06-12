`timescale 1ns/1ps

module testbench_enhanced;

    // Signal declarations
    reg clk;
    reg rst_n;
    reg din_serial;
    reg din_valid;
    wire [7:0] dout_parallel;
    wire dout_valid;

    // Golden reference outputs
    wire [7:0] ref_dout_parallel;
    wire ref_dout_valid;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i, j;

    // Clock generation: 10ns period
    initial clk = 0;
    always #5 clk = ~clk;

    // DUT instantiation
    serial2parallel uut (
        .clk(clk),
        .rst_n(rst_n),
        .din_serial(din_serial),
        .din_valid(din_valid),
        .dout_parallel(dout_parallel),
        .dout_valid(dout_valid)
    );

    // Golden reference instantiation
    golden_serial2parallel ref_model (
        .clk(clk),
        .rst_n(rst_n),
        .din_serial(din_serial),
        .din_valid(din_valid),
        .dout_parallel(ref_dout_parallel),
        .dout_valid(ref_dout_valid)
    );

    // Check task
    task check;
        input [7:0] dut_parallel;
        input dut_valid;
        input [7:0] gold_parallel;
        input gold_valid;
    begin
        check_id = check_id + 1;
        total_checks = total_checks + 1;
        if (dut_valid !== gold_valid || dut_parallel !== gold_parallel) begin
            $display("[FORGE_CHECK %0d] FAIL: DUT dout_parallel=%b dout_valid=%b, GOLD dout_parallel=%b dout_valid=%b at time %0t",
                     check_id, dut_parallel, dut_valid, gold_parallel, gold_valid, $time);
            failed_checks = failed_checks + 1;
        end else begin
            passed_checks = passed_checks + 1;
        end
    end
    endtask

    // Send one serial bit (drive din_serial on posedge clk)
    task send_bit;
        input bit_val;
    begin
        @(posedge clk);
        din_serial <= bit_val;
        din_valid <= 1'b1;
    end
    endtask

    // Send a full byte MSB first and check after 8th bit is clocked
    task send_byte;
        input [7:0] data;
    begin
        for (i = 7; i >= 0; i = i - 1) begin
            send_bit(data[i]);
        end
        // Wait one more cycle for output to appear (cnt reaches 8, then output registered)
        @(posedge clk); #1;
        check(dout_parallel, dout_valid, ref_dout_parallel, ref_dout_valid);
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
        din_serial = 0;
        din_valid = 0;

        // Reset
        @(posedge clk); #1;
        @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;

        // =============================================
        // Group A: Original testbench cases
        // =============================================

        // Test A1: Send 8'b11110000
        din_valid = 1;
        @(posedge clk); din_serial <= 1; // bit 7
        @(posedge clk); din_serial <= 1; // bit 6
        @(posedge clk); din_serial <= 1; // bit 5
        @(posedge clk); din_serial <= 1; // bit 4
        // Check dout_valid should be 0 midway
        @(posedge clk); #1;
        check(dout_parallel, dout_valid, ref_dout_parallel, ref_dout_valid);
        din_serial <= 0; // bit 3
        @(posedge clk); din_serial <= 0; // bit 2
        @(posedge clk); din_serial <= 0; // bit 1
        @(posedge clk); din_serial <= 0; // bit 0
        // Wait for output
        @(posedge clk); #1;
        check(dout_parallel, dout_valid, ref_dout_parallel, ref_dout_valid);

        // Deassert din_valid for a few cycles
        din_valid = 0;
        @(posedge clk); #1;
        check(dout_parallel, dout_valid, ref_dout_parallel, ref_dout_valid);
        @(posedge clk); #1;
        @(posedge clk); #1;

        // Test A2: Send 8'b11000011
        din_valid = 1;
        @(posedge clk); din_serial <= 1;
        @(posedge clk); din_serial <= 1;
        @(posedge clk); din_serial <= 0;
        @(posedge clk); din_serial <= 0;
        @(posedge clk); #1;
        check(dout_parallel, dout_valid, ref_dout_parallel, ref_dout_valid);
        din_serial <= 0;
        @(posedge clk); din_serial <= 0;
        @(posedge clk); din_serial <= 1;
        @(posedge clk); din_serial <= 1;
        @(posedge clk); #1;
        check(dout_parallel, dout_valid, ref_dout_parallel, ref_dout_valid);
        din_valid = 0;
        @(posedge clk); #1;
        check(dout_parallel, dout_valid, ref_dout_parallel, ref_dout_valid);

        // =============================================
        // Group B: Boundary/corner cases
        // =============================================

        // Reset and start fresh
        rst_n = 0;
        din_valid = 0;
        din_serial = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;

        // B1: Full byte 0xFF
        send_byte(8'hFF);

        // B2: Full byte 0x00
        send_byte(8'h00);

        // B3: Full byte 0xAA (alternating)
        send_byte(8'hAA);

        // B4: Full byte 0x55 (alternating inverse)
        send_byte(8'h55);

        // B5: Reset mid-byte (after 4 bits)
        din_valid = 1;
        @(posedge clk); din_serial <= 1;
        @(posedge clk); din_serial <= 0;
        @(posedge clk); din_serial <= 1;
        @(posedge clk); din_serial <= 0;
        // Now reset
        rst_n = 0;
        @(posedge clk); #1;
        check(dout_parallel, dout_valid, ref_dout_parallel, ref_dout_valid);
        @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;
        check(dout_parallel, dout_valid, ref_dout_parallel, ref_dout_valid);

        // B6: Send a full byte after reset mid-byte
        send_byte(8'hA5);

        // B7: din_valid goes low then high mid-stream (counter resets)
        din_valid = 1;
        @(posedge clk); din_serial <= 1;
        @(posedge clk); din_serial <= 1;
        @(posedge clk); din_serial <= 1;
        din_valid = 0;
        @(posedge clk); #1;
        check(dout_parallel, dout_valid, ref_dout_parallel, ref_dout_valid);
        @(posedge clk); #1;
        check(dout_parallel, dout_valid, ref_dout_parallel, ref_dout_valid);
        // Resume valid
        din_valid = 1;
        @(posedge clk); #1;
        check(dout_parallel, dout_valid, ref_dout_parallel, ref_dout_valid);
        // Now send full 8 bits fresh
        send_byte(8'h3C);

        // B8: Two consecutive bytes without gap
        send_byte(8'hDE);
        send_byte(8'hAD);

        // B9: Single bit 0x80
        send_byte(8'h80);

        // B10: Single bit 0x01
        send_byte(8'h01);

        // =============================================
        // Group C: Randomized stress
        // =============================================

        // Reset
        rst_n = 0;
        din_valid = 0;
        din_serial = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;

        // Send 10 random bytes
        for (j = 0; j < 10; j = j + 1) begin : random_loop
            reg [7:0] rand_byte;
            rand_byte = $random(seed);
            send_byte(rand_byte);
        end

        // Random valid toggling test
        for (j = 0; j < 5; j = j + 1) begin : random_valid_loop
            reg [7:0] rand_byte2;
            integer k;
            // Toggle valid off for random cycles
            din_valid = 0;
            for (k = 0; k < ($random(seed) % 4) + 1; k = k + 1) begin
                @(posedge clk); #1;
                check(dout_parallel, dout_valid, ref_dout_parallel, ref_dout_valid);
            end
            // Send a random byte
            rand_byte2 = $random(seed);
            send_byte(rand_byte2);
        end

        // =============================================
        // Group D: Protocol/timing tests
        // =============================================

        // Reset
        rst_n = 0;
        din_valid = 0;
        din_serial = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;

        // D1: Check that dout_valid is only high for one cycle
        send_byte(8'hF0);
        // dout_valid should go low on next cycle (after cnt resets)
        @(posedge clk); #1;
        check(dout_parallel, dout_valid, ref_dout_parallel, ref_dout_valid);

        // D2: Send data with valid low - should not affect counter
        din_valid = 0;
        din_serial = 1;
        @(posedge clk); #1;
        check(dout_parallel, dout_valid, ref_dout_parallel, ref_dout_valid);
        @(posedge clk); #1;
        check(dout_parallel, dout_valid, ref_dout_parallel, ref_dout_valid);
        @(posedge clk); #1;

        // D3: Multiple resets
        rst_n = 0;
        @(posedge clk); #1;
        check(dout_parallel, dout_valid, ref_dout_parallel, ref_dout_valid);
        rst_n = 1;
        @(posedge clk); #1;
        check(dout_parallel, dout_valid, ref_dout_parallel, ref_dout_valid);
        rst_n = 0;
        @(posedge clk); #1;
        check(dout_parallel, dout_valid, ref_dout_parallel, ref_dout_valid);
        rst_n = 1;
        @(posedge clk); #1;
        check(dout_parallel, dout_valid, ref_dout_parallel, ref_dout_valid);

        // D4: Three consecutive bytes back-to-back
        send_byte(8'h12);
        send_byte(8'h34);
        send_byte(8'h56);

        // D5: Check state after idle
        din_valid = 0;
        repeat(10) @(posedge clk);
        #1;
        check(dout_parallel, dout_valid, ref_dout_parallel, ref_dout_valid);

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
module golden_serial2parallel(
    input clk,
    input rst_n,
    input din_serial,
    input din_valid,
    output reg [7:0] dout_parallel,
    output reg dout_valid
);

    reg [7:0] din_tmp;
    reg [3:0] cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cnt <= 0;
        else if (din_valid)
            cnt <= (cnt == 4'd8) ? 0 : cnt + 1'b1;
        else
            cnt <= 0;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            din_tmp <= 8'b0;
        else if (din_valid && cnt <= 4'd7)
            din_tmp <= {din_tmp[6:0], din_serial};
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout_valid <= 1'b0;
            dout_parallel <= 8'b0;
        end
        else if (cnt == 4'd8) begin
            dout_valid <= 1'b1;
            dout_parallel <= din_tmp;
        end
        else begin
            dout_valid <= 1'b0;
        end
    end

endmodule
