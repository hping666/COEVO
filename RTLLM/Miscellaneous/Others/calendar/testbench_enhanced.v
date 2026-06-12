`timescale 1ns/1ps

module testbench_enhanced;

    // Signal declarations
    reg CLK;
    reg RST;
    wire [5:0] Hours, Mins, Secs;
    wire [5:0] Hours_ref, Mins_ref, Secs_ref;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // DUT instantiation
    calendar uut (
        .CLK(CLK),
        .RST(RST),
        .Hours(Hours),
        .Mins(Mins),
        .Secs(Secs)
    );

    // Golden reference instantiation
    golden_calendar ref_model (
        .CLK(CLK),
        .RST(RST),
        .Hours(Hours_ref),
        .Mins(Mins_ref),
        .Secs(Secs_ref)
    );

    // Clock generation: 10ns period
    initial CLK = 0;
    always #5 CLK = ~CLK;

    // Check task
    task check;
        input [255:0] test_name;
        begin
            check_id = check_id + 1;
            total_checks = total_checks + 1;
            if (Hours !== Hours_ref || Mins !== Mins_ref || Secs !== Secs_ref) begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL %0s | DUT H=%0d M=%0d S=%0d, REF H=%0d M=%0d S=%0d at time %0t",
                    check_id, test_name, Hours, Mins, Secs, Hours_ref, Mins_ref, Secs_ref, $time);
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
        // Group A: Original testbench cases - basic reset and counting
        // =============================================
        RST = 1;
        @(posedge CLK); #1;
        check("A: reset state");
        @(posedge CLK); #1;
        check("A: still in reset");

        RST = 0;
        // Run for 65 clock cycles to see seconds wrap
        for (i = 0; i < 65; i = i + 1) begin
            @(posedge CLK); #1;
            check("A: seconds counting");
        end

        // =============================================
        // Group B: Boundary/corner cases
        // =============================================

        // B1: Reset and verify initial state
        RST = 1;
        @(posedge CLK); #1;
        check("B: reset clears all");
        RST = 0;

        // B2: Run exactly to second 59 then check wrap
        // After reset, Secs=0. Run 59 cycles to get to Secs=59
        for (i = 0; i < 58; i = i + 1) begin
            @(posedge CLK); #1;
        end
        check("B: at Secs=58");
        @(posedge CLK); #1;
        check("B: at Secs=59");
        @(posedge CLK); #1;
        check("B: Secs wraps to 0, Mins increments");

        // B3: Run to minute boundary (need 59 more minutes worth of seconds from Mins=1,Secs=0)
        // Instead, reset and fast-forward carefully
        RST = 1;
        @(posedge CLK); #1;
        RST = 0;

        // Run for 60*60 = 3600 cycles to go from 00:00:00 to 01:00:00
        // That's too many, let's run for 60*2 = 120 to check 2-minute mark
        for (i = 0; i < 120; i = i + 1) begin
            @(posedge CLK); #1;
        end
        check("B: at 2 minutes");

        // B4: Reset mid-counting
        for (i = 0; i < 30; i = i + 1) begin
            @(posedge CLK); #1;
        end
        RST = 1;
        @(posedge CLK); #1;
        check("B: reset mid-count");
        RST = 0;
        @(posedge CLK); #1;
        check("B: resume after reset");

        // B5: Multiple resets in sequence
        RST = 1;
        @(posedge CLK); #1;
        check("B: reset 1");
        RST = 0;
        @(posedge CLK); #1;
        RST = 1;
        @(posedge CLK); #1;
        check("B: reset 2");
        RST = 0;
        @(posedge CLK); #1;
        check("B: after double reset");

        // B6: Run for a few more seconds
        for (i = 0; i < 10; i = i + 1) begin
            @(posedge CLK); #1;
            check("B: post-double-reset counting");
        end

        // =============================================
        // Group C: Randomized stress tests
        // =============================================
        RST = 1;
        @(posedge CLK); #1;
        RST = 0;

        for (i = 0; i < 30; i = i + 1) begin
            if (($random(seed) % 10) < 1) begin
                RST = 1;
                @(posedge CLK); #1;
                check("C: random reset");
                RST = 0;
            end
            @(posedge CLK); #1;
            check("C: random running");
        end

        // =============================================
        // Group D: Protocol/timing - day transitions, hour boundaries
        // =============================================

        // D1: Run through a full hour transition
        // Reset and run 3600 cycles (1 hour)
        RST = 1;
        @(posedge CLK); #1;
        RST = 0;

        // Run 3595 cycles to get to 00:59:55
        for (i = 0; i < 3595; i = i + 1) begin
            @(posedge CLK); #1;
        end
        // Now check the last 10 seconds around the hour boundary
        for (i = 0; i < 10; i = i + 1) begin
            @(posedge CLK); #1;
            check("D: around hour boundary");
        end

        // D2: Continue running to verify hour incremented
        for (i = 0; i < 5; i = i + 1) begin
            @(posedge CLK); #1;
            check("D: after hour boundary");
        end

        // D3: Run through a minute boundary more carefully
        RST = 1;
        @(posedge CLK); #1;
        RST = 0;
        for (i = 0; i < 55; i = i + 1) begin
            @(posedge CLK); #1;
        end
        for (i = 0; i < 10; i = i + 1) begin
            @(posedge CLK); #1;
            check("D: around minute boundary");
        end

        // D4: Verify day rollover (23:59:59 -> 00:00:00)
        // Run 24*3600 - 1 = 86399 cycles total from reset
        // We already ran 65 + some, let's just reset and run a shorter sequence
        // Just verify the counter keeps going correctly over many cycles
        RST = 1;
        @(posedge CLK); #1;
        RST = 0;
        for (i = 0; i < 200; i = i + 1) begin
            @(posedge CLK); #1;
        end
        check("D: long run 200 cycles");

        for (i = 0; i < 100; i = i + 1) begin
            @(posedge CLK); #1;
        end
        check("D: long run 300 cycles total");

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
module golden_calendar(CLK,RST,Hours,Mins,Secs);
input CLK,RST;
output [5:0] Hours,Mins,Secs;
reg [5:0] Hours,Mins,Secs;

always@(posedge CLK or posedge RST) begin
	if (RST)
		Secs <= 0;
	else if (Secs == 59)
		Secs <= 0;
	else
		Secs <= Secs + 1;
end

always@(posedge CLK or posedge RST) begin
	if (RST)
		Mins <= 0;
	else if((Mins==59)&&(Secs==59))
		Mins <= 0;
	else if(Secs== 59)
		Mins <= Mins + 1;
	else
		Mins <= Mins;
end

always@(posedge CLK or posedge RST) begin
        if (RST)
                Hours <= 0;
        else if((Hours == 23)&&(Mins==59)&&(Secs==59))
                Hours <= 0;
        else if((Mins == 59)&&(Secs==59))
                Hours <= Hours + 1;
        else
                Hours <= Hours;
end

endmodule
