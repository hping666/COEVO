`timescale 1ns/1ps
module radix2_div(
    input wire clk,
    input wire rst,
    input wire [7:0] dividend,    
    input wire [7:0] divisor,    
    input wire sign,       

    input wire opn_valid,   
    output reg res_valid,   
    input wire res_ready,   
    output wire [15:0] result
);

    reg [7:0] dividend_save, divisor_save;
    reg [15:0] SR;                  
    reg [8:0] NEG_DIVISOR;        
    
    wire [7:0] REMAINER = SR[15:8];
    wire [7:0] QUOTIENT = SR[7:0];
    wire [7:0] remainer = (sign & dividend_save[7]) ? ((~REMAINER) + 8'd1) : REMAINER;
    wire [7:0] quotient = (sign & (dividend_save[7] ^ divisor_save[7])) ? ((~QUOTIENT) + 8'd1) : QUOTIENT;
    assign result = {remainer, quotient};

    wire CO;
    wire [8:0] sub_result;
    assign {CO, sub_result} = {1'b0, REMAINER} + NEG_DIVISOR;
    wire [8:0] mux_result = CO ? sub_result : {1'b0, REMAINER};

    reg [3:0] cnt;
    reg start_cnt;
    reg [7:0] dividend_abs_reg;
    reg [8:0] neg_divisor_reg;
    
    always @(*) begin
        if (sign & dividend[7])
            dividend_abs_reg = (~dividend) + 8'd1;
        else
            dividend_abs_reg = dividend;
    end
    
    always @(*) begin
        if (sign & divisor[7])
            neg_divisor_reg = {1'b1, divisor};
        else
            neg_divisor_reg = (~{1'b0, divisor}) + 9'd1;
    end
    
    always @(posedge clk) begin
        if (rst) begin
            SR <= 16'b0;
            dividend_save <= 8'b0;
            divisor_save <= 8'b0;
            cnt <= 4'b0;
            start_cnt <= 1'b0;
            NEG_DIVISOR <= 9'b0;
        end
        else if (~start_cnt & opn_valid & ~res_valid) begin
            cnt <= 4'd1;
            start_cnt <= 1'b1;
            dividend_save <= dividend;
            divisor_save <= divisor;
            SR <= {7'b0, dividend_abs_reg, 1'b0}; 
            NEG_DIVISOR <= neg_divisor_reg;
        end
        else if (start_cnt) begin
            if (cnt[3]) begin    
                cnt <= 4'b0;
                start_cnt <= 1'b0;
                SR[15:8] <= mux_result[7:0];
                SR[0] <= CO;
            end
            else begin
                cnt <= cnt + 4'd1;
                SR <= {mux_result[6:0], SR[7:1], CO, 1'b0}; 
            end
        end
    end

    wire data_go = res_valid & res_ready;
    always @(posedge clk) begin
        res_valid <= rst ? 1'b0 : cnt[3] ? 1'b1 : data_go ? 1'b0 : res_valid;
    end
endmodule