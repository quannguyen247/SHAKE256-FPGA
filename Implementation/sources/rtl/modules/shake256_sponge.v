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
    parameter IDLE           = 4'd0;
    parameter ABSORB_BLOCK   = 4'd1;
    parameter PERMUTE_ABSORB = 4'd2;
    parameter SQUEEZE_LOOP   = 4'd3;
    parameter PERMUTE_SQUEEZE = 4'd4;
    parameter DONE_ST        = 4'd5;
    
    reg [3:0] state;
    reg [3:0] state_next;
    
    reg [`KECCAK_STATE_WIDTH-1:0] keccak_state;
    reg [`KECCAK_STATE_WIDTH-1:0] keccak_state_next;
    
    reg [15:0] absorb_count;
    reg [15:0] absorb_count_next;
    
    reg [15:0] squeeze_count;
    reg [15:0] squeeze_count_next;
    
    reg perm_in_valid;
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
            perm_in_valid <= 1'b0;
        end else begin
            state <= state_next;
            keccak_state <= keccak_state_next;
            absorb_count <= absorb_count_next;
            squeeze_count <= squeeze_count_next;
            perm_in_valid <= (state_next == PERMUTE_ABSORB) || (state_next == PERMUTE_SQUEEZE);
        end
    end
    
    // Combinational next-state logic
    always @* begin
        state_next = state;
        keccak_state_next = keccak_state;
        absorb_count_next = absorb_count;
        squeeze_count_next = squeeze_count;
        
        case (state)
            IDLE: begin
                if (start) begin
                    state_next = ABSORB_BLOCK;
                    keccak_state_next = {`KECCAK_STATE_WIDTH{1'b0}};
                    absorb_count_next = 16'h0000;
                    squeeze_count_next = 16'h0000;
                end
            end
            
            ABSORB_BLOCK: begin
                if (absorb_block_valid) begin
                    // XOR input block into rate (lower 1088 bits)
                    keccak_state_next[1087:0] = keccak_state[1087:0] ^ absorb_block_data;
                    absorb_count_next = absorb_count + 16'h0001;
                    
                    // After each block, apply permutation
                    state_next = PERMUTE_ABSORB;
                end
            end
            
            PERMUTE_ABSORB: begin
                if (perm_out_valid) begin
                    keccak_state_next = perm_out;
                    
                    // Check if more absorption needed
                    if (absorb_count >= num_input_blocks) begin
                        // Done absorbing, start squeezing
                        state_next = SQUEEZE_LOOP;
                        squeeze_count_next = 16'h0000;
                    end else begin
                        // More blocks to absorb
                        state_next = ABSORB_BLOCK;
                    end
                end
            end
            
            SQUEEZE_LOOP: begin
                if (squeeze_data_ready && squeeze_count < num_output_blocks) begin
                    squeeze_count_next = squeeze_count + 16'h0001;
                    
                    if (squeeze_count + 16'h0001 >= num_output_blocks) begin
                        // All output squeezed
                        state_next = DONE_ST;
                    end else begin
                        // Need more output, apply permutation again
                        state_next = PERMUTE_SQUEEZE;
                    end
                end
            end
            
            PERMUTE_SQUEEZE: begin
                if (perm_out_valid) begin
                    keccak_state_next = perm_out;
                    state_next = SQUEEZE_LOOP;
                end
            end
            
            DONE_ST: begin
                state_next = IDLE;
            end
            
            default: state_next = IDLE;
        endcase
    end
    
    // Output logic
    assign absorb_block_ready = (state == ABSORB_BLOCK);
    assign squeeze_data_valid = (state == SQUEEZE_LOOP) && (squeeze_count < num_output_blocks);
    assign squeeze_data = keccak_state[1087:0];  // Output lower 1088 bits (136 bytes)
    assign done = (state == DONE_ST);

endmodule
