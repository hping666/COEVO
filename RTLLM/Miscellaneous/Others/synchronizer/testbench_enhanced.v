`timescale 1ns/1ps

module testbench_enhanced;

    // Signal declarations
    reg clk_a;
    reg clk_b;
    reg arstn;
    reg brstn;
    reg [3:0] data_in;
    reg data_en;
    wire [3:0] dataout;

    // Golden reference outputs
    wire [3:0] ref_dataout;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // Clock generation
    initial clk_a = 0;
    initial clk_b = 0;
    always #5 clk_a = ~clk_a;   // 100MHz
    always #10 clk_b = ~clk_b;  // 50MHz

    // DUT instantiation
    synchronizer uut (
        .clk_a(clk_a),
        .clk_b(clk_b),
        .arstn(arstn),
        .brstn(brstn),
        .data_in(data_in),
        .data_en(data_en),
        .dataout(dataout)
    );

    // Golden reference instantiation
    golden_synchronizer ref_model (
        .clk_a(clk_a),
        .clk_b(clk_b),
        .arstn(arstn),
        .brstn(brstn),
        .data_in(data_in),
        .data_en(data_en),
        .dataout(ref_dataout)
    );

    // Check task
    task check_outputs;
    begin
        check_id = check_id + 1;
        total_checks = total_checks + 1;
        if (dataout !== ref_dataout) begin
            $display("[FORGE_CHECK %0d] FAIL: DUT dataout=%b, GOLD dataout=%b at time %0t",
                     check_id, dataout, ref_dataout, $time);
            failed_checks = failed_checks + 1;
        end else begin
            passed_checks = passed_checks + 1;
        end
    end
    endtask

    // Task: send data with enable and wait for propagation
    task send_data_and_wait;
        input [3:0] data;
        input integer en_cycles_clkb;  // how many clk_b cycles to keep enable high
        input integer wait_after;      // how many clk_b cycles to wait after disable
    begin
        data_in = data;
        // Wait a bit then enable
        #20;
        data_en = 1;
        // Keep enabled for en_cycles_clkb clk_b cycles (20ns each)
        repeat(en_cycles_clkb) @(posedge clk_b);
        #1;
        check_outputs;
        data_en = 0;
        // Wait after
        repeat(wait_after) @(posedge clk_b);
        #1;
        check_outputs;
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
        // Initialize
        clk_a = 0;
        clk_b = 0;
        arstn = 0;
        brstn = 0;
        data_en = 0;
        data_in = 0;

        // =============================================
        // Group A: Original testbench cases
        // =============================================

        #20; arstn = 1;
        #5;  brstn = 1;

        // A1: Send data_in = 4
        #50; data_in = 4;
        #10; data_en = 1;
        #100;
        @(posedge clk_b); #1;
        check_outputs;
        #10; data_en = 0;
        #100;
        @(posedge clk_b); #1;
        check_outputs;

        // A2: Send data_in = 7
        #50; data_in = 7;
        #10; data_en = 1;
        #80;
        @(posedge clk_b); #1;
        check_outputs;
        #10; data_en = 0;
        #100;
        @(posedge clk_b); #1;
        check_outputs;

        // A3: Reset and send data_in = 9
        #50;
        #20; arstn = 0;
        #100;
        @(posedge clk_b); #1;
        check_outputs;
        #20; arstn = 1;
        #50; data_in = 9;
        #10; data_en = 1;
        #100;
        @(posedge clk_b); #1;
        check_outputs;
        #10; data_en = 0;
        #100;
        @(posedge clk_b); #1;
        check_outputs;

        // =============================================
        // Group B: Boundary/corner cases
        // =============================================

        // Full reset
        arstn = 0; brstn = 0;
        data_en = 0; data_in = 0;
        #40;
        @(posedge clk_b); #1;
        check_outputs;
        arstn = 1; brstn = 1;
        #20;

        // B1: All ones data 4'hF
        send_data_and_wait(4'hF, 6, 5);

        // B2: All zeros data 4'h0
        send_data_and_wait(4'h0, 6, 5);

        // B3: Alternating 4'hA
        send_data_and_wait(4'hA, 6, 5);

        // B4: Alternating inverse 4'h5
        send_data_and_wait(4'h5, 6, 5);

        // B5: Reset only brstn (b-domain reset)
        brstn = 0;
        #40;
        @(posedge clk_b); #1;
        check_outputs;
        brstn = 1;
        #40;
        @(posedge clk_b); #1;
        check_outputs;

        // B6: Send data after b-reset
        send_data_and_wait(4'h3, 6, 5);

        // B7: Reset only arstn (a-domain reset)
        arstn = 0;
        #40;
        @(posedge clk_a); #1;
        @(posedge clk_b); #1;
        check_outputs;
        arstn = 1;
        #40;
        @(posedge clk_b); #1;
        check_outputs;

        // B8: Send data after a-reset
        send_data_and_wait(4'hC, 6, 5);

        // B9: Rapid data change (but with enable low between)
        data_in = 4'h1;
        #20;
        data_en = 1;
        repeat(6) @(posedge clk_b);
        #1; check_outputs;
        data_en = 0;
        repeat(5) @(posedge clk_b);
        #1; check_outputs;

        data_in = 4'h2;
        #20;
        data_en = 1;
        repeat(6) @(posedge clk_b);
        #1; check_outputs;
        data_en = 0;
        repeat(5) @(posedge clk_b);
        #1; check_outputs;

        // B10: Both resets simultaneously
        arstn = 0; brstn = 0;
        #40;
        @(posedge clk_b); #1;
        check_outputs;
        arstn = 1; brstn = 1;
        #40;
        @(posedge clk_b); #1;
        check_outputs;

        // B11: Send after both reset
        send_data_and_wait(4'h7, 6, 5);

        // =============================================
        // Group C: Randomized stress
        // =============================================

        // Reset first
        arstn = 0; brstn = 0;
        data_en = 0; data_in = 0;
        #40;
        arstn = 1; brstn = 1;
        #20;

        for (i = 0; i < 12; i = i + 1) begin : rand_loop
            reg [3:0] rdata;
            rdata = $random(seed) & 4'hF;
            send_data_and_wait(rdata, 6, 6);
        end

        // =============================================
        // Group D: Protocol/timing tests
        // =============================================

        // D1: Enable high for exactly 3 clk_b cycles (minimum per spec)
        data_in = 4'hB;
        #20;
        data_en = 1;
        repeat(3) @(posedge clk_b);
        // Need additional cycles for sync through two FFs
        repeat(3) @(posedge clk_b);
        #1; check_outputs;
        data_en = 0;
        repeat(5) @(posedge clk_b);
        #1; check_outputs;

        // D2: Data changes while enable is low (should not affect output)
        data_in = 4'hE;
        repeat(5) @(posedge clk_b);
        #1; check_outputs;
        data_in = 4'hD;
        repeat(5) @(posedge clk_b);
        #1; check_outputs;

        // D3: Enable and verify output holds after disable
        data_in = 4'h6;
        #20;
        data_en = 1;
        repeat(6) @(posedge clk_b);
        #1; check_outputs;
        data_en = 0;
        repeat(3) @(posedge clk_b);
        #1; check_outputs;
        repeat(3) @(posedge clk_b);
        #1; check_outputs;
        repeat(3) @(posedge clk_b);
        #1; check_outputs;

        // D4: Long idle then data
        repeat(20) @(posedge clk_b);
        #1; check_outputs;
        send_data_and_wait(4'h8, 6, 5);

        // D5: Multiple sequential values
        send_data_and_wait(4'h1, 6, 6);
        send_data_and_wait(4'h2, 6, 6);
        send_data_and_wait(4'h4, 6, 6);
        send_data_and_wait(4'h8, 6, 6);

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
// Golden Reference Model
// =============================================
module golden_synchronizer(
    input               clk_a,
    input               clk_b,
    input               arstn,
    input               brstn,
    input       [3:0]   data_in,
    input               data_en,

    output reg  [3:0]   dataout
);

    reg [3:0] data_reg;
    always @(posedge clk_a or negedge arstn) begin
        if (!arstn) data_reg <= 0;
        else        data_reg <= data_in;
    end

    reg en_data_reg;
    always @(posedge clk_a or negedge arstn) begin
        if (!arstn) en_data_reg <= 0;
        else        en_data_reg <= data_en;
    end

    reg en_clap_one;
    reg en_clap_two;
    always @(posedge clk_b or negedge brstn) begin
        if (!brstn) en_clap_one <= 0;
        else        en_clap_one <= en_data_reg;
    end
    always @(posedge clk_b or negedge brstn) begin
        if (!brstn) en_clap_two <= 0;
        else        en_clap_two <= en_clap_one;
    end

    always @(posedge clk_b or negedge brstn) begin
        if (!brstn) dataout <= 0;
        else        dataout <= (en_clap_two) ? data_reg : dataout;
    end

endmodule
