`timescale 1ns/1ps

module testbench_enhanced;

    // Signal declarations
    reg clk;
    reg rst_n;
    reg a;
    wire rise, down;
    wire rise_ref, down_ref;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // DUT instantiation
    edge_detect uut (
        .clk(clk),
        .rst_n(rst_n),
        .a(a),
        .rise(rise),
        .down(down)
    );

    // Golden reference instantiation
    golden_edge_detect ref_model (
        .clk(clk),
        .rst_n(rst_n),
        .a(a),
        .rise(rise_ref),
        .down(down_ref)
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
            if (rise !== rise_ref || down !== down_ref) begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL %0s | DUT rise=%b down=%b, REF rise=%b down=%b at time %0t",
                    check_id, test_name, rise, down, rise_ref, down_ref, $time);
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
        rst_n = 1;
        a = 0;
        @(posedge clk); #1;
        check("A: initial no edge");

        // No edge - a stays 0
        a = 0;
        @(posedge clk); #1;
        check("A: no edge a=0");
        @(posedge clk); #1;
        check("A: no edge a=0 cont");

        // Rising edge: a goes 0->1
        a = 1;
        @(posedge clk); #1;
        check("A: rising edge detected");
        @(posedge clk); #1;
        check("A: after rising edge");

        // Falling edge: a goes 1->0
        a = 0;
        @(posedge clk); #1;
        check("A: falling edge detected");
        @(posedge clk); #1;
        check("A: after falling edge");

        // Reset test
        rst_n = 0;
        @(posedge clk); #1;
        check("A: during reset");
        rst_n = 1;
        @(posedge clk); #1;
        check("A: after reset release");

        // =============================================
        // Group B: Boundary/corner cases
        // =============================================

        // B1: Rising edge immediately after reset
        rst_n = 0;
        a = 0;
        @(posedge clk); #1;
        check("B: reset with a=0");
        rst_n = 1;
        a = 1;
        @(posedge clk); #1;
        check("B: rising edge right after reset");
        @(posedge clk); #1;
        check("B: after rising post-reset");

        // B2: Falling edge right after reset
        rst_n = 0;
        a = 1;
        @(posedge clk); #1;
        check("B: reset with a=1");
        rst_n = 1;
        a = 0;
        @(posedge clk); #1;
        check("B: falling edge right after reset");

        // B3: No change - a stays high
        a = 1;
        @(posedge clk); #1;
        check("B: no change a=1 cycle1");
        @(posedge clk); #1;
        check("B: no change a=1 cycle2");
        @(posedge clk); #1;
        check("B: no change a=1 cycle3");

        // B4: No change - a stays low
        a = 0;
        @(posedge clk); #1;
        check("B: falling from 1 to 0");
        @(posedge clk); #1;
        check("B: no change a=0 cycle1");
        @(posedge clk); #1;
        check("B: no change a=0 cycle2");

        // B5: Rapid toggles
        a = 1;
        @(posedge clk); #1;
        check("B: toggle up 1");
        a = 0;
        @(posedge clk); #1;
        check("B: toggle down 1");
        a = 1;
        @(posedge clk); #1;
        check("B: toggle up 2");
        a = 0;
        @(posedge clk); #1;
        check("B: toggle down 2");
        a = 1;
        @(posedge clk); #1;
        check("B: toggle up 3");
        a = 0;
        @(posedge clk); #1;
        check("B: toggle down 3");

        // B6: Reset during rising edge detection
        a = 0;
        @(posedge clk); #1;
        a = 1;
        rst_n = 0;
        @(posedge clk); #1;
        check("B: reset during rising");
        rst_n = 1;
        @(posedge clk); #1;
        check("B: after reset during rising");

        // B7: Reset during falling edge detection
        a = 1;
        @(posedge clk); #1;
        check("B: a=1 before falling reset test");
        a = 0;
        rst_n = 0;
        @(posedge clk); #1;
        check("B: reset during falling");
        rst_n = 1;
        @(posedge clk); #1;
        check("B: after reset during falling");

        // =============================================
        // Group C: Randomized stress tests
        // =============================================
        rst_n = 1;
        a = 0;
        @(posedge clk); #1;

        for (i = 0; i < 30; i = i + 1) begin
            a = $random(seed) % 2;
            if (($random(seed) % 20) < 1) begin
                rst_n = 0;
                @(posedge clk); #1;
                check("C: random with reset");
                rst_n = 1;
            end
            @(posedge clk); #1;
            check("C: random stimulus");
        end

        // =============================================
        // Group D: Protocol/timing tests
        // =============================================

        // D1: Single pulse on 'a' (0->1->0)
        rst_n = 1;
        a = 0;
        @(posedge clk); #1;
        check("D: before pulse a=0");
        a = 1;
        @(posedge clk); #1;
        check("D: pulse rise");
        a = 0;
        @(posedge clk); #1;
        check("D: pulse fall");
        @(posedge clk); #1;
        check("D: after pulse");

        // D2: Long high period then fall
        a = 1;
        @(posedge clk); #1;
        check("D: long high start");
        for (i = 0; i < 5; i = i + 1) begin
            @(posedge clk); #1;
            check("D: long high hold");
        end
        a = 0;
        @(posedge clk); #1;
        check("D: fall after long high");

        // D3: Long low period then rise
        for (i = 0; i < 5; i = i + 1) begin
            @(posedge clk); #1;
            check("D: long low hold");
        end
        a = 1;
        @(posedge clk); #1;
        check("D: rise after long low");

        // D4: Multiple consecutive rising/falling checks
        a = 0;
        @(posedge clk); #1;
        check("D: fall for next rise test");
        a = 1;
        @(posedge clk); #1;
        check("D: consecutive rise 1");
        a = 0;
        @(posedge clk); #1;
        check("D: consecutive fall 1");
        a = 1;
        @(posedge clk); #1;
        check("D: consecutive rise 2");
        a = 0;
        @(posedge clk); #1;
        check("D: consecutive fall 2");

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
module golden_edge_detect(
	input clk,
	input rst_n,
	input a,

	output reg rise,
	output reg down
);
	reg a0;
    always@(posedge clk or negedge rst_n) begin
        if(~rst_n) begin
            rise <= 1'b0;
            down <= 1'b0;
        end
        else begin
            if(a & ~a0) begin
                rise <= 1;
                down <= 0;
            end
            else if (~a & a0) begin
                rise <= 0;
                down <= 1;
            end else begin
                rise <= 0;
                down <= 0;
            end
        end
    end

    always@(posedge clk or negedge rst_n) begin
        if(~rst_n)
            a0 <= 0;
        else
            a0 <= a;
    end
endmodule
