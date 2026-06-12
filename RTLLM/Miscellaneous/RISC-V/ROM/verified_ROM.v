module ROM (
    input wire [7:0] addr,        // 8-bit Address input
    output reg [15:0] dout        // 16-bit Data output
);

    // Declare a memory array of 256 locations, each 16 bits wide, initialized with fixed data
    reg [15:0] mem [0:255];

    // Initial block to initialize all ROM locations
    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1)
            mem[i] = {2{8'hA0 + i[7:0] * 8'h11}};
    end

    // Combinational logic: Read data from the ROM at the specified address
    always @(*) begin
        dout = mem[addr];
    end
endmodule