`timescale 1ns/1ps

module testbench_enhanced;

    // Signals
    reg         clk;
    reg         rst;
    reg  [31:0] a;
    reg  [31:0] b;
    wire [31:0] z;
    wire [31:0] z_ref;

    // Test infrastructure
    integer total_checks  = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id      = 0;
    integer seed          = 42;
    integer i;

    // DUT instantiation
    float_multi uut (
        .clk(clk),
        .rst(rst),
        .a(a),
        .b(b),
        .z(z)
    );

    // Golden reference instantiation
    golden_float_multi ref_model (
        .clk(clk),
        .rst(rst),
        .a(a),
        .b(b),
        .z(z_ref)
    );

    // Clock generation: 10ns period
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Check task
    task check;
        input [31:0] dut_out;
        input [31:0] ref_out;
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

    // Task: apply inputs and wait for golden model to finish processing.
    // The golden's free-running counter samples inputs at case(0). We set
    // inputs, then wait for counter to reach 1 (case(0) just ran), then
    // wait 6 more cycles for case(1)..case(6) to complete.
    task apply_and_check;
        input [31:0] in_a;
        input [31:0] in_b;
        begin
            a = in_a;
            b = in_b;
            // Wait for golden to sample inputs: counter==1 means case(0) just executed
            @(posedge clk); #1;
            while (ref_model.counter != 3'd1) begin
                @(posedge clk); #1;
            end
            // Stages 1-6: 6 more posedges
            repeat(6) @(posedge clk);
            #1;
            check(z, z_ref);
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
        // Reset sequence
        rst = 1;
        a = 32'h0;
        b = 32'h0;
        #13;
        rst = 0;
        #3; // align

        // Wait one full pipeline flush to synchronize
        #80;

        // ===== Group A: Original testbench cases =====
        $display("--- Group A: Original testbench cases ---");

        // Original test: 0.3 * 0.3 (from original testbench)
        // a = 0x3E4CCCCD (approximately 0.2), b = same
        // Actually the original uses: 32'b00111110100110011001100110011010 = 0x3E99999A
        apply_and_check(32'h3E99999A, 32'h3E99999A);

        // 1.0 * 1.0
        apply_and_check(32'h3F800000, 32'h3F800000);

        // 2.0 * 3.0
        apply_and_check(32'h40000000, 32'h40400000);

        // 0.5 * 4.0
        apply_and_check(32'h3F000000, 32'h40800000);

        // -1.0 * 1.0
        apply_and_check(32'hBF800000, 32'h3F800000);

        // ===== Group B: Boundary/corner cases =====
        $display("--- Group B: Boundary/corner cases ---");

        // B1: Zero * Zero (+0 * +0)
        apply_and_check(32'h00000000, 32'h00000000);

        // B2: +0 * -0
        apply_and_check(32'h00000000, 32'h80000000);

        // B3: -0 * +0
        apply_and_check(32'h80000000, 32'h00000000);

        // B4: -0 * -0
        apply_and_check(32'h80000000, 32'h80000000);

        // B5: 1.0 * 0
        apply_and_check(32'h3F800000, 32'h00000000);

        // B6: 0 * 1.0
        apply_and_check(32'h00000000, 32'h3F800000);

        // B7: Infinity * 1.0
        apply_and_check(32'h7F800000, 32'h3F800000);

        // B8: 1.0 * Infinity
        apply_and_check(32'h3F800000, 32'h7F800000);

        // B9: Infinity * Infinity
        apply_and_check(32'h7F800000, 32'h7F800000);

        // B10: Infinity * 0 => NaN
        apply_and_check(32'h7F800000, 32'h00000000);

        // B11: 0 * Infinity => NaN
        apply_and_check(32'h00000000, 32'h7F800000);

        // B12: NaN * 1.0
        apply_and_check(32'h7FC00000, 32'h3F800000);

        // B13: 1.0 * NaN
        apply_and_check(32'h3F800000, 32'h7FC00000);

        // B14: NaN * NaN
        apply_and_check(32'h7FC00000, 32'h7FC00000);

        // B15: -Infinity * 1.0
        apply_and_check(32'hFF800000, 32'h3F800000);

        // B16: -Infinity * -1.0
        apply_and_check(32'hFF800000, 32'hBF800000);

        // B17: Largest normal * 1.0
        apply_and_check(32'h7F7FFFFF, 32'h3F800000);

        // B18: Smallest normal * 1.0
        apply_and_check(32'h00800000, 32'h3F800000);

        // B19: -1.0 * -1.0
        apply_and_check(32'hBF800000, 32'hBF800000);

        // B20: Large * Large (overflow to infinity)
        apply_and_check(32'h7F000000, 32'h7F000000);

        // ===== Group C: Randomized stress tests =====
        $display("--- Group C: Randomized stress tests ---");
        for (i = 0; i < 50; i = i + 1) begin
            apply_and_check($random(seed), $random(seed));
        end

        // ===== Group D: Protocol/timing tests =====
        $display("--- Group D: Protocol/timing tests ---");

        // D1: Back-to-back operations
        apply_and_check(32'h40000000, 32'h40000000); // 2.0 * 2.0
        apply_and_check(32'h40400000, 32'h40400000); // 3.0 * 3.0
        apply_and_check(32'h40800000, 32'h40800000); // 4.0 * 4.0

        // D2: Alternating signs
        apply_and_check(32'h3F800000, 32'hBF800000); // 1.0 * -1.0
        apply_and_check(32'hBF800000, 32'h3F800000); // -1.0 * 1.0

        // D3: Small numbers
        apply_and_check(32'h33800000, 32'h33800000); // small * small

        // D4: Mixed large and small
        apply_and_check(32'h7E000000, 32'h00800000); // large * smallest normal

        // D5: Pi-like * e-like
        apply_and_check(32'h40490FDB, 32'h402DF854); // ~3.14159 * ~2.71828

        // D6: Reset in middle and recover
        rst = 1;
        #20;
        rst = 0;
        #80;
        apply_and_check(32'h3F800000, 32'h40000000); // 1.0 * 2.0

        apply_and_check(32'h41200000, 32'h41200000); // 10.0 * 10.0

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
module golden_float_multi(clk, rst, a, b, z);

input clk, rst;
input [31:0] a, b;
output reg [31:0] z;

reg [2:0] counter;

reg [23:0] a_mantissa, b_mantissa, z_mantissa;
reg [9:0] a_exponent, b_exponent, z_exponent;
reg a_sign, b_sign, z_sign;

reg [49:0] product;

reg guard_bit, round_bit, sticky;
reg special_case;

always @(posedge clk or posedge rst) begin
	if(rst)
		counter <= 0;
	else
		counter <= counter + 1;
end

always @(posedge clk) begin
	if (!rst) begin
		case (counter)
			3'd0: begin
				a_mantissa <= a[22:0];
				b_mantissa <= b[22:0];
				a_exponent <= a[30:23] - 127;
				b_exponent <= b[30:23] - 127;
				a_sign <= a[31];
				b_sign <= b[31];
				special_case <= 0;
			end

			3'd1: begin
				if ((a_exponent == 128 && a_mantissa != 0) || (b_exponent == 128 && b_mantissa != 0)) begin
					z[31] <= 1;
					z[30:23] <= 255;
					z[22] <= 1;
					z[21:0] <= 0;
					special_case <= 1;
				end
				else if (a_exponent == 128) begin
					z[31] <= a_sign ^ b_sign;
					z[30:23] <= 255;
					z[22:0] <= 0;
					special_case <= 1;
					if (($signed(b_exponent) == -127) && (b_mantissa == 0)) begin
						z[31] <= 1;
						z[30:23] <= 255;
						z[22] <= 1;
						z[21:0] <= 0;
					end
				end
				else if (b_exponent == 128) begin
					z[31] <= a_sign ^ b_sign;
					z[30:23] <= 255;
					z[22:0] <= 0;
					special_case <= 1;
					if (($signed(a_exponent) == -127) && (a_mantissa == 0)) begin
						z[31] <= 1;
						z[30:23] <= 255;
						z[22] <= 1;
						z[21:0] <= 0;
					end
				end
				else if (($signed(a_exponent) == -127) && (a_mantissa == 0)) begin
					z[31] <= a_sign ^ b_sign;
					z[30:23] <= 0;
					z[22:0] <= 0;
					special_case <= 1;
				end
				else if (($signed(b_exponent) == -127) && (b_mantissa == 0)) begin
					z[31] <= a_sign ^ b_sign;
					z[30:23] <= 0;
					z[22:0] <= 0;
					special_case <= 1;
				end
				else begin
					if ($signed(a_exponent) == -127)
						a_exponent <= -126;
					else
						a_mantissa[23] <= 1;

					if ($signed(b_exponent) == -127)
						b_exponent <= -126;
					else
						b_mantissa[23] <= 1;
				end
			end

			3'd2: begin
				if (~a_mantissa[23]) begin
					a_mantissa <= a_mantissa << 1;
					a_exponent <= a_exponent - 1;
				end
				if (~b_mantissa[23]) begin
					b_mantissa <= b_mantissa << 1;
					b_exponent <= b_exponent - 1;
				end
			end

			3'd3: begin
				z_sign <= a_sign ^ b_sign;
				z_exponent <= a_exponent + b_exponent + 1;
				product <= a_mantissa * b_mantissa * 4;
			end

			3'd4: begin
				z_mantissa <= product[49:26];
				guard_bit <= product[25];
				round_bit <= product[24];
				sticky <= (product[23:0] != 0);
			end

			3'd5: begin
				if ($signed(z_exponent) < -126) begin
					z_exponent <= z_exponent + (-126 - $signed(z_exponent));
					z_mantissa <= z_mantissa >> (-126 - $signed(z_exponent));
					guard_bit <= z_mantissa[0];
					round_bit <= guard_bit;
					sticky <= sticky | round_bit;
				end
				else if (z_mantissa[23] == 0) begin
					z_exponent <= z_exponent - 1;
					z_mantissa <= z_mantissa << 1;
					z_mantissa[0] <= guard_bit;
					guard_bit <= round_bit;
					round_bit <= 0;
				end
				else if (guard_bit && (round_bit | sticky | z_mantissa[0])) begin
					z_mantissa <= z_mantissa + 1;
					if (z_mantissa == 24'hffffff)
						z_exponent <= z_exponent + 1;
				end
			end

			3'd6: begin
				if (!special_case) begin
					z[22:0] <= z_mantissa[22:0];
					z[30:23] <= z_exponent[7:0] + 127;
					z[31] <= z_sign;
					if ($signed(z_exponent) == -126 && z_mantissa[23] == 0)
						z[30:23] <= 0;
					if ($signed(z_exponent) > 127) begin
						z[22:0] <= 0;
						z[30:23] <= 255;
						z[31] <= z_sign;
					end
				end
			end

			default: begin
			end
		endcase
	end
end

endmodule
