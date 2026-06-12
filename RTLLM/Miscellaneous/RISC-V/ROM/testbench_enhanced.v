`timescale 1ns/1ps

module testbench_enhanced;

    // Signal declarations
    reg [7:0] addr;
    wire [15:0] dout;
    wire [15:0] dout_ref;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // DUT instantiation
    ROM uut (
        .addr(addr),
        .dout(dout)
    );

    // Golden reference instantiation
    golden_ROM ref_model (
        .addr(addr),
        .dout(dout_ref)
    );

    // Check task
    task check_output;
        begin
            check_id = check_id + 1;
            total_checks = total_checks + 1;
            if (dout === dout_ref) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL dout: expected=%h actual=%h (addr=%h)", check_id, dout_ref, dout, addr);
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
        addr = 0;
        #5;

        // ===================== Group A: Original testbench cases =====================
        addr = 8'h00; #10; check_output;
        addr = 8'h01; #10; check_output;
        addr = 8'h02; #10; check_output;
        addr = 8'h03; #10; check_output;

        // ===================== Group B: Boundary/corner cases =====================

        // B1: Read all initialized addresses again
        addr = 8'h00; #10; check_output;
        addr = 8'h01; #10; check_output;
        addr = 8'h02; #10; check_output;
        addr = 8'h03; #10; check_output;

        // B2: Boundary addresses
        addr = 8'h00; #10; check_output; // First address
        addr = 8'hFF; #10; check_output; // Last address
        addr = 8'h80; #10; check_output; // Mid-point
        addr = 8'h7F; #10; check_output; // Just below mid

        // B3: Addresses near initialized region
        addr = 8'h04; #10; check_output;
        addr = 8'h05; #10; check_output;
        addr = 8'h06; #10; check_output;
        addr = 8'h07; #10; check_output;

        // B4: Various uninitialized addresses
        addr = 8'h10; #10; check_output;
        addr = 8'h20; #10; check_output;
        addr = 8'h30; #10; check_output;
        addr = 8'h40; #10; check_output;
        addr = 8'h50; #10; check_output;
        addr = 8'h60; #10; check_output;
        addr = 8'h70; #10; check_output;
        addr = 8'h90; #10; check_output;
        addr = 8'hA0; #10; check_output;
        addr = 8'hB0; #10; check_output;
        addr = 8'hC0; #10; check_output;
        addr = 8'hD0; #10; check_output;
        addr = 8'hE0; #10; check_output;
        addr = 8'hF0; #10; check_output;

        // B5: All bits patterns for address
        addr = 8'b00000001; #10; check_output;
        addr = 8'b00000010; #10; check_output;
        addr = 8'b00000100; #10; check_output;
        addr = 8'b00001000; #10; check_output;
        addr = 8'b00010000; #10; check_output;
        addr = 8'b00100000; #10; check_output;
        addr = 8'b01000000; #10; check_output;
        addr = 8'b10000000; #10; check_output;

        // ===================== Group C: Randomized stress =====================
        for (i = 0; i < 20; i = i + 1) begin
            addr = $random(seed) & 8'hFF;
            #10;
            check_output;
        end

        // ===================== Group D: Protocol/timing tests =====================

        // D1: Rapid address switching
        addr = 8'h00; #10; check_output;
        addr = 8'h03; #10; check_output;
        addr = 8'h00; #10; check_output;
        addr = 8'h02; #10; check_output;
        addr = 8'h01; #10; check_output;
        addr = 8'h03; #10; check_output;

        // D2: Same address multiple reads
        addr = 8'h00;
        #10; check_output;
        #10; check_output;
        #10; check_output;

        // D3: Sequential sweep of low addresses
        for (i = 0; i < 16; i = i + 1) begin
            addr = i;
            #10;
            check_output;
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

// ============================================================
// Golden reference model - copy of verified_ROM.v renamed
// ============================================================
module golden_ROM (
    input wire [7:0] addr,
    output reg [15:0] dout
);

    reg [15:0] mem [0:255];

    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1)
            mem[i] = {2{8'hA0 + i[7:0] * 8'h11}};
    end

    always @(*) begin
        dout = mem[addr];
    end
endmodule
