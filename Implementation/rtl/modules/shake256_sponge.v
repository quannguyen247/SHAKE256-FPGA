`timescale 1ns / 1ps

`include "../utils/keccak_defs.vh"

// SHAKE256 Sponge Construction
// Rate: 136 bytes (1088 bits)
// Capacity: 512 bits
//
// FSM Flow:
//   IDLE -> (start) -> ABSORB_BLOCK -> PERMUTE -> (more blocks?) -> SQUEEZE
//   SQUEEZE -> (more output?) -> PERMUTE -> SQUEEZE -> DONE

module shake256_sponge (
    clk,
    rst_n,
    
    // Absorb control
    absorb_block_valid,
    absorb_block_data,
    absorb_block_ready,
    
    // Squeeze output
    squeeze_data_valid,
    squeeze_data,
    squeeze_data_ready,
    
    // Control
    start,
    done,
    num_input_blocks,
    num_output_blocks
);

    input clk;
    input rst_n;
    
    // Absorb: 136 bytes (1088 bits) per block
    input absorb_block_valid;
    input [1087:0] absorb_block_data;
    output absorb_block_ready;
    
    // Squeeze: 136 bytes per block
    output squeeze_data_valid;
    output [1087:0] squeeze_data;
    input squeeze_data_ready;
    
    // Control
    input start;
    output done;
    input [15:0] num_input_blocks;   // Number of 136-byte input blocks to absorb
    input [15:0] num_output_blocks;  // Number of 136-byte output blocks to squeeze
    
    // FSM states
    parameter IDLE            = 3'd0;
    parameter ABSORB_BLOCK    = 3'd1;
    parameter PERMUTE_ABSORB  = 3'd2;
    parameter SQUEEZE_LOOP    = 3'd3;
    parameter PERMUTE_SQUEEZE = 3'd4;
    parameter DONE_ST         = 3'd5;
    
    reg [2:0] state;

    reg [`KECCAK_STATE_WIDTH-1:0] keccak_state;

    reg [15:0] absorb_count;
    reg [15:0] squeeze_count;
    reg [15:0] num_input_blocks_reg;
    reg [15:0] num_output_blocks_reg;

    reg perm_in_valid;
    reg perm_waiting;
    wire perm_out_valid;
    wire [`KECCAK_STATE_WIDTH-1:0] perm_out;
    
    // Instantiate Keccak permutation pipeline
    keccak_permutation_pipeline u_keccak_perm (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(perm_in_valid),
        .state_in(keccak_state),
        .out_valid(perm_out_valid),
        .state_out(perm_out)
    );
    
    // Sequential logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            keccak_state <= {`KECCAK_STATE_WIDTH{1'b0}};
            absorb_count <= 16'h0000;
            squeeze_count <= 16'h0000;
            num_input_blocks_reg <= 16'h0000;
            num_output_blocks_reg <= 16'h0000;
            perm_in_valid <= 1'b0;
            perm_waiting <= 1'b0;
        end else begin
            // One-cycle launch pulse for permutation core.
            perm_in_valid <= 1'b0;

            case (state)
                IDLE: begin
                    if (start) begin
                        state <= ABSORB_BLOCK;
                        keccak_state <= {`KECCAK_STATE_WIDTH{1'b0}};
                        absorb_count <= 16'h0000;
                        squeeze_count <= 16'h0000;
                        num_input_blocks_reg <= num_input_blocks;
                        num_output_blocks_reg <= num_output_blocks;
                        perm_waiting <= 1'b0;
                    end
                end

                ABSORB_BLOCK: begin
                    if (absorb_block_valid) begin
                        // XOR input block into rate (lower 1088 bits).
                        keccak_state[1087:0] <= keccak_state[1087:0] ^ absorb_block_data;
                        absorb_count <= absorb_count + 16'h0001;

                        // After each block, apply permutation.
                        state <= PERMUTE_ABSORB;
                        perm_in_valid <= 1'b1;
                        perm_waiting <= 1'b1;
                    end
                end

                PERMUTE_ABSORB: begin
                    if (perm_waiting && perm_out_valid) begin
                        keccak_state <= perm_out;
                        perm_waiting <= 1'b0;

                        if (absorb_count >= num_input_blocks_reg) begin
                            squeeze_count <= 16'h0000;
                            if (num_output_blocks_reg == 16'h0000) begin
                                state <= DONE_ST;
                            end else begin
                                state <= SQUEEZE_LOOP;
                            end
                        end else begin
                            state <= ABSORB_BLOCK;
                        end
                    end
                end

                SQUEEZE_LOOP: begin
                    if (squeeze_data_ready && (squeeze_count < num_output_blocks_reg)) begin
                        squeeze_count <= squeeze_count + 16'h0001;

                        if (squeeze_count + 16'h0001 >= num_output_blocks_reg) begin
                            state <= DONE_ST;
                        end else begin
                            state <= PERMUTE_SQUEEZE;
                            perm_in_valid <= 1'b1;
                            perm_waiting <= 1'b1;
                        end
                    end
                end

                PERMUTE_SQUEEZE: begin
                    if (perm_waiting && perm_out_valid) begin
                        keccak_state <= perm_out;
                        perm_waiting <= 1'b0;
                        state <= SQUEEZE_LOOP;
                    end
                end

                DONE_ST: begin
                    state <= IDLE;
                    perm_waiting <= 1'b0;
                end

                default: begin
                    state <= IDLE;
                    perm_waiting <= 1'b0;
                end
            endcase
        end
    end
    
    // Output logic
    assign absorb_block_ready = (state == ABSORB_BLOCK);
    assign squeeze_data_valid = (state == SQUEEZE_LOOP) && (squeeze_count < num_output_blocks_reg);
    assign squeeze_data = keccak_state[1087:0];  // Output lower 1088 bits (136 bytes)
    assign done = (state == DONE_ST);

endmodule
