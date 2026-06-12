`timescale 1ns/1ps

module testbench_enhanced;

    // Signal declarations
    reg [7:0] in;
    reg [2:0] ctrl;
    wire [7:0] out;
    wire [7:0] out_ref;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i, j;

    // DUT instantiation
    barrel_shifter uut (
        .in(in),
        .ctrl(ctrl),
        .out(out)
    );

    // Golden reference instantiation
    golden_barrel_shifter ref_model (
        .in(in),
        .ctrl(ctrl),
        .out(out_ref)
    );

    // Check task
    task check;
        input [199:0] test_name;
        begin
            check_id = check_id + 1;
            total_checks = total_checks + 1;
            if (out === out_ref) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FAIL] Check %0d: %s - in=%b ctrl=%d DUT out=%b REF out=%b",
                    check_id, test_name, in, ctrl, out, out_ref);
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
        // =============================================
        // Group A: Original testbench cases
        // =============================================
        in = 8'd0; ctrl = 3'd0;
        #10;
        check("A: 0 shift 0");

        in = 8'd128; ctrl = 3'd4;
        #10;
        check("A: 128 shift 4");

        in = 8'd128; ctrl = 3'd2;
        #10;
        check("A: 128 shift 2");

        in = 8'd128; ctrl = 3'd1;
        #10;
        check("A: 128 shift 1");

        in = 8'd255; ctrl = 3'd7;
        #10;
        check("A: 255 shift 7");

        // =============================================
        // Group B: Boundary/corner cases
        // =============================================

        // B1: Shift by 0 (no shift) for various inputs
        in = 8'hFF; ctrl = 3'd0;
        #10;
        check("B: FF shift 0");

        in = 8'h01; ctrl = 3'd0;
        #10;
        check("B: 01 shift 0");

        in = 8'h80; ctrl = 3'd0;
        #10;
        check("B: 80 shift 0");

        in = 8'hA5; ctrl = 3'd0;
        #10;
        check("B: A5 shift 0");

        // B2: Shift by max (7) for various inputs
        in = 8'hFF; ctrl = 3'd7;
        #10;
        check("B: FF shift 7");

        in = 8'h80; ctrl = 3'd7;
        #10;
        check("B: 80 shift 7");

        in = 8'h01; ctrl = 3'd7;
        #10;
        check("B: 01 shift 7");

        in = 8'h7F; ctrl = 3'd7;
        #10;
        check("B: 7F shift 7");

        // B3: Shift by 1 for various inputs
        in = 8'hFF; ctrl = 3'd1;
        #10;
        check("B: FF shift 1");

        in = 8'h01; ctrl = 3'd1;
        #10;
        check("B: 01 shift 1");

        in = 8'h02; ctrl = 3'd1;
        #10;
        check("B: 02 shift 1");

        in = 8'hAA; ctrl = 3'd1;
        #10;
        check("B: AA shift 1");

        // B4: All-ones input with all shift amounts
        for (i = 0; i < 8; i = i + 1) begin
            in = 8'hFF; ctrl = i[2:0];
            #10;
            check("B: FF all shifts");
        end

        // B5: Single-bit input (power of 2) with all shift amounts
        for (i = 0; i < 8; i = i + 1) begin
            in = 8'h01; ctrl = i[2:0];
            #10;
            check("B: 01 all shifts");
        end

        // B6: MSB-only input with all shift amounts
        for (i = 0; i < 8; i = i + 1) begin
            in = 8'h80; ctrl = i[2:0];
            #10;
            check("B: 80 all shifts");
        end

        // B7: Alternating bits
        in = 8'hAA; ctrl = 3'd0;
        #10;
        check("B: AA shift 0");
        in = 8'hAA; ctrl = 3'd1;
        #10;
        check("B: AA shift 1 = 55");
        in = 8'h55; ctrl = 3'd1;
        #10;
        check("B: 55 shift 1");
        in = 8'hAA; ctrl = 3'd4;
        #10;
        check("B: AA shift 4");
        in = 8'h55; ctrl = 3'd4;
        #10;
        check("B: 55 shift 4");

        // B8: All zeros with all shifts
        for (i = 0; i < 8; i = i + 1) begin
            in = 8'h00; ctrl = i[2:0];
            #10;
            check("B: 00 all shifts");
        end

        // =============================================
        // Group C: Randomized stress tests
        // =============================================
        for (i = 0; i < 30; i = i + 1) begin
            in = $random(seed);
            ctrl = $random(seed);
            #10;
            check("C: random");
        end

        // =============================================
        // Group D: Protocol/timing edge cases
        // =============================================

        // D1: Rapid input changes
        for (i = 0; i < 8; i = i + 1) begin
            in = (8'h01 << i);
            ctrl = 3'd3;
            #5;
            check("D: walking 1 shift 3");
        end

        // D2: Rapid ctrl changes with fixed input
        in = 8'hC3;
        for (i = 0; i < 8; i = i + 1) begin
            ctrl = i[2:0];
            #5;
            check("D: C3 all ctrl");
        end

        // D3: Simultaneous input and ctrl changes
        for (i = 0; i < 8; i = i + 1) begin
            in = ~(8'h01 << i);
            ctrl = i[2:0];
            #5;
            check("D: walking 0 shift i");
        end

        // D4: Back-to-back same values
        in = 8'hDE; ctrl = 3'd5;
        #10;
        check("D: DE shift 5 first");
        #10;
        check("D: DE shift 5 repeat");
        #10;
        check("D: DE shift 5 repeat2");

        // D5: Transition from max to min and back
        in = 8'hFF; ctrl = 3'd7;
        #10;
        check("D: max in max ctrl");
        in = 8'h00; ctrl = 3'd0;
        #10;
        check("D: min in min ctrl");
        in = 8'hFF; ctrl = 3'd0;
        #10;
        check("D: max in min ctrl");
        in = 8'h00; ctrl = 3'd7;
        #10;
        check("D: min in max ctrl");

        // =============================================
        // Score Reporting
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
// Golden reference: mux2X1
// =============================================
module golden_mux2X1(in0, in1, sel, out);
    input in0, in1;
    input sel;
    output out;
    assign out = (sel) ? in1 : in0;
endmodule

// =============================================
// Golden reference: barrel_shifter
// =============================================
module golden_barrel_shifter(in, ctrl, out);
    input  [7:0] in;
    input  [2:0] ctrl;
    output [7:0] out;
    wire [7:0] x, y;

    // 4-bit shift right
    golden_mux2X1 g_ins_17 (.in0(in[7]), .in1(1'b0),  .sel(ctrl[2]), .out(x[7]));
    golden_mux2X1 g_ins_16 (.in0(in[6]), .in1(1'b0),  .sel(ctrl[2]), .out(x[6]));
    golden_mux2X1 g_ins_15 (.in0(in[5]), .in1(1'b0),  .sel(ctrl[2]), .out(x[5]));
    golden_mux2X1 g_ins_14 (.in0(in[4]), .in1(1'b0),  .sel(ctrl[2]), .out(x[4]));
    golden_mux2X1 g_ins_13 (.in0(in[3]), .in1(in[7]), .sel(ctrl[2]), .out(x[3]));
    golden_mux2X1 g_ins_12 (.in0(in[2]), .in1(in[6]), .sel(ctrl[2]), .out(x[2]));
    golden_mux2X1 g_ins_11 (.in0(in[1]), .in1(in[5]), .sel(ctrl[2]), .out(x[1]));
    golden_mux2X1 g_ins_10 (.in0(in[0]), .in1(in[4]), .sel(ctrl[2]), .out(x[0]));

    // 2-bit shift right
    golden_mux2X1 g_ins_27 (.in0(x[7]), .in1(1'b0),  .sel(ctrl[1]), .out(y[7]));
    golden_mux2X1 g_ins_26 (.in0(x[6]), .in1(1'b0),  .sel(ctrl[1]), .out(y[6]));
    golden_mux2X1 g_ins_25 (.in0(x[5]), .in1(x[7]),   .sel(ctrl[1]), .out(y[5]));
    golden_mux2X1 g_ins_24 (.in0(x[4]), .in1(x[6]),   .sel(ctrl[1]), .out(y[4]));
    golden_mux2X1 g_ins_23 (.in0(x[3]), .in1(x[5]),   .sel(ctrl[1]), .out(y[3]));
    golden_mux2X1 g_ins_22 (.in0(x[2]), .in1(x[4]),   .sel(ctrl[1]), .out(y[2]));
    golden_mux2X1 g_ins_21 (.in0(x[1]), .in1(x[3]),   .sel(ctrl[1]), .out(y[1]));
    golden_mux2X1 g_ins_20 (.in0(x[0]), .in1(x[2]),   .sel(ctrl[1]), .out(y[0]));

    // 1-bit shift right
    golden_mux2X1 g_ins_07 (.in0(y[7]), .in1(1'b0),  .sel(ctrl[0]), .out(out[7]));
    golden_mux2X1 g_ins_06 (.in0(y[6]), .in1(y[7]),   .sel(ctrl[0]), .out(out[6]));
    golden_mux2X1 g_ins_05 (.in0(y[5]), .in1(y[6]),   .sel(ctrl[0]), .out(out[5]));
    golden_mux2X1 g_ins_04 (.in0(y[4]), .in1(y[5]),   .sel(ctrl[0]), .out(out[4]));
    golden_mux2X1 g_ins_03 (.in0(y[3]), .in1(y[4]),   .sel(ctrl[0]), .out(out[3]));
    golden_mux2X1 g_ins_02 (.in0(y[2]), .in1(y[3]),   .sel(ctrl[0]), .out(out[2]));
    golden_mux2X1 g_ins_01 (.in0(y[1]), .in1(y[2]),   .sel(ctrl[0]), .out(out[1]));
    golden_mux2X1 g_ins_00 (.in0(y[0]), .in1(y[1]),   .sel(ctrl[0]), .out(out[0]));

endmodule
