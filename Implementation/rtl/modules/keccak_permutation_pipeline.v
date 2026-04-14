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

    // Two-phase iterative permutation core.
    // Phase 0: Theta + RhoPi
    // Phase 1: Chi + Iota
    (* use_clock_enable = "no" *) reg [`KECCAK_STATE_WIDTH-1:0] state_reg;
    reg [`KECCAK_STATE_WIDTH-1:0] stage_mid_reg;
    reg [`KECCAK_STATE_WIDTH-1:0] state_out_reg;
    (* max_fanout = 32 *) reg [4:0] round_idx_reg;
    reg [63:0] round_const_reg;
    (* max_fanout = 32 *) reg busy_reg;
    (* max_fanout = 32 *) reg phase_reg;
    (* max_fanout = 32 *) reg start_req_reg;
    reg [`KECCAK_STATE_WIDTH-1:0] start_state_reg;
    reg out_valid_reg;

    wire [`KECCAK_STATE_WIDTH-1:0] stage_trp_next;
    wire [`KECCAK_STATE_WIDTH-1:0] stage_ci_next;
    (* max_fanout = 32 *) wire load_state_fire;
    (* max_fanout = 32 *) wire round_commit_fire;
    wire [`KECCAK_STATE_WIDTH-1:0] state_reg_next;

    (* keep_hierarchy = "yes" *)
    keccak_theta_rho_pi_stage u_stage_trp (
        .state_in(state_reg),
        .state_out(stage_trp_next)
    );

    (* keep_hierarchy = "yes" *)
    keccak_chi_iota_stage u_stage_ci (
        .state_in(stage_mid_reg),
        .round_const(round_const_reg),
        .state_out(stage_ci_next)
    );

    function [63:0] round_constant;
        input [4:0] idx;
        begin
            case (idx)
                5'd0:  round_constant = 64'h0000000000000001;
                5'd1:  round_constant = 64'h0000000000008082;
                5'd2:  round_constant = 64'h800000000000808a;
                5'd3:  round_constant = 64'h8000000080008000;
                5'd4:  round_constant = 64'h000000000000808b;
                5'd5:  round_constant = 64'h0000000080000001;
                5'd6:  round_constant = 64'h8000000080008081;
                5'd7:  round_constant = 64'h8000000000008009;
                5'd8:  round_constant = 64'h000000000000008a;
                5'd9:  round_constant = 64'h0000000000000088;
                5'd10: round_constant = 64'h0000000080008009;
                5'd11: round_constant = 64'h000000008000000a;
                5'd12: round_constant = 64'h000000008000808b;
                5'd13: round_constant = 64'h800000000000008b;
                5'd14: round_constant = 64'h8000000000008089;
                5'd15: round_constant = 64'h8000000000008003;
                5'd16: round_constant = 64'h8000000000008002;
                5'd17: round_constant = 64'h8000000000000080;
                5'd18: round_constant = 64'h000000000000800a;
                5'd19: round_constant = 64'h800000008000000a;
                5'd20: round_constant = 64'h8000000080008081;
                5'd21: round_constant = 64'h8000000000008080;
                5'd22: round_constant = 64'h0000000080000001;
                5'd23: round_constant = 64'h8000000080008008;
                default: round_constant = 64'h0;
            endcase
        end
    endfunction

    assign load_state_fire = (!busy_reg) && start_req_reg;
    assign round_commit_fire = busy_reg && phase_reg;
    assign state_reg_next = load_state_fire ? start_state_reg :
                            round_commit_fire ? stage_ci_next : state_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_reg <= {`KECCAK_STATE_WIDTH{1'b0}};
            stage_mid_reg <= {`KECCAK_STATE_WIDTH{1'b0}};
            state_out_reg <= {`KECCAK_STATE_WIDTH{1'b0}};
            round_idx_reg <= 5'd0;
            round_const_reg <= 64'h0;
            busy_reg <= 1'b0;
            phase_reg <= 1'b0;
            start_req_reg <= 1'b0;
            start_state_reg <= {`KECCAK_STATE_WIDTH{1'b0}};
            out_valid_reg <= 1'b0;
        end else begin
            // out_valid is a one-cycle pulse when a permutation completes.
            out_valid_reg <= 1'b0;
            state_reg <= state_reg_next;

            if (!busy_reg) begin
                phase_reg <= 1'b0;
                if (start_req_reg) begin
                    round_idx_reg <= 5'd0;
                    busy_reg <= 1'b1;
                    start_req_reg <= 1'b0;
                end else if (in_valid) begin
                    start_state_reg <= state_in;
                    start_req_reg <= 1'b1;
                end
            end else begin
                if (!phase_reg) begin
                    stage_mid_reg <= stage_trp_next;
                    round_const_reg <= round_constant(round_idx_reg);
                    phase_reg <= 1'b1;
                end else begin
                    if (round_idx_reg == (`KECCAK_NUM_ROUNDS - 1)) begin
                        busy_reg <= 1'b0;
                        phase_reg <= 1'b0;
                        round_idx_reg <= 5'd0;
                        out_valid_reg <= 1'b1;
                        state_out_reg <= stage_ci_next;
                    end else begin
                        round_idx_reg <= round_idx_reg + 5'd1;
                        phase_reg <= 1'b0;
                    end
                end
            end
        end
    end

    assign out_valid = out_valid_reg;
    assign state_out = state_out_reg;

endmodule
