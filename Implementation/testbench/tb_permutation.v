`timescale 1ns / 1ps

module tb_permutation;
    reg clk, rst_n, in_valid;
    reg [1599:0] state_in;
    wire [1599:0] state_out;
    wire out_valid;

    keccak_permutation_pipeline u_perm (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
        .state_in(state_in), .out_valid(out_valid), .state_out(state_out)
    );

    initial begin
        clk = 0;
        forever #2.5 clk = ~clk;
    end

    initial begin
        rst_n = 0; in_valid = 0; state_in = 0;

        repeat(5) @(posedge clk);
        rst_n = 1;

        @(negedge clk);
        state_in = {1600{1'b1}};
        in_valid = 1;     
        @(negedge clk);
        in_valid = 0;

        @(posedge out_valid);
        repeat(5) @(posedge clk);
        $finish;
    end

endmodule