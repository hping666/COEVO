`timescale 1ns/1ps

module testbench_enhanced;

    // SECTION 1: Signal declarations
    parameter DATA_WIDTH = 64;
    parameter STG_WIDTH = 16;

    reg clk;
    reg rst_n;
    reg i_en;
    reg [DATA_WIDTH-1:0] adda;
    reg [DATA_WIDTH-1:0] addb;

    wire [DATA_WIDTH:0] dut_result;
    wire dut_o_en;
    wire [DATA_WIDTH:0] ref_result;
    wire ref_o_en;

    // SECTION 2: Clock generation
    initial clk = 0;
    always #5 clk = ~clk;

    // SECTION 3: Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // SECTION 4: DUT instantiation
    adder_pipe_64bit #(
        .DATA_WIDTH(DATA_WIDTH),
        .STG_WIDTH(STG_WIDTH)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .i_en(i_en),
        .adda(adda),
        .addb(addb),
        .result(dut_result),
        .o_en(dut_o_en)
    );

    // SECTION 5: Golden reference instantiation
    golden_adder_pipe_64bit #(
        .DATA_WIDTH(DATA_WIDTH),
        .STG_WIDTH(STG_WIDTH)
    ) ref_model (
        .clk(clk),
        .rst_n(rst_n),
        .i_en(i_en),
        .adda(adda),
        .addb(addb),
        .result(ref_result),
        .o_en(ref_o_en)
    );

    // SECTION 6: Check task
    task check_outputs;
        input [255:0] description;
        begin
            check_id = check_id + 1;
            total_checks = total_checks + 1;
            if (dut_result !== ref_result || dut_o_en !== ref_o_en) begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL | %0s | expected result=%h o_en=%b got result=%h o_en=%b | time=%0t",
                    check_id, description, ref_result, ref_o_en, dut_result, dut_o_en, $time);
            end else begin
                passed_checks = passed_checks + 1;
            end
        end
    endtask

    // Helper task: apply stimulus and wait for pipeline output
    // Holds i_en high throughout pipeline latency (matches original TB protocol)
    task apply_and_wait;
        input [DATA_WIDTH-1:0] a;
        input [DATA_WIDTH-1:0] b;
        input [255:0] description;
        begin
            @(posedge clk);
            #1;
            i_en = 1'b1;
            adda = a;
            addb = b;
            // Hold i_en high through full 4-stage pipeline latency
            @(posedge clk); #1;
            @(posedge clk); #1;
            @(posedge clk); #1;
            @(posedge clk); #1;
            check_outputs(description);
            i_en = 1'b0;
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
        i_en = 0;
        adda = 0;
        addb = 0;

        // Reset
        @(posedge clk); #1;
        @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;

        // =============================================
        // Group A: Original testbench-style cases
        // =============================================
        apply_and_wait(64'h0000_0001_0000_0001, 64'h0000_0002_0000_0002, "GroupA: basic add 1");
        apply_and_wait(64'hFFFF_FFFF_FFFF_FFFF, 64'h0000_0000_0000_0001, "GroupA: max+1 overflow");
        apply_and_wait(64'h1234_5678_9ABC_DEF0, 64'hFEDC_BA98_7654_3210, "GroupA: arbitrary values");
        apply_and_wait(64'h8000_0000_0000_0000, 64'h8000_0000_0000_0000, "GroupA: two large MSB");
        apply_and_wait(64'hAAAA_AAAA_AAAA_AAAA, 64'h5555_5555_5555_5555, "GroupA: complementary");

        // =============================================
        // Group B: Boundary/corner cases
        // =============================================
        apply_and_wait(64'h0, 64'h0, "GroupB: zero+zero");
        apply_and_wait(64'hFFFF_FFFF_FFFF_FFFF, 64'h0, "GroupB: max+zero");
        apply_and_wait(64'h0, 64'hFFFF_FFFF_FFFF_FFFF, "GroupB: zero+max");
        apply_and_wait(64'hFFFF_FFFF_FFFF_FFFF, 64'hFFFF_FFFF_FFFF_FFFF, "GroupB: max+max");
        apply_and_wait(64'h0000_0000_0000_0001, 64'h0000_0000_0000_0001, "GroupB: 1+1");
        apply_and_wait(64'h0000_0000_0000_FFFF, 64'h0000_0000_0000_0001, "GroupB: stg1 carry");
        apply_and_wait(64'h0000_0000_FFFF_0000, 64'h0000_0000_0001_0000, "GroupB: stg2 carry");
        apply_and_wait(64'h0000_FFFF_0000_0000, 64'h0000_0001_0000_0000, "GroupB: stg3 carry");
        apply_and_wait(64'hFFFF_0000_0000_0000, 64'h0001_0000_0000_0000, "GroupB: stg4 carry");
        apply_and_wait(64'h0000_0000_FFFF_FFFF, 64'h0000_0000_0000_0001, "GroupB: carry across stg1-2");
        apply_and_wait(64'h0000_FFFF_FFFF_FFFF, 64'h0000_0000_0000_0001, "GroupB: carry across stg1-3");
        apply_and_wait(64'hFFFF_FFFF_FFFF_FFFF, 64'h0000_0000_0000_0001, "GroupB: carry all stages");
        apply_and_wait(64'h7FFF_FFFF_FFFF_FFFF, 64'h7FFF_FFFF_FFFF_FFFF, "GroupB: two just-under-half");
        apply_and_wait(64'h8000_0000_0000_0000, 64'h7FFF_FFFF_FFFF_FFFF, "GroupB: half+half-1");
        apply_and_wait(64'h0000_0000_0000_0000, 64'h0000_0000_0000_0001, "GroupB: zero+one");
        apply_and_wait(64'hDEAD_BEEF_DEAD_BEEF, 64'h1234_5678_1234_5678, "GroupB: pattern 1");
        apply_and_wait(64'hCAFE_BABE_CAFE_BABE, 64'h0BAD_F00D_0BAD_F00D, "GroupB: pattern 2");
        apply_and_wait(64'h0001_0001_0001_0001, 64'hFFFE_FFFE_FFFE_FFFE, "GroupB: near-boundary");
        apply_and_wait(64'h0F0F_0F0F_0F0F_0F0F, 64'hF0F0_F0F0_F0F0_F0F0, "GroupB: nibble complement");
        apply_and_wait(64'h00FF_00FF_00FF_00FF, 64'hFF00_FF00_FF00_FF00, "GroupB: byte complement");

        // =============================================
        // Group C: Randomized stress tests
        // =============================================
        for (i = 0; i < 50; i = i + 1) begin
            apply_and_wait(
                {$random(seed), $random(seed)},
                {$random(seed), $random(seed)},
                "GroupC: random test"
            );
        end

        // =============================================
        // Group D: Protocol/timing tests
        // =============================================

        // D1: Reset in the middle of operation
        @(posedge clk); #1;
        i_en = 1'b1;
        adda = 64'hAAAA_BBBB_CCCC_DDDD;
        addb = 64'h1111_2222_3333_4444;
        @(posedge clk); #1;
        i_en = 1'b0;
        // Assert reset mid-pipeline
        rst_n = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;
        @(posedge clk); #1;
        @(posedge clk); #1;
        check_outputs("GroupD: reset mid-pipe");

        // D2: Back-to-back enable pulses (pipeline streaming)
        @(posedge clk); #1;
        i_en = 1'b1;
        adda = 64'h0000_0000_0000_000A;
        addb = 64'h0000_0000_0000_0005;
        @(posedge clk); #1;
        adda = 64'h0000_0000_0000_0014;
        addb = 64'h0000_0000_0000_000A;
        @(posedge clk); #1;
        adda = 64'h0000_0000_0000_001E;
        addb = 64'h0000_0000_0000_000F;
        @(posedge clk); #1;
        adda = 64'h0000_0000_0000_0028;
        addb = 64'h0000_0000_0000_0014;
        @(posedge clk); #1;
        i_en = 1'b0;
        // Wait for first result after 3 more cycles
        @(posedge clk); #1;
        @(posedge clk); #1;
        @(posedge clk); #1;
        check_outputs("GroupD: streaming pipe result 1");
        @(posedge clk); #1;
        check_outputs("GroupD: streaming pipe result 2");
        @(posedge clk); #1;
        check_outputs("GroupD: streaming pipe result 3");
        @(posedge clk); #1;
        check_outputs("GroupD: streaming pipe result 4");

        // D3: i_en deasserted - outputs should hold
        @(posedge clk); #1;
        i_en = 1'b0;
        adda = 64'hFFFF_FFFF_FFFF_FFFF;
        addb = 64'hFFFF_FFFF_FFFF_FFFF;
        @(posedge clk); #1;
        @(posedge clk); #1;
        @(posedge clk); #1;
        @(posedge clk); #1;
        check_outputs("GroupD: i_en deasserted hold");

        // D4: Single-cycle enable pulse
        @(posedge clk); #1;
        i_en = 1'b1;
        adda = 64'h0000_0000_DEAD_BEEF;
        addb = 64'h0000_0000_0000_0001;
        @(posedge clk); #1;
        i_en = 1'b0;
        @(posedge clk); #1;
        @(posedge clk); #1;
        @(posedge clk); #1;
        check_outputs("GroupD: single cycle enable");

        // D5: Multiple resets
        rst_n = 0;
        @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;
        rst_n = 0;
        @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;
        @(posedge clk); #1;
        check_outputs("GroupD: double reset");

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

// =============================================
// Golden reference model
// =============================================
module golden_adder_pipe_64bit
#(
    parameter DATA_WIDTH = 64,
    parameter STG_WIDTH = 16
)
(
    input clk,
    input rst_n,
    input i_en,
    input [DATA_WIDTH-1:0] adda,
    input [DATA_WIDTH-1:0] addb,
    output [DATA_WIDTH:0] result,
    output reg o_en
);

reg stage1;
reg stage2;
reg stage3;

wire [STG_WIDTH-1:0] a1;
wire [STG_WIDTH-1:0] b1;
wire [STG_WIDTH-1:0] a2;
wire [STG_WIDTH-1:0] b2;
wire [STG_WIDTH-1:0] a3;
wire [STG_WIDTH-1:0] b3;
wire [STG_WIDTH-1:0] a4;
wire [STG_WIDTH-1:0] b4;

reg [STG_WIDTH-1:0] a2_ff1;
reg [STG_WIDTH-1:0] b2_ff1;

reg [STG_WIDTH-1:0] a3_ff1;
reg [STG_WIDTH-1:0] b3_ff1;
reg [STG_WIDTH-1:0] a3_ff2;
reg [STG_WIDTH-1:0] b3_ff2;

reg [STG_WIDTH-1:0] a4_ff1;
reg [STG_WIDTH-1:0] b4_ff1;
reg [STG_WIDTH-1:0] a4_ff2;
reg [STG_WIDTH-1:0] b4_ff2;
reg [STG_WIDTH-1:0] a4_ff3;
reg [STG_WIDTH-1:0] b4_ff3;

reg c1;
reg c2;
reg c3;
reg c4;

reg [STG_WIDTH-1:0] s1;
reg [STG_WIDTH-1:0] s2;
reg [STG_WIDTH-1:0] s3;
reg [STG_WIDTH-1:0] s4;

reg [STG_WIDTH-1:0] s1_ff1;
reg [STG_WIDTH-1:0] s1_ff2;
reg [STG_WIDTH-1:0] s1_ff3;

reg [STG_WIDTH-1:0] s2_ff1;
reg [STG_WIDTH-1:0] s2_ff2;

reg [STG_WIDTH-1:0] s3_ff1;

assign a1 = adda[STG_WIDTH-1:0];
assign b1 = addb[STG_WIDTH-1:0];
assign a2 = adda[STG_WIDTH*2-1:16];
assign b2 = addb[STG_WIDTH*2-1:16];
assign a3 = adda[STG_WIDTH*3-1:32];
assign b3 = addb[STG_WIDTH*3-1:32];
assign a4 = adda[STG_WIDTH*4-1:48];
assign b4 = addb[STG_WIDTH*4-1:48];

always @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
        stage1 <= 1'b0;
        stage2 <= 1'b0;
        stage3 <= 1'b0;
        o_en <= 1'b0;
    end
    else begin
        stage1 <= i_en;
        stage2 <= stage1;
        stage3 <= stage2;
        o_en <= stage3;
    end
end

always @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
        a2_ff1 <= 'd0;
        b2_ff1 <= 'd0;
        a3_ff1 <= 'd0;
        b3_ff1 <= 'd0;
        a3_ff2 <= 'd0;
        b3_ff2 <= 'd0;
        a4_ff1 <= 'd0;
        b4_ff1 <= 'd0;
        a4_ff2 <= 'd0;
        b4_ff2 <= 'd0;
        a4_ff3 <= 'd0;
        b4_ff3 <= 'd0;
    end
    else begin
        a2_ff1 <= a2;
        b2_ff1 <= b2;
        a3_ff1 <= a3;
        b3_ff1 <= b3;
        a3_ff2 <= a3_ff1;
        b3_ff2 <= b3_ff1;
        a4_ff1 <= a4;
        b4_ff1 <= b4;
        a4_ff2 <= a4_ff1;
        b4_ff2<= b4_ff1;
        a4_ff3 <= a4_ff2;
        b4_ff3 <= b4_ff2;
    end
end

always @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
        s1_ff1 <= 'd0;
        s1_ff2 <= 'd0;
        s1_ff3 <= 'd0;
        s2_ff1 <= 'd0;
        s2_ff2 <= 'd0;
        s3_ff1 <= 'd0;
    end
    else begin
        s1_ff1 <= s1;
        s1_ff2 <= s1_ff1;
        s1_ff3 <= s1_ff2;
        s2_ff1 <= s2;
        s2_ff2 <= s2_ff1;
        s3_ff1 <= s3;
    end
end

always @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
        c1 <= 1'b0;
        s1 <= 'd0;
    end
    else if (i_en) begin
        {c1, s1} <= a1 + b1;
    end
    else begin
        c1 <= c1;
        s1 <= s1;
    end
end

always @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
        c2 <= 1'b0;
        s2 <= 'd0;
    end
    else if (stage1) begin
        {c2, s2} <= a2_ff1 + b2_ff1 + c1;
    end
    else begin
        c2 <= c2;
        s2 <= s2;
    end
end

always @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
        c3 <= 1'b0;
        s3 <= 'd0;
    end
    else if (stage2) begin
        {c3, s3} <= a3_ff2 + b3_ff2 + c2;
    end
    else begin
        c3 <= c3;
        s3 <= s3;
    end
end

always @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
        c4 <= 1'b0;
        s4 <= 'd0;
    end
    else if (stage3) begin
        {c4, s4} <= a4_ff3 + b4_ff3 + c3;
    end
    else begin
        c4 <= c4;
        s4 <= s4;
    end
end

assign result = {c4, s4, s3_ff1, s2_ff2, s1_ff3};

endmodule
