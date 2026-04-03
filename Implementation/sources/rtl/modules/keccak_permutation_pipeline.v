`timescale 1ns / 1ps

`include "../utils/keccak_defs.vh"

module keccak_permutation_pipeline (
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

    reg [`KECCAK_STATE_WIDTH-1:0] stage_state [0:`KECCAK_PIPE_STAGES];
    reg stage_valid [0:`KECCAK_PIPE_STAGES];

    wire [`KECCAK_STATE_WIDTH-1:0] stage_next0;
    wire [`KECCAK_STATE_WIDTH-1:0] stage_next1;
    wire [`KECCAK_STATE_WIDTH-1:0] stage_next2;
    wire [`KECCAK_STATE_WIDTH-1:0] stage_next3;

    integer k;

    keccak_stage6 u_stage0 (.state_in(stage_state[0]), .stage_idx(2'd0), .state_out(stage_next0));
    keccak_stage6 u_stage1 (.state_in(stage_state[1]), .stage_idx(2'd1), .state_out(stage_next1));
    keccak_stage6 u_stage2 (.state_in(stage_state[2]), .stage_idx(2'd2), .state_out(stage_next2));
    keccak_stage6 u_stage3 (.state_in(stage_state[3]), .stage_idx(2'd3), .state_out(stage_next3));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k = 0; k <= `KECCAK_PIPE_STAGES; k = k + 1) begin
                stage_state[k] <= {`KECCAK_STATE_WIDTH{1'b0}};
                stage_valid[k] <= 1'b0;
            end
        end else begin
            stage_state[0] <= state_in;
            stage_valid[0] <= in_valid;

            stage_state[1] <= stage_next0;
            stage_valid[1] <= stage_valid[0];

            stage_state[2] <= stage_next1;
            stage_valid[2] <= stage_valid[1];

            stage_state[3] <= stage_next2;
            stage_valid[3] <= stage_valid[2];

            stage_state[4] <= stage_next3;
            stage_valid[4] <= stage_valid[3];
        end
    end

    assign out_valid = stage_valid[`KECCAK_PIPE_STAGES];
    assign state_out = stage_state[`KECCAK_PIPE_STAGES];

endmodule