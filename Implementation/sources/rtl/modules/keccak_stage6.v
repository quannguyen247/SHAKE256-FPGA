`timescale 1ns / 1ps

`include "../utils/keccak_defs.vh"

module keccak_stage6 (
    state_in,
    stage_idx,
    state_out
);
    input  [`KECCAK_STATE_WIDTH-1:0] state_in;
    input  [1:0] stage_idx;
    output [`KECCAK_STATE_WIDTH-1:0] state_out;

    wire [`KECCAK_STATE_WIDTH-1:0] s0;
    wire [`KECCAK_STATE_WIDTH-1:0] s1;
    wire [`KECCAK_STATE_WIDTH-1:0] s2;
    wire [`KECCAK_STATE_WIDTH-1:0] s3;
    wire [`KECCAK_STATE_WIDTH-1:0] s4;
    wire [`KECCAK_STATE_WIDTH-1:0] s5;

    wire [4:0] base_round;

    assign base_round = ({3'b000, stage_idx} * 5'd6);

    keccak_round r0 (.state_in(state_in), .round_idx(base_round + 5'd0), .state_out(s0));
    keccak_round r1 (.state_in(s0),      .round_idx(base_round + 5'd1), .state_out(s1));
    keccak_round r2 (.state_in(s1),      .round_idx(base_round + 5'd2), .state_out(s2));
    keccak_round r3 (.state_in(s2),      .round_idx(base_round + 5'd3), .state_out(s3));
    keccak_round r4 (.state_in(s3),      .round_idx(base_round + 5'd4), .state_out(s4));
    keccak_round r5 (.state_in(s4),      .round_idx(base_round + 5'd5), .state_out(s5));

    assign state_out = s5;

endmodule