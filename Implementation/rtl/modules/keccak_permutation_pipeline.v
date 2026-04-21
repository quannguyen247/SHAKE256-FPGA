`timescale 1ns / 1ps
`include "../utils/keccak_defs.vh"

module keccak_permutation_pipeline (
    input wire clk,
    input wire rst_n,
    input wire in_valid,
    input wire [`KECCAK_STATE_WIDTH-1:0] state_in,
    output reg out_valid,
    output reg [`KECCAK_STATE_WIDTH-1:0] state_out
);

    `include "../utils/keccak_funcs.vh"
    
    localparam ST_IDLE = 3'b001;
    localparam ST_TRP = 3'b010; 
    localparam ST_CI = 3'b100; 

    reg [`KECCAK_STATE_WIDTH-1:0] state_reg, trp_mid_reg;
    wire [`KECCAK_STATE_WIDTH-1:0] trp_next, ci_next;
    reg [4:0] round_ctr;
    reg [2:0] curr_state, next_state;

    keccak_theta_rho_pi_stage u_stage_trp (
        .state_in(state_reg),
        .state_out(trp_next)
    );

    keccak_chi_iota_stage u_stage_ci (
        .state_in(trp_mid_reg),
        .round_const(round_constant(round_ctr)),
        .state_out(ci_next)
    );

    always @(*) begin
        next_state = curr_state;
        case (curr_state)
            ST_IDLE: if (in_valid) next_state = ST_TRP;
            ST_TRP: next_state = ST_CI;
            ST_CI: begin
                if (round_ctr == (`KECCAK_NUM_ROUNDS - 1))
                    next_state = ST_IDLE;
                else
                    next_state = ST_TRP;
            end
            default: next_state = ST_IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            curr_state <= ST_IDLE;
            state_reg <= {`KECCAK_STATE_WIDTH{1'b0}};
            trp_mid_reg <= {`KECCAK_STATE_WIDTH{1'b0}};
            state_out <= {`KECCAK_STATE_WIDTH{1'b0}};
            round_ctr <= 5'd0;
            out_valid <= 1'b0;
        end else begin
            curr_state <= next_state;
            out_valid <= 1'b0; 
            case (next_state)
                ST_IDLE: begin
                    if (curr_state == ST_CI && round_ctr == 23) begin
                        out_valid <= 1'b1;
                        state_out <= ci_next; 
                    end
                end
                ST_TRP: begin
                    if (curr_state == ST_IDLE) begin
                        state_reg <= state_in;
                        round_ctr <= 5'd0;
                    end else if (curr_state == ST_CI) begin
                        state_reg <= ci_next;
                        round_ctr <= round_ctr + 5'd1;
                    end
                end
                ST_CI: trp_mid_reg <= trp_next;
            endcase
        end
    end

endmodule