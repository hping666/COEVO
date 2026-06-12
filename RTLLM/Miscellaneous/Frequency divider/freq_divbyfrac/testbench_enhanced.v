`timescale 1ns/1ps

module testbench_enhanced;

    // Signal declarations
    reg clk;
    reg rst_n;
    wire clk_div;
    wire ref_clk_div;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // DUT instantiation
    freq_divbyfrac uut (
        .clk(clk),
        .rst_n(rst_n),
        .clk_div(clk_div)
    );

    // Golden reference instantiation
    golden_freq_divbyfrac ref_model (
        .clk(clk),
        .rst_n(rst_n),
        .clk_div(ref_clk_div)
    );

    // Clock generation: 10ns period
    initial clk = 1;
    always #5 clk = ~clk;

    // Check task
    task check;
        input [255:0] description;
        begin
            total_checks = total_checks + 1;
            check_id = check_id + 1;
            if (clk_div === ref_clk_div) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL | %0s | expected=%b got=%b | time=%0t", check_id, description, ref_clk_div, clk_div, $time);
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
        // Mimic original: clk=1, rst_n=0, then release after 10ns
        rst_n = 0;
        #10;
        rst_n = 1;
        // Original checks at 5ns intervals from t=15
        #5; // t=15
        check("GroupA: t=15");
        #5; // t=20
        check("GroupA: t=20");
        #5; // t=25
        check("GroupA: t=25");
        #5; // t=30
        check("GroupA: t=30");
        #5; // t=35
        check("GroupA: t=35");
        #5; // t=40
        check("GroupA: t=40");
        #5; // t=45
        check("GroupA: t=45");
        #5; // t=50
        check("GroupA: t=50");
        #5; // t=55
        check("GroupA: t=55");
        #5; // t=60
        check("GroupA: t=60");
        #5; // t=65
        check("GroupA: t=65");
        #5; // t=70
        check("GroupA: t=70");
        #5; // t=75
        check("GroupA: t=75");
        #5; // t=80
        check("GroupA: t=80");
        #5; // t=85
        check("GroupA: t=85");
        #5; // t=90
        check("GroupA: t=90");
        #5; // t=95
        check("GroupA: t=95");
        #5; // t=100
        check("GroupA: t=100");
        #5; // t=105
        check("GroupA: t=105");
        #5; // t=110
        check("GroupA: t=110");

        // =============================================
        // Group B: Boundary/corner cases
        // =============================================

        // B1: Reset behavior - drive reset and check
        rst_n = 0;
        #10;
        check("GroupB: In reset");
        #10;
        check("GroupB: Held in reset");

        rst_n = 1;
        // B2: Run for many cycles to verify 3.5x division pattern
        // With 3.5x, period = 7 half-clocks = 35ns per divided cycle
        // Run for several full divided periods
        for (i = 0; i < 30; i = i + 1) begin
            @(posedge clk); #1;
            check("GroupB: Posedge cycle verify");
            @(negedge clk); #1;
            check("GroupB: Negedge cycle verify");
        end

        // =============================================
        // Group C: Randomized stress tests
        // =============================================
        rst_n = 0;
        #10;
        check("GroupC: Reset for random");
        rst_n = 1;

        for (i = 0; i < 30; i = i + 1) begin
            if (($random(seed) % 20) == 0) begin
                rst_n = 0;
                @(posedge clk); #1;
                check("GroupC: Random reset assert");
                @(negedge clk); #1;
                check("GroupC: Random negedge after reset");
                rst_n = 1;
            end
            @(posedge clk); #1;
            check("GroupC: Random posedge");
        end

        // =============================================
        // Group D: Protocol/timing tests
        // =============================================

        // D1: Reset during operation
        rst_n = 0;
        @(posedge clk); #1;
        check("GroupD: Reset start");
        rst_n = 1;

        for (i = 0; i < 10; i = i + 1) begin
            @(posedge clk); #1;
            check("GroupD: Pre-reset run posedge");
        end

        // Mid-operation reset
        rst_n = 0;
        @(posedge clk); #1;
        check("GroupD: Mid-op reset posedge");
        @(negedge clk); #1;
        check("GroupD: Mid-op reset negedge");
        rst_n = 1;

        for (i = 0; i < 10; i = i + 1) begin
            @(posedge clk); #1;
            check("GroupD: Post-reset posedge");
        end

        // D2: Multiple rapid resets
        for (i = 0; i < 5; i = i + 1) begin
            rst_n = 0;
            @(posedge clk); #1;
            check("GroupD: Rapid rst on");
            rst_n = 1;
            @(posedge clk); #1;
            check("GroupD: Rapid rst off");
        end

        // D3: Long continuous run
        rst_n = 0;
        @(posedge clk); #1;
        rst_n = 1;
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge clk); #1;
            check("GroupD: Long run posedge");
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
module golden_freq_divbyfrac(
    input               rst_n ,
    input               clk,
    output              clk_div
    );

   parameter            MUL2_DIV_CLK = 7 ;
   reg [3:0]            cnt ;
   always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         cnt    <= 'b0 ;
      end
      else if (cnt == MUL2_DIV_CLK-1) begin
         cnt    <= 'b0 ;
      end
      else begin
         cnt    <= cnt + 1'b1 ;
      end
   end

   reg                  clk_ave_r ;
   always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         clk_ave_r <= 1'b0 ;
      end
      else if (cnt == 0) begin
         clk_ave_r <= 1 ;
      end
      else if (cnt == (MUL2_DIV_CLK/2)+1) begin
         clk_ave_r <= 1 ;
      end
      else begin
         clk_ave_r <= 0 ;
      end
   end

   reg                  clk_adjust_r ;
   always @(negedge clk or negedge rst_n) begin
      if (!rst_n) begin
         clk_adjust_r <= 1'b0 ;
      end
      else if (cnt == 1) begin
         clk_adjust_r <= 1 ;
      end
      else if (cnt == (MUL2_DIV_CLK/2)+1 ) begin
         clk_adjust_r <= 1 ;
      end
      else begin
         clk_adjust_r <= 0 ;
      end
   end

   assign clk_div = clk_adjust_r | clk_ave_r ;

endmodule
