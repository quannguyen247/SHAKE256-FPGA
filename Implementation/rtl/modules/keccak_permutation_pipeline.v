`timescale 1ns / 1ps

`include "../utils/keccak_defs.vh"

(* keep_hierarchy = "yes" *)
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

    // Iterative permutation core: one round per cycle.
    // This reduces LUT usage significantly versus 24-round unrolled datapaths.
    reg [`KECCAK_STATE_WIDTH-1:0] state_reg;
    reg [`KECCAK_STATE_WIDTH-1:0] state_out_reg;
    reg [4:0] round_idx_reg;
    reg busy_reg;
    reg out_valid_reg;

    wire [`KECCAK_STATE_WIDTH-1:0] round_state_next;

    (* keep_hierarchy = "yes" *)
    keccak_round u_round (
        .state_in(state_reg),
        .round_idx(round_idx_reg),
        .state_out(round_state_next)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_reg <= {`KECCAK_STATE_WIDTH{1'b0}};
            state_out_reg <= {`KECCAK_STATE_WIDTH{1'b0}};
            round_idx_reg <= 5'd0;
            busy_reg <= 1'b0;
            out_valid_reg <= 1'b0;
        end else begin
            // out_valid is a one-cycle pulse when a permutation completes.
            out_valid_reg <= 1'b0;

            if (busy_reg) begin
                state_reg <= round_state_next;

                if (round_idx_reg == (`KECCAK_NUM_ROUNDS - 1)) begin
                    busy_reg <= 1'b0;
                    round_idx_reg <= 5'd0;
                    out_valid_reg <= 1'b1;
                    state_out_reg <= round_state_next;
                end else begin
                    round_idx_reg <= round_idx_reg + 5'd1;
                end
            end else if (in_valid) begin
                state_reg <= state_in;
                round_idx_reg <= 5'd0;
                busy_reg <= 1'b1;
            end
        end
    end

    assign out_valid = out_valid_reg;
    assign state_out = state_out_reg;

endmodule