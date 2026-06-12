`timescale 1ns/1ps

module testbench_enhanced;

    // Signal declarations
    reg clk;
    reg rst_n;
    reg [3:0] d;
    wire valid_out, dout;
    wire valid_out_ref, dout_ref;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i, j;

    // DUT instantiation
    parallel2serial uut (
        .clk(clk),
        .rst_n(rst_n),
        .d(d),
        .valid_out(valid_out),
        .dout(dout)
    );

    // Golden reference instantiation
    golden_parallel2serial ref_model (
        .clk(clk),
        .rst_n(rst_n),
        .d(d),
        .valid_out(valid_out_ref),
        .dout(dout_ref)
    );

    // Clock generation: 10ns period
    initial clk = 0;
    always #5 clk = ~clk;

    // Check task
    task check;
        input [255:0] test_name;
        begin
            check_id = check_id + 1;
            total_checks = total_checks + 1;
            if (valid_out !== valid_out_ref || dout !== dout_ref) begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL %0s | DUT valid=%b dout=%b, REF valid=%b dout=%b at time %0t",
                    check_id, test_name, valid_out, dout, valid_out_ref, dout_ref, $time);
            end else begin
                passed_checks = passed_checks + 1;
            end
        end
    endtask

    // Watchdog
    initial begin
        #5000000;
        $display("[FORGE_RESULT] TIMEOUT");
        $finish;
    end

    // Main test stimulus
    initial begin
        // =============================================
        // Group A: Original testbench cases
        // =============================================
        rst_n = 0;
        d = 4'b0;
        @(posedge clk); #1;
        check("A: reset state");

        rst_n = 1;
        @(posedge clk); #1;
        check("A: after reset release");

        // Wait until valid_out from ref is high (cnt reaches 3)
        d = 4'b1010;
        repeat(4) begin
            @(posedge clk); #1;
            check("A: waiting for valid");
        end

        // After valid, check serial output for next 4 cycles
        d = 4'b1100;
        repeat(4) begin
            @(posedge clk); #1;
            check("A: serial output check");
        end

        // Another data pattern
        d = 4'b0110;
        repeat(4) begin
            @(posedge clk); #1;
            check("A: second pattern check");
        end

        // =============================================
        // Group B: Boundary/corner cases
        // =============================================

        // B1: All zeros
        rst_n = 0;
        @(posedge clk); #1;
        rst_n = 1;
        d = 4'b0000;
        repeat(8) begin
            @(posedge clk); #1;
            check("B: all zeros");
        end

        // B2: All ones
        rst_n = 0;
        @(posedge clk); #1;
        rst_n = 1;
        d = 4'b1111;
        repeat(8) begin
            @(posedge clk); #1;
            check("B: all ones");
        end

        // B3: Single bit patterns
        rst_n = 0;
        @(posedge clk); #1;
        rst_n = 1;
        d = 4'b1000;
        repeat(4) begin
            @(posedge clk); #1;
            check("B: single MSB");
        end
        d = 4'b0001;
        repeat(4) begin
            @(posedge clk); #1;
            check("B: single LSB");
        end

        // B4: Reset mid-conversion
        rst_n = 0;
        @(posedge clk); #1;
        rst_n = 1;
        d = 4'b1010;
        repeat(4) begin
            @(posedge clk); #1;
        end
        // Now in middle of conversion
        d = 4'b1100;
        @(posedge clk); #1;
        check("B: mid conversion 1");
        @(posedge clk); #1;
        check("B: mid conversion 2");
        // Reset mid-way
        rst_n = 0;
        @(posedge clk); #1;
        check("B: reset mid conversion");
        rst_n = 1;
        @(posedge clk); #1;
        check("B: resume after mid-reset");

        // B5: Changing d during conversion
        rst_n = 0;
        @(posedge clk); #1;
        rst_n = 1;
        d = 4'b1111;
        repeat(4) begin
            @(posedge clk); #1;
            check("B: setup for d change");
        end
        d = 4'b0101;
        @(posedge clk); #1;
        check("B: new d loaded");
        d = 4'b1010;  // change d while not at cnt=3
        @(posedge clk); #1;
        check("B: d changed mid-serial 1");
        @(posedge clk); #1;
        check("B: d changed mid-serial 2");
        @(posedge clk); #1;
        check("B: d changed mid-serial 3");

        // =============================================
        // Group C: Randomized stress tests
        // =============================================
        rst_n = 0;
        @(posedge clk); #1;
        rst_n = 1;

        for (i = 0; i < 20; i = i + 1) begin
            d = $random(seed);
            if (($random(seed) % 15) < 1) begin
                rst_n = 0;
                @(posedge clk); #1;
                check("C: random reset");
                rst_n = 1;
            end
            @(posedge clk); #1;
            check("C: random data");
        end

        // =============================================
        // Group D: Protocol/timing tests
        // =============================================

        // D1: Full conversion cycle verification
        rst_n = 0;
        @(posedge clk); #1;
        rst_n = 1;
        d = 4'b1001;
        // Run through multiple complete 4-cycle conversions
        for (i = 0; i < 16; i = i + 1) begin
            @(posedge clk); #1;
            check("D: full conversion cycle");
        end

        // D2: Alternating patterns
        rst_n = 0;
        @(posedge clk); #1;
        rst_n = 1;
        for (i = 0; i < 4; i = i + 1) begin
            d = (i % 2 == 0) ? 4'b1010 : 4'b0101;
            repeat(4) begin
                @(posedge clk); #1;
                check("D: alternating pattern");
            end
        end

        // D3: Multiple resets
        for (i = 0; i < 3; i = i + 1) begin
            rst_n = 0;
            @(posedge clk); #1;
            check("D: multi reset cycle");
            rst_n = 1;
            d = 4'b1100;
            repeat(3) begin
                @(posedge clk); #1;
                check("D: after multi reset");
            end
        end

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
// Golden reference model
// =============================================
module golden_parallel2serial(
	input wire clk  ,
	input wire rst_n  ,
	input wire [3:0]d ,
	output wire valid_out ,
	output wire dout
	);

reg [3:0] data = 'd0;
reg [1:0]cnt;
reg valid;
assign dout = data[3];
assign valid_out =valid;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        data<= 'd0;
        cnt <= 'd0;
        valid <= 'd0;
    end
    else  begin

		if (cnt == 'd3) begin
			data <= d;
			cnt <= 'd0;
			valid <= 1;
		end
		else begin
			cnt <= cnt + 'd1;
			valid <= 0;
			data  <= {data[2:0],data[3]};
		end
    end

end

endmodule
