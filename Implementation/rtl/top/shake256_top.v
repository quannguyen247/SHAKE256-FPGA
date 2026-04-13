`timescale 1ns / 1ps

`include "../utils/keccak_defs.vh"

module shake256_top (
    clk,
    rst_n,
    in_valid,
    state_in,
    out_valid,
    state_out
);
    input clk;
    input rst_n;
    input in_valid;
    input [`KECCAK_STATE_WIDTH-1:0] state_in;
    output out_valid;
    output [`KECCAK_STATE_WIDTH-1:0] state_out;

    keccak_permutation_pipeline u_perm (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .state_in(state_in),
        .out_valid(out_valid),
        .state_out(state_out)
    );

endmodule