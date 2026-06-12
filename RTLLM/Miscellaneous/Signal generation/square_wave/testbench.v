module square_wave_tb;

    reg clk_tb = 0;        
    reg [8:0] freq_tb = 8'b0000100; 
    wire wave_out_tb;       
    integer ones_count = 0;  // Counter for consecutive ones
    integer zeros_count = 0; // Counter for consecutive zeros
    integer toggle_count = 0;
    reg prev_wave;
    integer error = 0;       // Error flag

    square_wave square_wave_inst (
        .clk(clk_tb),
        .freq(freq_tb),
        .wave_out(wave_out_tb)
    );

    initial begin
        // Monitor output
        // $monitor("Time: %0t | Clock: %b | Frequency: %d | Square Wave Output: %b | Error: %d", $time, clk_tb, freq_tb, wave_out_tb, error);

        // Simulate for a certain time
        prev_wave = 0;
        repeat (200) begin
            if (wave_out_tb == 1) begin
                ones_count = ones_count + 1;
                zeros_count = 0;
            end else begin
                zeros_count = zeros_count + 1;
                ones_count = 0;
            end
            if (wave_out_tb !== prev_wave) toggle_count = toggle_count + 1;
            prev_wave = wave_out_tb;
            if (ones_count > 8 || zeros_count > 8) begin
                $display("Error: More than 8 consecutive same values at time %0t", $time);
                error = 1;
                $finish;
            end
            #5;
        end
        if (toggle_count < 2) begin
            $display("Error: Output did not toggle");
            error = 1;
        end
        if (error == 0) begin
            $display("=========== Your Design Passed ===========");
        end
        $finish;  // Finish the simulation
    end

    always #5 clk_tb = ~clk_tb;

endmodule