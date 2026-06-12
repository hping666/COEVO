`timescale 1ns/1ps

module testbench_enhanced;

    // Parameters
    parameter WIDTH = 8;
    parameter DEPTH = 16;

    // Signal declarations
    reg wclk, rclk;
    reg wrstn, rrstn;
    reg winc, rinc;
    reg [WIDTH-1:0] wdata;
    wire wfull, rempty;
    wire [WIDTH-1:0] rdata;

    wire wfull_ref, rempty_ref;
    wire [WIDTH-1:0] rdata_ref;

    // Test infrastructure
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed = 42;
    integer i;

    // DUT instantiation
    asyn_fifo #(.WIDTH(WIDTH), .DEPTH(DEPTH)) uut (
        .wclk(wclk),
        .rclk(rclk),
        .wrstn(wrstn),
        .rrstn(rrstn),
        .winc(winc),
        .rinc(rinc),
        .wdata(wdata),
        .wfull(wfull),
        .rempty(rempty),
        .rdata(rdata)
    );

    // Golden reference instantiation
    golden_asyn_fifo #(.WIDTH(WIDTH), .DEPTH(DEPTH)) ref_model (
        .wclk(wclk),
        .rclk(rclk),
        .wrstn(wrstn),
        .rrstn(rrstn),
        .winc(winc),
        .rinc(rinc),
        .wdata(wdata),
        .wfull(wfull_ref),
        .rempty(rempty_ref),
        .rdata(rdata_ref)
    );

    // Clock generation: wclk=10ns period, rclk=20ns period
    initial begin
        wclk = 0;
        forever #5 wclk = ~wclk;
    end
    initial begin
        rclk = 0;
        forever #10 rclk = ~rclk;
    end

    // Check task - compare flags
    task check_flags;
        input [199:0] test_name;
        begin
            check_id = check_id + 1;
            total_checks = total_checks + 1;
            if (wfull === wfull_ref && rempty === rempty_ref) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FAIL] Check %0d: %s - DUT wfull=%b rempty=%b, REF wfull=%b rempty=%b at time %0t",
                    check_id, test_name, wfull, rempty, wfull_ref, rempty_ref, $time);
            end
        end
    endtask

    // Check task - compare data
    task check_data;
        input [199:0] test_name;
        begin
            check_id = check_id + 1;
            total_checks = total_checks + 1;
            if (rdata === rdata_ref) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FAIL] Check %0d: %s - DUT rdata=%h, REF rdata=%h at time %0t",
                    check_id, test_name, rdata, rdata_ref, $time);
            end
        end
    endtask

    // Check all signals
    task check_all;
        input [199:0] test_name;
        begin
            check_id = check_id + 1;
            total_checks = total_checks + 1;
            if (wfull === wfull_ref && rempty === rempty_ref && rdata === rdata_ref) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FAIL] Check %0d: %s - DUT(wf=%b,re=%b,rd=%h) REF(wf=%b,re=%b,rd=%h) t=%0t",
                    check_id, test_name, wfull, rempty, rdata, wfull_ref, rempty_ref, rdata_ref, $time);
            end
        end
    endtask

    // Task: write one word
    task write_one;
        input [WIDTH-1:0] data;
        begin
            @(posedge wclk); #1;
            winc = 1;
            wdata = data;
            @(posedge wclk); #1;
            winc = 0;
        end
    endtask

    // Task: read one word
    task read_one;
        begin
            @(posedge rclk); #1;
            rinc = 1;
            @(posedge rclk); #1;
            rinc = 0;
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
        wrstn = 0;
        rrstn = 0;
        winc = 0;
        rinc = 0;
        wdata = 0;

        // Reset
        #50;
        wrstn = 1;
        rrstn = 1;
        #50;

        // =============================================
        // Group A: Original testbench cases (simplified)
        // Write one word, wait, read it back
        // =============================================

        // Write AA
        @(posedge wclk); #1;
        winc = 1;
        wdata = 8'hAA;
        @(posedge wclk); #1;
        winc = 0;

        // Wait for sync
        repeat(6) @(posedge rclk);
        #1;
        check_flags("A: after write AA");

        // Write a few more
        @(posedge wclk); #1;
        wdata = 8'hAB;
        winc = 1;
        @(posedge wclk); #1;
        winc = 0;
        @(posedge wclk); #1;
        wdata = 8'hAC;
        winc = 1;
        @(posedge wclk); #1;
        winc = 0;

        // Wait for sync
        repeat(6) @(posedge rclk);
        #1;
        check_flags("A: after 3 writes");

        // Read back
        @(posedge rclk); #1;
        rinc = 1;
        @(posedge rclk); #1;
        rinc = 0;
        @(posedge rclk); #1;
        check_data("A: read back 1");

        @(posedge rclk); #1;
        rinc = 1;
        @(posedge rclk); #1;
        rinc = 0;
        @(posedge rclk); #1;
        check_data("A: read back 2");

        @(posedge rclk); #1;
        rinc = 1;
        @(posedge rclk); #1;
        rinc = 0;
        @(posedge rclk); #1;
        check_data("A: read back 3");

        // Wait for empty to propagate
        repeat(6) @(posedge rclk);
        #1;
        check_flags("A: empty after reads");

        // =============================================
        // Group B: Boundary/corner cases
        // =============================================

        // B1: Empty read - try reading when FIFO is empty
        // Reset first
        wrstn = 0; rrstn = 0;
        #50;
        wrstn = 1; rrstn = 1;
        #50;

        repeat(6) @(posedge rclk); #1;
        check_flags("B: empty after reset");

        @(posedge rclk); #1;
        rinc = 1;
        @(posedge rclk); #1;
        rinc = 0;
        repeat(4) @(posedge rclk); #1;
        check_flags("B: empty read flags");

        // B2: Fill to full
        wrstn = 0; rrstn = 0;
        #50;
        wrstn = 1; rrstn = 1;
        #50;

        for (i = 0; i < DEPTH; i = i + 1) begin
            @(posedge wclk); #1;
            winc = 1;
            wdata = i[WIDTH-1:0];
            @(posedge wclk); #1;
            winc = 0;
        end

        // Wait for full to propagate
        repeat(8) @(posedge wclk); #1;
        check_flags("B: full after 16 writes");

        // B3: Full write - try writing when full
        @(posedge wclk); #1;
        winc = 1;
        wdata = 8'hFF;
        @(posedge wclk); #1;
        winc = 0;
        repeat(4) @(posedge wclk); #1;
        check_flags("B: write when full");

        // B4: Drain all
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(posedge rclk); #1;
            rinc = 1;
            @(posedge rclk); #1;
            rinc = 0;
            @(posedge rclk); #1;
            check_data("B: drain read");
        end

        repeat(8) @(posedge rclk); #1;
        check_flags("B: empty after drain");

        // B5: Single element write/read
        wrstn = 0; rrstn = 0;
        #50;
        wrstn = 1; rrstn = 1;
        #50;

        @(posedge wclk); #1;
        winc = 1;
        wdata = 8'h42;
        @(posedge wclk); #1;
        winc = 0;

        repeat(8) @(posedge rclk); #1;
        check_flags("B: single element flags");

        @(posedge rclk); #1;
        rinc = 1;
        @(posedge rclk); #1;
        rinc = 0;
        @(posedge rclk); #1;
        check_data("B: single element read");

        repeat(8) @(posedge rclk); #1;
        check_flags("B: empty after single");

        // B6: Reset while non-empty
        wrstn = 0; rrstn = 0;
        #50;
        wrstn = 1; rrstn = 1;
        #50;

        for (i = 0; i < 5; i = i + 1) begin
            @(posedge wclk); #1;
            winc = 1;
            wdata = i[WIDTH-1:0] + 8'h10;
            @(posedge wclk); #1;
            winc = 0;
        end

        repeat(6) @(posedge rclk); #1;
        check_flags("B: non-empty before rst");

        // Reset while non-empty
        wrstn = 0; rrstn = 0;
        #50;
        wrstn = 1; rrstn = 1;
        #50;

        repeat(6) @(posedge rclk); #1;
        check_flags("B: after reset non-empty");

        // B7: Simultaneous read/write
        wrstn = 0; rrstn = 0;
        #50;
        wrstn = 1; rrstn = 1;
        #50;

        // Write 4 items first
        for (i = 0; i < 4; i = i + 1) begin
            @(posedge wclk); #1;
            winc = 1;
            wdata = i[WIDTH-1:0] + 8'h20;
            @(posedge wclk); #1;
            winc = 0;
        end

        repeat(8) @(posedge rclk); #1;

        // Now read and write simultaneously
        for (i = 0; i < 4; i = i + 1) begin
            // Start both at same time
            @(posedge wclk); #1;
            winc = 1;
            wdata = i[WIDTH-1:0] + 8'h30;
            rinc = 1;
            @(posedge wclk); #1;
            winc = 0;
            @(posedge rclk); #1;
            rinc = 0;
            repeat(4) @(posedge rclk); #1;
            check_flags("B: simul rw flags");
        end

        // =============================================
        // Group C: Randomized stress tests
        // =============================================
        wrstn = 0; rrstn = 0;
        #50;
        wrstn = 1; rrstn = 1;
        #50;

        // Random writes and reads
        for (i = 0; i < 40; i = i + 1) begin
            if ($random(seed) % 2) begin
                // Write
                @(posedge wclk); #1;
                winc = 1;
                wdata = $random(seed);
                @(posedge wclk); #1;
                winc = 0;
            end else begin
                // Read
                @(posedge rclk); #1;
                rinc = 1;
                @(posedge rclk); #1;
                rinc = 0;
            end
            repeat(2) @(posedge rclk); #1;
            check_flags("C: random op flags");
        end

        // =============================================
        // Group D: Protocol/timing tests
        // =============================================

        // D1: Reset during operation
        wrstn = 0; rrstn = 0;
        #50;
        wrstn = 1; rrstn = 1;
        #50;

        for (i = 0; i < 8; i = i + 1) begin
            @(posedge wclk); #1;
            winc = 1;
            wdata = i[WIDTH-1:0] + 8'h50;
            @(posedge wclk); #1;
            winc = 0;
        end

        repeat(6) @(posedge rclk); #1;
        check_flags("D: before mid-reset");

        // Reset mid-operation
        wrstn = 0; rrstn = 0;
        #50;
        wrstn = 1; rrstn = 1;
        #50;

        repeat(6) @(posedge rclk); #1;
        check_flags("D: after mid-reset");

        // Write again after reset
        for (i = 0; i < 3; i = i + 1) begin
            @(posedge wclk); #1;
            winc = 1;
            wdata = i[WIDTH-1:0] + 8'h60;
            @(posedge wclk); #1;
            winc = 0;
        end

        repeat(8) @(posedge rclk); #1;
        check_flags("D: writes after reset");

        // Read them back
        for (i = 0; i < 3; i = i + 1) begin
            @(posedge rclk); #1;
            rinc = 1;
            @(posedge rclk); #1;
            rinc = 0;
            @(posedge rclk); #1;
            check_data("D: read after reset");
        end

        // D2: Back-to-back writes
        wrstn = 0; rrstn = 0;
        #50;
        wrstn = 1; rrstn = 1;
        #50;

        for (i = 0; i < 8; i = i + 1) begin
            @(posedge wclk); #1;
            winc = 1;
            wdata = i[WIDTH-1:0] + 8'h70;
        end
        @(posedge wclk); #1;
        winc = 0;

        repeat(8) @(posedge rclk); #1;
        check_flags("D: back-to-back writes");

        // Back-to-back reads
        for (i = 0; i < 8; i = i + 1) begin
            @(posedge rclk); #1;
            rinc = 1;
        end
        @(posedge rclk); #1;
        rinc = 0;

        repeat(6) @(posedge rclk); #1;
        check_flags("D: back-to-back reads");

        // D3: Idle periods
        wrstn = 0; rrstn = 0;
        #50;
        wrstn = 1; rrstn = 1;
        #100;

        check_flags("D: idle period");

        @(posedge wclk); #1;
        winc = 1;
        wdata = 8'hBB;
        @(posedge wclk); #1;
        winc = 0;

        #200;

        repeat(6) @(posedge rclk); #1;
        check_flags("D: after idle write");

        @(posedge rclk); #1;
        rinc = 1;
        @(posedge rclk); #1;
        rinc = 0;
        @(posedge rclk); #1;
        check_data("D: after idle read");

        // D4: Fill, drain, fill again
        wrstn = 0; rrstn = 0;
        #50;
        wrstn = 1; rrstn = 1;
        #50;

        // Fill
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(posedge wclk); #1;
            winc = 1;
            wdata = i[WIDTH-1:0] + 8'h80;
            @(posedge wclk); #1;
            winc = 0;
        end
        repeat(8) @(posedge wclk); #1;
        check_flags("D: full 1st fill");

        // Drain
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(posedge rclk); #1;
            rinc = 1;
            @(posedge rclk); #1;
            rinc = 0;
        end
        repeat(8) @(posedge rclk); #1;
        check_flags("D: empty after drain");

        // Fill again
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(posedge wclk); #1;
            winc = 1;
            wdata = i[WIDTH-1:0] + 8'hA0;
            @(posedge wclk); #1;
            winc = 0;
        end
        repeat(8) @(posedge wclk); #1;
        check_flags("D: full 2nd fill");

        // Read some back to verify
        for (i = 0; i < 4; i = i + 1) begin
            @(posedge rclk); #1;
            rinc = 1;
            @(posedge rclk); #1;
            rinc = 0;
            @(posedge rclk); #1;
            check_data("D: 2nd fill read");
        end

        // =============================================
        // Group E: Cycle-accurate CDC flag transition tracking
        // =============================================

        // E1: Fill to full, read one, track wfull deassert timing
        wrstn = 0; rrstn = 0;
        #50;
        wrstn = 1; rrstn = 1;
        #50;

        // Fill to full
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(posedge wclk); #1;
            winc = 1;
            wdata = i[WIDTH-1:0];
            @(posedge wclk); #1;
            winc = 0;
        end
        // Wait for full to propagate
        repeat(8) @(posedge wclk); #1;
        check_flags("E1: full before read");

        // Read one element to trigger wfull deassert
        @(posedge rclk); #1;
        rinc = 1;
        @(posedge rclk); #1;
        rinc = 0;

        // Track wfull at every wclk edge during CDC propagation window
        repeat(12) begin
            @(posedge wclk); #1;
            check_flags("E1: wfull deassert track");
        end

        // E2: Empty FIFO, write one, track rempty deassert timing
        wrstn = 0; rrstn = 0;
        #50;
        wrstn = 1; rrstn = 1;
        #50;

        repeat(6) @(posedge rclk); #1;
        check_flags("E2: empty after reset");

        // Write one element to trigger rempty deassert
        @(posedge wclk); #1;
        winc = 1;
        wdata = 8'hCC;
        @(posedge wclk); #1;
        winc = 0;

        // Track rempty at every rclk edge during CDC propagation window
        repeat(12) begin
            @(posedge rclk); #1;
            check_flags("E2: rempty deassert track");
        end

        // E3: Near-full/near-empty transitions with per-cycle tracking
        wrstn = 0; rrstn = 0;
        #50;
        wrstn = 1; rrstn = 1;
        #50;

        // Fill to DEPTH-1 (one short of full)
        for (i = 0; i < DEPTH - 1; i = i + 1) begin
            @(posedge wclk); #1;
            winc = 1;
            wdata = i[WIDTH-1:0] + 8'hC0;
            @(posedge wclk); #1;
            winc = 0;
        end
        repeat(8) @(posedge wclk); #1;
        check_flags("E3: near-full flags");

        // Write one more to make it full
        @(posedge wclk); #1;
        winc = 1;
        wdata = 8'hDF;
        @(posedge wclk); #1;
        winc = 0;

        // Track wfull assert timing
        repeat(12) begin
            @(posedge wclk); #1;
            check_flags("E3: wfull assert track");
        end

        // =============================================
        // Score Reporting
        // =============================================
        #100;
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
// Golden reference: dual_port_RAM
// =============================================
module golden_dual_port_RAM #(parameter DEPTH = 16, parameter WIDTH = 8)
(
    input wclk,
    input wenc,
    input [$clog2(DEPTH)-1:0] waddr,
    input [WIDTH-1:0] wdata,
    input rclk,
    input renc,
    input [$clog2(DEPTH)-1:0] raddr,
    output reg [WIDTH-1:0] rdata
);

reg [WIDTH-1:0] RAM_MEM [0:DEPTH-1];

always @(posedge wclk) begin
    if (wenc)
        RAM_MEM[waddr] <= wdata;
end

always @(posedge rclk) begin
    if (renc)
        rdata <= RAM_MEM[raddr];
end

endmodule

// =============================================
// Golden reference: asyn_fifo
// =============================================
module golden_asyn_fifo #(
    parameter WIDTH = 8,
    parameter DEPTH = 16
)(
    input                   wclk,
    input                   rclk,
    input                   wrstn,
    input                   rrstn,
    input                   winc,
    input                   rinc,
    input   [WIDTH-1:0]     wdata,

    output wire             wfull,
    output wire             rempty,
    output wire [WIDTH-1:0] rdata
);

parameter ADDR_WIDTH = $clog2(DEPTH);

reg     [ADDR_WIDTH:0]  waddr_bin;
reg     [ADDR_WIDTH:0]  raddr_bin;

always @(posedge wclk or negedge wrstn) begin
    if (~wrstn) begin
        waddr_bin <= 'd0;
    end
    else if (!wfull && winc) begin
        waddr_bin <= waddr_bin + 1'd1;
    end
end
always @(posedge rclk or negedge rrstn) begin
    if (~rrstn) begin
        raddr_bin <= 'd0;
    end
    else if (!rempty && rinc) begin
        raddr_bin <= raddr_bin + 1'd1;
    end
end

wire    [ADDR_WIDTH:0]  waddr_gray;
wire    [ADDR_WIDTH:0]  raddr_gray;
reg     [ADDR_WIDTH:0]  wptr;
reg     [ADDR_WIDTH:0]  rptr;
assign waddr_gray = waddr_bin ^ (waddr_bin >> 1);
assign raddr_gray = raddr_bin ^ (raddr_bin >> 1);
always @(posedge wclk or negedge wrstn) begin
    if (~wrstn) begin
        wptr <= 'd0;
    end
    else begin
        wptr <= waddr_gray;
    end
end
always @(posedge rclk or negedge rrstn) begin
    if (~rrstn) begin
        rptr <= 'd0;
    end
    else begin
        rptr <= raddr_gray;
    end
end

reg     [ADDR_WIDTH:0]  wptr_buff;
reg     [ADDR_WIDTH:0]  wptr_syn;
reg     [ADDR_WIDTH:0]  rptr_buff;
reg     [ADDR_WIDTH:0]  rptr_syn;
always @(posedge wclk or negedge wrstn) begin
    if (~wrstn) begin
        rptr_buff <= 'd0;
        rptr_syn <= 'd0;
    end
    else begin
        rptr_buff <= rptr;
        rptr_syn <= rptr_buff;
    end
end
always @(posedge rclk or negedge rrstn) begin
    if (~rrstn) begin
        wptr_buff <= 'd0;
        wptr_syn <= 'd0;
    end
    else begin
        wptr_buff <= wptr;
        wptr_syn <= wptr_buff;
    end
end

assign wfull = (wptr == {~rptr_syn[ADDR_WIDTH:ADDR_WIDTH-1], rptr_syn[ADDR_WIDTH-2:0]});
assign rempty = (rptr == wptr_syn);

wire    wen;
wire    ren;
wire [ADDR_WIDTH-1:0]   waddr;
wire [ADDR_WIDTH-1:0]   raddr;
assign wen = winc & !wfull;
assign ren = rinc & !rempty;
assign waddr = waddr_bin[ADDR_WIDTH-1:0];
assign raddr = raddr_bin[ADDR_WIDTH-1:0];

golden_dual_port_RAM #(.DEPTH(DEPTH), .WIDTH(WIDTH)) golden_dual_port_RAM_inst (
    .wclk  (wclk),
    .wenc  (wen),
    .waddr (waddr[ADDR_WIDTH-1:0]),
    .wdata (wdata),
    .rclk  (rclk),
    .renc  (ren),
    .raddr (raddr[ADDR_WIDTH-1:0]),
    .rdata (rdata)
);

endmodule
