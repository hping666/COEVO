`timescale 1ns/1ps

module testbench_enhanced;

    // Parameters
    parameter Q = 15;
    parameter N = 32;

    // Signals
    reg  [N-1:0] a;
    reg  [N-1:0] b;
    wire [N-1:0] c;
    wire [N-1:0] c_ref;

    // Test infrastructure
    integer total_checks  = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id      = 0;
    integer seed          = 42;
    integer i;

    // DUT instantiation
    fixed_point_subtractor #(.Q(Q), .N(N)) uut (
        .a(a),
        .b(b),
        .c(c)
    );

    // Golden reference instantiation
    golden_fixed_point_subtractor #(.Q(Q), .N(N)) ref_model (
        .a(a),
        .b(b),
        .c(c_ref)
    );

    // Check task
    task check;
        input [N-1:0] dut_out;
        input [N-1:0] ref_out;
        begin
            total_checks = total_checks + 1;
            check_id = check_id + 1;
            if (dut_out === ref_out) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL: a=%h b=%h DUT=%h REF=%h", check_id, a, b, dut_out, ref_out);
            end
        end
    endtask

    // Watchdog
    initial begin
        #5000000;
        $display("[FORGE_RESULT] TIMEOUT");
        $finish;
    end

    // Main test sequence
    initial begin

        // ===== Group A: Original testbench cases (basic random) =====
        $display("--- Group A: Original testbench cases ---");
        for (i = 0; i < 5; i = i + 1) begin
            a = $random(seed);
            b = $random(seed);
            #10;
            check(c, c_ref);
        end

        // ===== Group B: Boundary/corner cases =====
        $display("--- Group B: Boundary/corner cases ---");

        // B1: Both zero
        a = {N{1'b0}};
        b = {N{1'b0}};
        #10; check(c, c_ref);

        // B2: a=0, b positive
        a = {N{1'b0}};
        b = {1'b0, {(N-1){1'b1}}};
        #10; check(c, c_ref);

        // B3: a positive, b=0
        a = {1'b0, {(N-1){1'b1}}};
        b = {N{1'b0}};
        #10; check(c, c_ref);

        // B4: a - b where a > b, both positive
        a = {1'b0, 31'h7000_0000};
        b = {1'b0, 31'h3000_0000};
        #10; check(c, c_ref);

        // B5: a - b where a < b, both positive
        a = {1'b0, 31'h3000_0000};
        b = {1'b0, 31'h7000_0000};
        #10; check(c, c_ref);

        // B6: a == b, both positive
        a = {1'b0, 31'h5555_5555};
        b = {1'b0, 31'h5555_5555};
        #10; check(c, c_ref);

        // B7: Both negative, a > b magnitude
        a = {1'b1, 31'h7000_0000};
        b = {1'b1, 31'h3000_0000};
        #10; check(c, c_ref);

        // B8: Both negative, a < b magnitude
        a = {1'b1, 31'h3000_0000};
        b = {1'b1, 31'h7000_0000};
        #10; check(c, c_ref);

        // B9: Both negative, equal magnitude
        a = {1'b1, 31'h5555_5555};
        b = {1'b1, 31'h5555_5555};
        #10; check(c, c_ref);

        // B10: Positive - Negative (a positive, b negative), a mag > b mag
        a = {1'b0, 31'h7000_0000};
        b = {1'b1, 31'h3000_0000};
        #10; check(c, c_ref);

        // B11: Positive - Negative, a mag < b mag
        a = {1'b0, 31'h3000_0000};
        b = {1'b1, 31'h7000_0000};
        #10; check(c, c_ref);

        // B12: Negative - Positive, a mag > b mag
        a = {1'b1, 31'h7000_0000};
        b = {1'b0, 31'h3000_0000};
        #10; check(c, c_ref);

        // B13: Negative - Positive, a mag < b mag
        a = {1'b1, 31'h3000_0000};
        b = {1'b0, 31'h7000_0000};
        #10; check(c, c_ref);

        // B14: Max positive - max positive
        a = {1'b0, {(N-1){1'b1}}};
        b = {1'b0, {(N-1){1'b1}}};
        #10; check(c, c_ref);

        // B15: Max negative - max negative
        a = {1'b1, {(N-1){1'b1}}};
        b = {1'b1, {(N-1){1'b1}}};
        #10; check(c, c_ref);

        // B16: Max positive - max negative
        a = {1'b0, {(N-1){1'b1}}};
        b = {1'b1, {(N-1){1'b1}}};
        #10; check(c, c_ref);

        // B17: Max negative - max positive
        a = {1'b1, {(N-1){1'b1}}};
        b = {1'b0, {(N-1){1'b1}}};
        #10; check(c, c_ref);

        // B18: Small positive - small negative
        a = 32'h0000_0001;
        b = 32'h8000_0001;
        #10; check(c, c_ref);

        // B19: Negative zero
        a = 32'h8000_0000;
        b = 32'h0000_0000;
        #10; check(c, c_ref);

        // B20: Both negative zero
        a = 32'h8000_0000;
        b = 32'h8000_0000;
        #10; check(c, c_ref);

        // ===== Group C: Randomized stress tests =====
        $display("--- Group C: Randomized stress tests ---");
        for (i = 0; i < 60; i = i + 1) begin
            a = $random(seed);
            b = $random(seed);
            #10;
            check(c, c_ref);
        end

        // ===== Group D: Additional directed tests =====
        $display("--- Group D: Additional directed tests ---");

        // D1: Alternating bit patterns
        a = 32'h5555_5555;
        b = 32'hAAAA_AAAA;
        #10; check(c, c_ref);

        a = 32'hAAAA_AAAA;
        b = 32'h5555_5555;
        #10; check(c, c_ref);

        // D2: One bit differences
        a = 32'h0000_0002;
        b = 32'h0000_0001;
        #10; check(c, c_ref);

        a = 32'h0000_0001;
        b = 32'h0000_0002;
        #10; check(c, c_ref);

        // D3: Powers of 2
        a = 32'h0000_8000;
        b = 32'h0000_4000;
        #10; check(c, c_ref);

        a = 32'h8000_8000;
        b = 32'h8000_4000;
        #10; check(c, c_ref);

        // D4: Fractional boundary
        a = 32'h0000_7FFF;
        b = 32'h0000_7FFF;
        #10; check(c, c_ref);

        a = 32'h0000_7FFF;
        b = 32'h8000_7FFF;
        #10; check(c, c_ref);

        // D5: Large positive - small negative
        a = 32'h7FFF_FFFF;
        b = 32'h8000_0001;
        #10; check(c, c_ref);

        // D6: Small positive - large negative
        a = 32'h0000_0001;
        b = 32'h8FFF_FFFF;
        #10; check(c, c_ref);

        // ===== Score Reporting =====
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
// Golden Reference Model
// ============================================================
module golden_fixed_point_subtractor #(
	parameter Q = 15,
	parameter N = 32
	)
	(
    input [N-1:0] a,
    input [N-1:0] b,
    output [N-1:0] c
    );

reg [N-1:0] res;

assign c = res;

always @(a,b) begin
	// both negative or both positive
	if(a[N-1] == b[N-1]) begin
		if (a[N-2:0] >= b[N-2:0]) begin
			res[N-2:0] = a[N-2:0] - b[N-2:0];
			res[N-1] = a[N-1];
		end else begin
			res[N-2:0] = b[N-2:0] - a[N-2:0];
			res[N-1] = ~a[N-1];
		end
		if (res[N-2:0] == 0) res[N-1] = 0;
		end
	//	one of them is negative
	else if(a[N-1] == 0 && b[N-1] == 1) begin
		if( a[N-2:0] > b[N-2:0] ) begin
			res[N-2:0] = a[N-2:0] + b[N-2:0];
			res[N-1] = 0;
			end
		else begin
			res[N-2:0] = b[N-2:0] + a[N-2:0];
			res[N-1] = 0;
			end
		end
	else begin
		if( a[N-2:0] > b[N-2:0] ) begin
			res[N-2:0] = a[N-2:0] + b[N-2:0];
			if (res[N-2:0] == 0)
				res[N-1] = 0;
			else
				res[N-1] = 1;
			end
		else begin
			res[N-2:0] = b[N-2:0] + a[N-2:0];
			if (res[N-2:0] == 0)
				res[N-1] = 0;
			else
				res[N-1] = 1;
			end
		end
	end
endmodule
