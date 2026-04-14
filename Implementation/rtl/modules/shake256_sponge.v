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
    
    // One-hot FSM state encoding reduces decode depth/fanout for control nets.
    localparam [5:0] IDLE            = 6'b000001;
    localparam [5:0] ABSORB_BLOCK    = 6'b000010;
    localparam [5:0] PERMUTE_ABSORB  = 6'b000100;
    localparam [5:0] SQUEEZE_LOOP    = 6'b001000;
    localparam [5:0] PERMUTE_SQUEEZE = 6'b010000;
    localparam [5:0] DONE_ST         = 6'b100000;

    (* fsm_encoding = "none", max_fanout = 32 *) reg [5:0] state;

    (* use_clock_enable = "no" *) reg [`KECCAK_STATE_WIDTH-1:0] keccak_state;
    reg [`KECCAK_STATE_WIDTH-1:0] keccak_state_next;

    reg [15:0] absorb_remaining_reg;
    reg [15:0] squeeze_remaining_reg;
    reg absorb_done_after_perm_reg;
    reg perm_launch_reg;
    reg squeeze_has_data_reg;
    reg squeeze_last_reg;

    wire perm_in_valid;
    wire perm_out_valid;
    wire [`KECCAK_STATE_WIDTH-1:0] perm_out;

    // Centralized state update controls to improve replication/placement of control logic.
    wire st_idle;
    wire st_absorb;
    wire st_perm_absorb;
    wire st_squeeze;
    wire st_perm_squeeze;
    wire st_done;

    (* max_fanout = 32 *) wire absorb_has_data;
    (* max_fanout = 32 *) wire squeeze_has_data;
    (* max_fanout = 32 *) wire squeeze_fire;
    (* max_fanout = 32 *) wire squeeze_is_last;

    assign st_idle = state[0];
    assign st_absorb = state[1];
    assign st_perm_absorb = state[2];
    assign st_squeeze = state[3];
    assign st_perm_squeeze = state[4];
    assign st_done = state[5];

    assign absorb_has_data = (absorb_remaining_reg != 16'h0000);
    assign squeeze_has_data = squeeze_has_data_reg;
    assign squeeze_fire = st_squeeze && squeeze_data_ready && squeeze_has_data;
    assign squeeze_is_last = squeeze_last_reg;
    assign perm_in_valid = perm_launch_reg;
    
    // Instantiate Keccak permutation pipeline
    (* keep_hierarchy = "yes" *)
    keccak_permutation_pipeline u_keccak_perm (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(perm_in_valid),
        .state_in(keccak_state),
        .out_valid(perm_out_valid),
        .state_out(perm_out)
    );

    // Always-write next-state style avoids a high-fanout CE network on keccak_state.
    always @(*) begin
        keccak_state_next = keccak_state;

        if (st_idle && start) begin
            keccak_state_next = {`KECCAK_STATE_WIDTH{1'b0}};
        end else if (st_absorb && absorb_block_valid) begin
            keccak_state_next[1087:0] = keccak_state[1087:0] ^ absorb_block_data;
        end else if ((st_perm_absorb || st_perm_squeeze) && perm_out_valid) begin
            keccak_state_next = perm_out;
        end
    end
    
    // Sequential logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            keccak_state <= {`KECCAK_STATE_WIDTH{1'b0}};
            absorb_remaining_reg <= 16'h0000;
            squeeze_remaining_reg <= 16'h0000;
            absorb_done_after_perm_reg <= 1'b0;
            perm_launch_reg <= 1'b0;
            squeeze_has_data_reg <= 1'b0;
            squeeze_last_reg <= 1'b0;
        end else begin
            // Registered one-cycle launch pulse keeps control fanout short.
            perm_launch_reg <= 1'b0;
            keccak_state <= keccak_state_next;

            case (1'b1)
                st_idle: begin
                    if (start) begin
                        state <= ABSORB_BLOCK;
                        absorb_remaining_reg <= num_input_blocks;
                        squeeze_remaining_reg <= num_output_blocks;
                        absorb_done_after_perm_reg <= 1'b0;
                        squeeze_has_data_reg <= (num_output_blocks != 16'h0000);
                        squeeze_last_reg <= (num_output_blocks == 16'h0001);
                    end
                end

                st_absorb: begin
                    if (absorb_block_valid) begin
                        absorb_done_after_perm_reg <= !absorb_has_data || (absorb_remaining_reg == 16'h0001);
                        if (absorb_has_data)
                            absorb_remaining_reg <= absorb_remaining_reg - 16'h0001;
                        perm_launch_reg <= 1'b1;

                        // After each block, apply permutation.
                        state <= PERMUTE_ABSORB;
                    end
                end

                st_perm_absorb: begin
                    if (perm_out_valid) begin
                        if (absorb_done_after_perm_reg) begin
                            if (!squeeze_has_data) begin
                                state <= DONE_ST;
                            end else begin
                                state <= SQUEEZE_LOOP;
                            end
                        end else begin
                            state <= ABSORB_BLOCK;
                        end
                    end
                end

                st_squeeze: begin
                    if (squeeze_fire) begin
                        squeeze_remaining_reg <= squeeze_remaining_reg - 16'h0001;
                        squeeze_has_data_reg <= !squeeze_is_last;
                        squeeze_last_reg <= (squeeze_remaining_reg == 16'h0002);

                        if (squeeze_is_last) begin
                            state <= DONE_ST;
                        end else begin
                            perm_launch_reg <= 1'b1;
                            state <= PERMUTE_SQUEEZE;
                        end
                    end
                end

                st_perm_squeeze: begin
                    if (perm_out_valid) begin
                        state <= SQUEEZE_LOOP;
                    end
                end

                st_done: begin
                    state <= IDLE;
                    absorb_done_after_perm_reg <= 1'b0;
                    perm_launch_reg <= 1'b0;
                    squeeze_has_data_reg <= 1'b0;
                    squeeze_last_reg <= 1'b0;
                end

                default: begin
                    state <= IDLE;
                    absorb_done_after_perm_reg <= 1'b0;
                    perm_launch_reg <= 1'b0;
                    squeeze_has_data_reg <= 1'b0;
                    squeeze_last_reg <= 1'b0;
                end
            endcase
        end
    end
    
    // Output logic
    assign absorb_block_ready = st_absorb;
    assign squeeze_data_valid = st_squeeze && squeeze_has_data;
    assign squeeze_data = keccak_state[1087:0];  // Output lower 1088 bits (136 bytes)
    assign done = st_done;

endmodule
