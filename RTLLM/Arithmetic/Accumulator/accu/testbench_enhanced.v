`timescale 1ns/1ps

module testbench_enhanced;

    // SECTION 1: Signal declarations
    reg clk;
    reg rst_n;
    reg [7:0] data_in;
    reg valid_in;

    wire valid_out_dut, valid_out_ref;
    wire [9:0] data_out_dut, data_out_ref;

    // SECTION 2: Clock generation
    parameter PERIOD = 10;
    initial clk = 0;
    always #(PERIOD/2) clk = ~clk;

    // SECTION 3: Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // SECTION 4: DUT instantiation
    accu uut (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(data_in),
        .valid_in(valid_in),
        .valid_out(valid_out_dut),
        .data_out(data_out_dut)
    );

    // SECTION 5: Golden reference instantiation
    golden_accu ref_model (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(data_in),
        .valid_in(valid_in),
        .valid_out(valid_out_ref),
        .data_out(data_out_ref)
    );

    // SECTION 6: Check task
    task check_outputs;
        input [255:0] description;
        begin
            check_id = check_id + 1;
            total_checks = total_checks + 1;
            if (valid_out_dut !== valid_out_ref || data_out_dut !== data_out_ref) begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL | %0s | expected valid_out=%b data_out=%0d got valid_out=%b data_out=%0d | time=%0t",
                    check_id, description, valid_out_ref, data_out_ref, valid_out_dut, data_out_dut, $time);
            end else begin
                passed_checks = passed_checks + 1;
            end
        end
    endtask

    // SECTION 7: Watchdog timer
    initial begin
        #5000000;
        $display("[FORGE_RESULT] TIMEOUT");
        $finish;
    end

    // SECTION 8: Test cases
    initial begin
        // Initialize
        rst_n = 0;
        data_in = 0;
        valid_in = 0;

        // Reset
        @(posedge clk); #1;
        @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;

        // ---- Group A: Original testbench cases ----

        // Case A1: First batch {1, 2, 3, 14} => sum=20
        valid_in = 1;
        data_in = 8'd1;
        @(posedge clk); #1;
        check_outputs("A1: after data_in=1 (1st of batch1)");

        data_in = 8'd2;
        @(posedge clk); #1;
        check_outputs("A1: after data_in=2 (2nd of batch1)");

        data_in = 8'd3;
        @(posedge clk); #1;
        check_outputs("A1: after data_in=3 (3rd of batch1)");

        data_in = 8'd14;
        @(posedge clk); #1;
        check_outputs("A1: after data_in=14 (4th of batch1)");

        // Case A2: Second batch {5, 2, 103, 4} => sum=114
        data_in = 8'd5;
        @(posedge clk); #1;
        check_outputs("A2: after data_in=5 (1st of batch2)");

        data_in = 8'd2;
        @(posedge clk); #1;
        check_outputs("A2: after data_in=2 (2nd of batch2)");

        data_in = 8'd103;
        @(posedge clk); #1;
        check_outputs("A2: after data_in=103 (3rd of batch2)");

        data_in = 8'd4;
        @(posedge clk); #1;
        check_outputs("A2: after data_in=4 (4th of batch2)");

        // Case A3: Third batch {5, 6, 3, 54} => sum=68
        data_in = 8'd5;
        @(posedge clk); #1;
        check_outputs("A3: after data_in=5 (1st of batch3)");

        data_in = 8'd6;
        @(posedge clk); #1;
        check_outputs("A3: after data_in=6 (2nd of batch3)");

        data_in = 8'd3;
        @(posedge clk); #1;
        check_outputs("A3: after data_in=3 (3rd of batch3)");

        data_in = 8'd54;
        @(posedge clk); #1;
        check_outputs("A3: after data_in=54 (4th of batch3)");

        // ---- Group B: Boundary/corner cases ----

        // B1: All zeros
        data_in = 8'd0;
        @(posedge clk); #1;
        check_outputs("B1: all zeros (1/4)");
        @(posedge clk); #1;
        check_outputs("B1: all zeros (2/4)");
        @(posedge clk); #1;
        check_outputs("B1: all zeros (3/4)");
        @(posedge clk); #1;
        check_outputs("B1: all zeros (4/4)");

        // B2: All max (255)
        data_in = 8'd255;
        @(posedge clk); #1;
        check_outputs("B2: all 255 (1/4)");
        @(posedge clk); #1;
        check_outputs("B2: all 255 (2/4)");
        @(posedge clk); #1;
        check_outputs("B2: all 255 (3/4)");
        @(posedge clk); #1;
        check_outputs("B2: all 255 (4/4)");

        // B3: Alternating 0 and 255
        data_in = 8'd0;
        @(posedge clk); #1;
        check_outputs("B3: alternating (0)");
        data_in = 8'd255;
        @(posedge clk); #1;
        check_outputs("B3: alternating (255)");
        data_in = 8'd0;
        @(posedge clk); #1;
        check_outputs("B3: alternating (0)");
        data_in = 8'd255;
        @(posedge clk); #1;
        check_outputs("B3: alternating (255)");

        // B4: Single value repeated
        data_in = 8'd128;
        @(posedge clk); #1;
        check_outputs("B4: all 128 (1/4)");
        @(posedge clk); #1;
        check_outputs("B4: all 128 (2/4)");
        @(posedge clk); #1;
        check_outputs("B4: all 128 (3/4)");
        @(posedge clk); #1;
        check_outputs("B4: all 128 (4/4)");

        // B5: Powers of 2
        data_in = 8'd1;
        @(posedge clk); #1;
        check_outputs("B5: powers of 2 (1)");
        data_in = 8'd2;
        @(posedge clk); #1;
        check_outputs("B5: powers of 2 (2)");
        data_in = 8'd4;
        @(posedge clk); #1;
        check_outputs("B5: powers of 2 (4)");
        data_in = 8'd8;
        @(posedge clk); #1;
        check_outputs("B5: powers of 2 (8)");

        // ---- Group C: Randomized stress tests ----
        for (i = 0; i < 60; i = i + 1) begin
            data_in = $random(seed) % 256;
            @(posedge clk); #1;
            check_outputs("C: random stress test");
        end

        // ---- Group D: Protocol/timing tests ----

        // D1: valid_in deasserted mid-stream
        valid_in = 0;
        data_in = 8'd10;
        @(posedge clk); #1;
        check_outputs("D1: valid_in=0 (no data)");
        @(posedge clk); #1;
        check_outputs("D1: valid_in=0 (still no data)");

        // D2: Re-assert valid_in
        valid_in = 1;
        data_in = 8'd20;
        @(posedge clk); #1;
        check_outputs("D2: valid_in re-asserted (1/4)");
        data_in = 8'd30;
        @(posedge clk); #1;
        check_outputs("D2: (2/4)");
        data_in = 8'd40;
        @(posedge clk); #1;
        check_outputs("D2: (3/4)");
        data_in = 8'd50;
        @(posedge clk); #1;
        check_outputs("D2: (4/4)");

        // D3: Reset in the middle of accumulation
        data_in = 8'd100;
        @(posedge clk); #1;
        check_outputs("D3: before reset (1/4)");
        data_in = 8'd101;
        @(posedge clk); #1;
        check_outputs("D3: before reset (2/4)");

        rst_n = 0;
        @(posedge clk); #1;
        check_outputs("D3: during reset");
        @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;
        check_outputs("D3: after reset release");

        // D4: Full batch after reset recovery
        valid_in = 1;
        data_in = 8'd10;
        @(posedge clk); #1;
        check_outputs("D4: post-reset batch (1/4)");
        data_in = 8'd20;
        @(posedge clk); #1;
        check_outputs("D4: post-reset batch (2/4)");
        data_in = 8'd30;
        @(posedge clk); #1;
        check_outputs("D4: post-reset batch (3/4)");
        data_in = 8'd40;
        @(posedge clk); #1;
        check_outputs("D4: post-reset batch (4/4)");

        // D5: Toggle valid_in every cycle
        valid_in = 1;
        data_in = 8'd11;
        @(posedge clk); #1;
        check_outputs("D5: toggle valid (on)");
        valid_in = 0;
        @(posedge clk); #1;
        check_outputs("D5: toggle valid (off)");
        valid_in = 1;
        data_in = 8'd22;
        @(posedge clk); #1;
        check_outputs("D5: toggle valid (on)");
        valid_in = 0;
        @(posedge clk); #1;
        check_outputs("D5: toggle valid (off)");
        valid_in = 1;
        data_in = 8'd33;
        @(posedge clk); #1;
        check_outputs("D5: toggle valid (on)");
        valid_in = 0;
        @(posedge clk); #1;
        check_outputs("D5: toggle valid (off)");
        valid_in = 1;
        data_in = 8'd44;
        @(posedge clk); #1;
        check_outputs("D5: toggle valid (on)");
        valid_in = 0;
        @(posedge clk); #1;
        check_outputs("D5: toggle valid (off)");

        // D6: Multiple resets
        rst_n = 0;
        @(posedge clk); #1;
        check_outputs("D6: reset pulse 1");
        rst_n = 1;
        @(posedge clk); #1;
        check_outputs("D6: after reset 1");
        rst_n = 0;
        @(posedge clk); #1;
        check_outputs("D6: reset pulse 2");
        rst_n = 1;
        @(posedge clk); #1;
        check_outputs("D6: after reset 2");

        // SECTION 9: Score reporting
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

// SECTION 10: Golden reference model
module golden_accu(
    input               clk         ,
    input               rst_n       ,
    input       [7:0]   data_in     ,
    input               valid_in     ,

    output  reg         valid_out     ,
    output  reg [9:0]   data_out
);

   reg [1:0] count;
   wire add_cnt;
   wire ready_add;
   wire end_cnt;
   reg [9:0]   data_out_reg;

   assign add_cnt = ready_add;
   assign end_cnt = ready_add && (count == 'd3);

   always @(posedge clk or negedge rst_n) begin
       if(!rst_n) begin
          count <= 0;
       end
       else if(end_cnt) begin
          count <= 0;
       end
       else if(add_cnt) begin
          count <= count + 1;
       end
   end

   always @(posedge clk or negedge rst_n) begin
      if(!rst_n) begin
        data_out_reg <= 0;
      end
      else if (add_cnt && count == 0) begin
          data_out_reg <= data_in;
      end
      else if (add_cnt) begin
          data_out_reg <= data_out_reg + data_in;
      end
   end

   always @(posedge clk or negedge rst_n) begin
      if(!rst_n) begin
        data_out <= 0;
      end
      else if (end_cnt) begin
          data_out <= data_out_reg + data_in;
      end
   end

   assign ready_add = valid_in;

   always @(posedge clk or negedge rst_n) begin
       if(!rst_n) begin
           valid_out <= 0;
       end
       else if(end_cnt) begin
           valid_out <= 1;
       end
       else begin
           valid_out <= 0;
       end
   end

endmodule
