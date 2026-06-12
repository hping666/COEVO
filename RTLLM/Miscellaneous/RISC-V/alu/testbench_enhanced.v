`timescale 1ns/1ps

module testbench_enhanced;

    // Signal declarations
    reg [31:0] a, b;
    reg [5:0] aluc;
    wire [31:0] r;
    wire zero, carry, negative, overflow, flag;

    // Golden reference outputs
    wire [31:0] r_ref;
    wire zero_ref, carry_ref, negative_ref, overflow_ref, flag_ref;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // Opcode parameters
    parameter ADD  = 6'b100000;
    parameter ADDU = 6'b100001;
    parameter SUB  = 6'b100010;
    parameter SUBU = 6'b100011;
    parameter AND_ = 6'b100100;
    parameter OR_  = 6'b100101;
    parameter XOR_ = 6'b100110;
    parameter NOR_ = 6'b100111;
    parameter SLT  = 6'b101010;
    parameter SLTU = 6'b101011;
    parameter SLL  = 6'b000000;
    parameter SRL  = 6'b000010;
    parameter SRA  = 6'b000011;
    parameter SLLV = 6'b000100;
    parameter SRLV = 6'b000110;
    parameter SRAV = 6'b000111;
    parameter LUI  = 6'b001111;

    // DUT instantiation
    alu uut (
        .a(a), .b(b), .aluc(aluc),
        .r(r), .zero(zero), .carry(carry),
        .negative(negative), .overflow(overflow), .flag(flag)
    );

    // Golden reference instantiation
    golden_alu ref_model (
        .a(a), .b(b), .aluc(aluc),
        .r(r_ref), .zero(zero_ref), .carry(carry_ref),
        .negative(negative_ref), .overflow(overflow_ref), .flag(flag_ref)
    );

    // Check task
    task check_outputs;
        input [31:0] test_id_val;
        begin
            check_id = check_id + 1;
            // Check r
            total_checks = total_checks + 1;
            if (r === r_ref) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL r: expected=%h actual=%h (a=%h b=%h aluc=%b)", check_id, r_ref, r, a, b, aluc);
            end

            // Check zero
            total_checks = total_checks + 1;
            if (zero === zero_ref) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL zero: expected=%b actual=%b (a=%h b=%h aluc=%b)", check_id, zero_ref, zero, a, b, aluc);
            end

            // Check flag
            total_checks = total_checks + 1;
            if (flag === flag_ref) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL flag: expected=%b actual=%b (a=%h b=%h aluc=%b)", check_id, flag_ref, flag, a, b, aluc);
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
        a = 0; b = 0; aluc = 0;
        #5;

        // ===================== Group A: Original testbench cases =====================
        a = 32'h0000001c; b = 32'h00000021;
        #5;

        aluc = ADD; #10; check_outputs(0);
        aluc = ADDU; #10; check_outputs(0);
        aluc = SUB; #10; check_outputs(0);
        aluc = SUBU; #10; check_outputs(0);
        aluc = AND_; #10; check_outputs(0);
        aluc = OR_; #10; check_outputs(0);
        aluc = XOR_; #10; check_outputs(0);
        aluc = NOR_; #10; check_outputs(0);
        aluc = SLT; #10; check_outputs(0);
        aluc = SLTU; #10; check_outputs(0);
        aluc = SLL; #10; check_outputs(0);
        aluc = SRL; #10; check_outputs(0);
        aluc = SRA; #10; check_outputs(0);
        aluc = SLLV; #10; check_outputs(0);
        aluc = SRLV; #10; check_outputs(0);
        aluc = SRAV; #10; check_outputs(0);
        aluc = LUI; #10; check_outputs(0);

        // ===================== Group B: Boundary/corner cases =====================

        // B1: Zero operands for each opcode
        a = 32'h00000000; b = 32'h00000000;
        #5;
        aluc = ADD; #10; check_outputs(0);
        aluc = ADDU; #10; check_outputs(0);
        aluc = SUB; #10; check_outputs(0);
        aluc = SUBU; #10; check_outputs(0);
        aluc = AND_; #10; check_outputs(0);
        aluc = OR_; #10; check_outputs(0);
        aluc = XOR_; #10; check_outputs(0);
        aluc = NOR_; #10; check_outputs(0);
        aluc = SLT; #10; check_outputs(0);
        aluc = SLTU; #10; check_outputs(0);
        aluc = SLL; #10; check_outputs(0);
        aluc = SRL; #10; check_outputs(0);
        aluc = SRA; #10; check_outputs(0);
        aluc = SLLV; #10; check_outputs(0);
        aluc = SRLV; #10; check_outputs(0);
        aluc = SRAV; #10; check_outputs(0);
        aluc = LUI; #10; check_outputs(0);

        // B2: Max operands (0xFFFFFFFF)
        a = 32'hFFFFFFFF; b = 32'hFFFFFFFF;
        #5;
        aluc = ADD; #10; check_outputs(0);
        aluc = ADDU; #10; check_outputs(0);
        aluc = SUB; #10; check_outputs(0);
        aluc = SUBU; #10; check_outputs(0);
        aluc = AND_; #10; check_outputs(0);
        aluc = OR_; #10; check_outputs(0);
        aluc = XOR_; #10; check_outputs(0);
        aluc = NOR_; #10; check_outputs(0);
        aluc = SLT; #10; check_outputs(0);
        aluc = SLTU; #10; check_outputs(0);
        aluc = LUI; #10; check_outputs(0);

        // B3: Signed boundaries
        a = 32'h80000000; b = 32'h7FFFFFFF;
        #5;
        aluc = ADD; #10; check_outputs(0);
        aluc = SUB; #10; check_outputs(0);
        aluc = SLT; #10; check_outputs(0);
        aluc = SLTU; #10; check_outputs(0);

        a = 32'h7FFFFFFF; b = 32'h80000000;
        #5;
        aluc = ADD; #10; check_outputs(0);
        aluc = SUB; #10; check_outputs(0);
        aluc = SLT; #10; check_outputs(0);
        aluc = SLTU; #10; check_outputs(0);

        // B4: Shift amounts 0 and 31
        a = 32'h00000000; b = 32'hA5A5A5A5;
        #5;
        aluc = SLL; #10; check_outputs(0);
        aluc = SRL; #10; check_outputs(0);
        aluc = SRA; #10; check_outputs(0);
        aluc = SLLV; #10; check_outputs(0);
        aluc = SRLV; #10; check_outputs(0);
        aluc = SRAV; #10; check_outputs(0);

        a = 32'h0000001F; b = 32'hA5A5A5A5;
        #5;
        aluc = SLL; #10; check_outputs(0);
        aluc = SRL; #10; check_outputs(0);
        aluc = SRA; #10; check_outputs(0);
        aluc = SLLV; #10; check_outputs(0);
        aluc = SRLV; #10; check_outputs(0);
        aluc = SRAV; #10; check_outputs(0);

        // B5: One operand zero
        a = 32'h12345678; b = 32'h00000000;
        #5;
        aluc = ADD; #10; check_outputs(0);
        aluc = SUB; #10; check_outputs(0);
        aluc = OR_; #10; check_outputs(0);
        aluc = AND_; #10; check_outputs(0);

        a = 32'h00000000; b = 32'h12345678;
        #5;
        aluc = ADD; #10; check_outputs(0);
        aluc = SUB; #10; check_outputs(0);
        aluc = OR_; #10; check_outputs(0);
        aluc = AND_; #10; check_outputs(0);

        // ===================== Group C: Randomized stress =====================
        for (i = 0; i < 30; i = i + 1) begin
            a = $random(seed);
            b = $random(seed);
            #5;

            // Cycle through various opcodes
            case (i % 17)
                0: aluc = ADD;
                1: aluc = ADDU;
                2: aluc = SUB;
                3: aluc = SUBU;
                4: aluc = AND_;
                5: aluc = OR_;
                6: aluc = XOR_;
                7: aluc = NOR_;
                8: aluc = SLT;
                9: aluc = SLTU;
                10: aluc = SLL;
                11: aluc = SRL;
                12: aluc = SRA;
                13: aluc = SLLV;
                14: aluc = SRLV;
                15: aluc = SRAV;
                16: aluc = LUI;
            endcase
            #10;
            check_outputs(0);
        end

        // ===================== Group D: Protocol/timing tests =====================

        // D1: Rapid opcode switching with same operands
        a = 32'hDEADBEEF; b = 32'hCAFEBABE;
        #5;
        aluc = ADD; #10; check_outputs(0);
        aluc = SUB; #10; check_outputs(0);
        aluc = AND_; #10; check_outputs(0);
        aluc = OR_; #10; check_outputs(0);
        aluc = XOR_; #10; check_outputs(0);
        aluc = NOR_; #10; check_outputs(0);

        // D2: Operand change with same opcode
        aluc = ADD;
        a = 32'h00000001; b = 32'h00000001; #10; check_outputs(0);
        a = 32'hFFFFFFFF; b = 32'h00000001; #10; check_outputs(0);
        a = 32'h80000000; b = 32'h80000000; #10; check_outputs(0);
        a = 32'h7FFFFFFF; b = 32'h00000001; #10; check_outputs(0);

        // D3: Default opcode test (undefined opcode)
        a = 32'h12345678; b = 32'hABCDEF01;
        aluc = 6'b111111; #10; check_outputs(0);
        aluc = 6'b010101; #10; check_outputs(0);

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
// Golden reference model - copy of verified_alu.v renamed
// ============================================================
module golden_alu(
    input [31:0] a,
    input [31:0] b,
    input [5:0] aluc,
    output [31:0] r,
    output zero,
    output carry,
    output negative,
    output overflow,
    output flag
    );

    parameter ADD = 6'b100000;
    parameter ADDU = 6'b100001;
    parameter SUB = 6'b100010;
    parameter SUBU = 6'b100011;
    parameter AND = 6'b100100;
    parameter OR = 6'b100101;
    parameter XOR = 6'b100110;
    parameter NOR = 6'b100111;
    parameter SLT = 6'b101010;
    parameter SLTU = 6'b101011;
    parameter SLL = 6'b000000;
    parameter SRL = 6'b000010;
    parameter SRA = 6'b000011;
    parameter SLLV = 6'b000100;
    parameter SRLV = 6'b000110;
    parameter SRAV = 6'b000111;
    parameter JR = 6'b001000;
    parameter LUI = 6'b001111;

    wire signed [31:0] a_signed;
    wire signed [31:0] b_signed;

    reg [32:0] res;

    assign a_signed = a;
    assign b_signed = b;
    assign r = res[31:0];

    assign flag = (aluc == SLT || aluc == SLTU) ? ((aluc == SLT) ? (a_signed < b_signed) : (a < b)) : 1'b0;
    assign zero = (res[31:0] == 32'b0) ? 1'b1 : 1'b0;
    assign carry = res[32];
    assign negative = res[31];
    assign overflow = (aluc == ADD || aluc == SUB) ?
        ((aluc == ADD) ? ((a[31] == b[31]) && (res[31] != a[31])) :
                         ((a[31] != b[31]) && (res[31] != a[31]))) : 1'b0;

    always @ (a or b or aluc)
    begin
        case(aluc)
            ADD: begin
                res <= a_signed + b_signed;
            end
            ADDU: begin
                res <= a + b;
            end
            SUB: begin
                res <= a_signed - b_signed;
            end
            SUBU: begin
                res <= a - b;
            end
            AND: begin
                res <= a & b;
            end
            OR: begin
                res <= a | b;
            end
            XOR: begin
                res <= a ^ b;
            end
            NOR: begin
                res <= ~(a | b);
            end
            SLT: begin
                res <= a_signed < b_signed ? 1 : 0;
            end
            SLTU: begin
                res <= a < b ? 1 : 0;
            end
            SLL: begin
                res <= b << a;
            end
            SRL: begin
                res <= b >> a;
            end
            SRA: begin
                res <= b_signed >>> a_signed;
            end
            SLLV: begin
                res <= b << a[4:0];
            end
            SRLV: begin
                res <= b >> a[4:0];
            end
            SRAV: begin
                res <= b_signed >>> a_signed[4:0];
            end
            LUI: begin
                res <= {a[15:0], 16'h0000};
            end
            default:
            begin
                res <= 32'b0;
            end
        endcase
    end
endmodule
