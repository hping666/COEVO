`timescale 1ns/1ps

module clkgenerator_tb;

    wire clk_tb; // Clock signal driven by DUT output
    reg res = 1'b0;
    integer error = 0;
    // Instantiate the clkgenerator module
    clkgenerator clkgenerator_inst (
        .clk(clk_tb)
    );

    initial begin
        // Monitor the clock signal
        // $monitor("Time=%0t, clk=%b", $time, clk_tb);

        // Simulate for a certain number of clock cycles
        repeat (20) begin // Simulate 20 clock cycles
            #4; // Sample slightly before the toggle edge to avoid race condition
            error = (res == clk_tb) ? error :error+1;
            res = res + 1;
            #1; // Complete the 5ns half-period
            // $display(clk_tb);
        end
        if (error == 0) begin
        $display("=========== Your Design Passed ===========");
        end
        else begin
        $display("=========== Test completed with %d failures ===========", error);
        end
        // Finish simulation
        $finish;
    end

endmodule