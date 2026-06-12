`timescale 1ns/1ps

module testbench_enhanced;

    // Signal declarations
    reg clk;
    reg rst_n;
    reg write_en;
    reg [7:0] write_addr;
    reg [5:0] write_data;
    reg read_en;
    reg [7:0] read_addr;
    wire [5:0] read_data;
    wire [5:0] read_data_ref;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;
    reg [5:0] saved_data;

    // Clock generation
    parameter CLK_PERIOD = 10;
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // DUT instantiation
    RAM uut (
        .clk(clk), .rst_n(rst_n),
        .write_en(write_en), .write_addr(write_addr), .write_data(write_data),
        .read_en(read_en), .read_addr(read_addr), .read_data(read_data)
    );

    // Golden reference instantiation
    golden_RAM ref_model (
        .clk(clk), .rst_n(rst_n),
        .write_en(write_en), .write_addr(write_addr), .write_data(write_data),
        .read_en(read_en), .read_addr(read_addr), .read_data(read_data_ref)
    );

    // Check task
    task check_output;
        begin
            check_id = check_id + 1;
            total_checks = total_checks + 1;
            if (read_data === read_data_ref) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL read_data: expected=%b actual=%b (rd_en=%b rd_addr=%h wr_en=%b wr_addr=%h wr_data=%b)",
                    check_id, read_data_ref, read_data, read_en, read_addr, write_en, write_addr, write_data);
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
        // Initialize
        rst_n = 1;
        write_en = 0;
        write_addr = 0;
        write_data = 0;
        read_en = 0;
        read_addr = 0;

        // ===================== Group A: Original testbench cases =====================
        // Reset
        #(CLK_PERIOD * 2);
        rst_n = 0;
        #(CLK_PERIOD * 2);
        @(posedge clk); #1;
        check_output; // After reset, read_data should be 0

        rst_n = 1;
        #(CLK_PERIOD);

        // Write to address 0
        write_en = 1;
        write_addr = 8'b000;
        write_data = 6'b101010;
        saved_data = 6'b101010;
        @(posedge clk); #1;
        write_en = 0;
        @(posedge clk); #1;

        // Read from address 0
        read_en = 1;
        read_addr = 8'b000;
        @(posedge clk); #1;
        check_output;

        read_en = 0;
        @(posedge clk); #1;
        check_output; // read_data should be 0 when read_en=0

        // ===================== Group B: Boundary/corner cases =====================

        // B1: Reset and verify all locations are cleared
        rst_n = 0;
        @(posedge clk); #1;
        check_output;
        rst_n = 1;
        @(posedge clk); #1;

        // B2: Write and read all 8 addresses
        for (i = 0; i < 8; i = i + 1) begin
            write_en = 1;
            write_addr = i;
            write_data = i[5:0] + 6'd10;
            @(posedge clk); #1;
        end
        write_en = 0;
        @(posedge clk); #1;

        // Read back all 8 addresses
        for (i = 0; i < 8; i = i + 1) begin
            read_en = 1;
            read_addr = i;
            @(posedge clk); #1;
            check_output;
        end
        read_en = 0;
        @(posedge clk); #1;

        // B3: Write all 1s and all 0s
        write_en = 1;
        write_addr = 0;
        write_data = 6'b111111;
        @(posedge clk); #1;
        write_en = 0;

        read_en = 1;
        read_addr = 0;
        @(posedge clk); #1;
        check_output;

        write_en = 1;
        read_en = 0;
        write_addr = 0;
        write_data = 6'b000000;
        @(posedge clk); #1;
        write_en = 0;

        read_en = 1;
        read_addr = 0;
        @(posedge clk); #1;
        check_output;
        read_en = 0;

        // B4: Simultaneous read and write to same address
        write_en = 1;
        write_addr = 3;
        write_data = 6'b110011;
        @(posedge clk); #1;
        write_en = 0;
        @(posedge clk); #1;

        // Now simultaneous read and write to same address
        write_en = 1;
        read_en = 1;
        write_addr = 3;
        read_addr = 3;
        write_data = 6'b001100;
        @(posedge clk); #1;
        check_output;
        write_en = 0;
        read_en = 0;
        @(posedge clk); #1;

        // B5: Simultaneous read and write to different addresses
        // First write values
        write_en = 1;
        write_addr = 1;
        write_data = 6'b101010;
        @(posedge clk); #1;
        write_addr = 2;
        write_data = 6'b010101;
        @(posedge clk); #1;
        write_en = 0;
        @(posedge clk); #1;

        // Now simultaneous: write to addr 1, read from addr 2
        write_en = 1;
        read_en = 1;
        write_addr = 1;
        write_data = 6'b111000;
        read_addr = 2;
        @(posedge clk); #1;
        check_output;
        write_en = 0;
        read_en = 0;
        @(posedge clk); #1;

        // B6: Read without enable
        read_en = 0;
        read_addr = 1;
        @(posedge clk); #1;
        check_output; // Should be 0

        // B7: Write without enable
        write_en = 0;
        write_addr = 5;
        write_data = 6'b111111;
        @(posedge clk); #1;
        // Verify nothing was written
        read_en = 1;
        read_addr = 5;
        @(posedge clk); #1;
        check_output;
        read_en = 0;
        @(posedge clk); #1;

        // B8: Reset behavior - verify data is cleared
        // Write something first
        write_en = 1;
        write_addr = 7;
        write_data = 6'b111111;
        @(posedge clk); #1;
        write_en = 0;

        // Assert reset
        rst_n = 0;
        @(posedge clk); #1;
        check_output;
        rst_n = 1;
        @(posedge clk); #1;

        // Verify address 7 is cleared
        read_en = 1;
        read_addr = 7;
        @(posedge clk); #1;
        check_output;
        read_en = 0;
        @(posedge clk); #1;

        // ===================== Group C: Randomized stress =====================
        rst_n = 0;
        @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;

        for (i = 0; i < 30; i = i + 1) begin
            write_en = $random(seed) & 1;
            read_en = $random(seed) & 1;
            write_addr = $random(seed) % 8;
            read_addr = $random(seed) % 8;
            write_data = $random(seed) & 6'h3F;
            @(posedge clk); #1;
            check_output;
        end

        // Write random data then read back
        write_en = 1;
        read_en = 0;
        for (i = 0; i < 8; i = i + 1) begin
            write_addr = i;
            write_data = $random(seed) & 6'h3F;
            @(posedge clk); #1;
        end
        write_en = 0;

        // Read back
        read_en = 1;
        for (i = 0; i < 8; i = i + 1) begin
            read_addr = i;
            @(posedge clk); #1;
            check_output;
        end
        read_en = 0;
        @(posedge clk); #1;

        // ===================== Group D: Protocol/timing tests =====================

        // D1: Back-to-back writes to same address
        rst_n = 0;
        @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;

        write_en = 1;
        write_addr = 4;
        write_data = 6'b000001;
        @(posedge clk); #1;
        write_data = 6'b000010;
        @(posedge clk); #1;
        write_data = 6'b000100;
        @(posedge clk); #1;
        write_en = 0;

        // Read final value
        read_en = 1;
        read_addr = 4;
        @(posedge clk); #1;
        check_output;
        read_en = 0;
        @(posedge clk); #1;

        // D2: Continuous reading
        write_en = 1;
        write_addr = 0;
        write_data = 6'b110110;
        @(posedge clk); #1;
        write_en = 0;

        read_en = 1;
        read_addr = 0;
        @(posedge clk); #1;
        check_output;
        @(posedge clk); #1;
        check_output;
        @(posedge clk); #1;
        check_output;
        read_en = 0;
        @(posedge clk); #1;
        check_output; // Should be 0

        // D3: Write all addresses with unique patterns and read them all back
        rst_n = 0;
        @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;

        write_en = 1;
        read_en = 0;
        for (i = 0; i < 8; i = i + 1) begin
            write_addr = i;
            write_data = (i * 7 + 3) & 6'h3F;
            @(posedge clk); #1;
        end
        write_en = 0;
        read_en = 1;
        for (i = 0; i < 8; i = i + 1) begin
            read_addr = i;
            @(posedge clk); #1;
            check_output;
        end
        read_en = 0;
        @(posedge clk); #1;

        // D4: Overwrite and verify
        write_en = 1;
        read_en = 0;
        for (i = 0; i < 8; i = i + 1) begin
            write_addr = i;
            write_data = (~i) & 6'h3F;
            @(posedge clk); #1;
        end
        write_en = 0;
        read_en = 1;
        for (i = 0; i < 8; i = i + 1) begin
            read_addr = i;
            @(posedge clk); #1;
            check_output;
        end
        read_en = 0;
        @(posedge clk); #1;

        // D5: Write during reset (should be ignored)
        rst_n = 0;
        write_en = 1;
        write_addr = 6;
        write_data = 6'b111111;
        @(posedge clk); #1;
        check_output;
        write_en = 0;
        rst_n = 1;
        @(posedge clk); #1;

        read_en = 1;
        read_addr = 6;
        @(posedge clk); #1;
        check_output; // Should be 0 since reset cleared it
        read_en = 0;
        @(posedge clk); #1;

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

// ============================================================
// Golden reference model - copy of verified_RAM.v renamed
// ============================================================
module golden_RAM (
    input clk,
    input rst_n,

    input write_en,
    input [7:0] write_addr,
    input [5:0] write_data,

    input read_en,
    input [7:0] read_addr,
    output reg [5:0] read_data
);

    reg [5:0] ram_mem [7:0];

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 8; i = i + 1) begin
                ram_mem[i] <= 'd0;
            end
        end
        else if (write_en)
            ram_mem[write_addr] <= write_data;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            read_data <= 'd0;
        else if (read_en)
            read_data <= ram_mem[read_addr];
        else
            read_data <= 'd0;
    end
endmodule
