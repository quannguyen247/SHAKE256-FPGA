`timescale 1ns / 1ps
`include "../utils/keccak_defs.vh"

module shake256_sponge (
    input wire clk,
    input wire rst_n,
    
    // Absorb control
    input wire absorb_valid,
    input wire [1087:0] absorb_in,
    output wire absorb_ready,

    // Squeeze control
    input wire squeeze_ready,
    output wire squeeze_valid,
    output wire [1087:0] squeeze_out,
    
    // Global control
    input wire start,
    output wire done,
    input wire [15:0] input_blocks,
    input wire [15:0] output_blocks
);

    localparam [5:0] ST_IDLE    = 6'b000001;
    localparam [5:0] ST_ABSORB  = 6'b000010;
    localparam [5:0] ST_START   = 6'b000100;
    localparam [5:0] ST_PERMUTE = 6'b001000;
    localparam [5:0] ST_SQUEEZE = 6'b010000; 
    localparam [5:0] ST_DONE    = 6'b100000;

    reg [5:0] curr_state, next_state;
    reg [`KECCAK_STATE_WIDTH-1:0] keccak_state;
    reg [15:0] absorb_cnt, squeeze_cnt;
    
    reg perm_start;
    wire perm_done;
    wire [`KECCAK_STATE_WIDTH-1:0] perm_out;

    keccak_permutation_pipeline u_keccak_perm (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(perm_start),
        .state_in(keccak_state),
        .out_valid(perm_done),
        .state_out(perm_out)
    );

    always @(*) begin
        next_state = curr_state; 

        case (curr_state)
            ST_IDLE: if (start) next_state = ST_ABSORB;
            ST_ABSORB: if (absorb_valid) next_state = ST_START;
            ST_START: next_state = ST_PERMUTE;
            ST_PERMUTE: begin
                if (perm_done) begin
                    if (absorb_cnt > 0) 
                        next_state = ST_ABSORB;
                    else if (squeeze_cnt > 0) 
                        next_state = ST_SQUEEZE;
                    else 
                        next_state = ST_DONE;
                end
            end
            ST_SQUEEZE: begin
                if (squeeze_ready && squeeze_cnt > 0) begin
                    if (squeeze_cnt == 16'd1) 
                        next_state = ST_DONE;
                    else 
                        next_state = ST_START;
                end
            end
            ST_DONE: next_state = ST_IDLE;
            default: next_state = ST_IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            keccak_state <= {`KECCAK_STATE_WIDTH{1'b0}};
            absorb_cnt <= 16'd0;
            squeeze_cnt <= 16'd0;
            curr_state <= ST_IDLE;
            perm_start <= 1'b0;
        end else begin
            curr_state <= next_state;
            perm_start <= (next_state == ST_START);
            case (curr_state)
                ST_IDLE: begin
                    if (start) begin
                        keccak_state <= {`KECCAK_STATE_WIDTH{1'b0}};
                        absorb_cnt <= input_blocks;
                        squeeze_cnt <= output_blocks;
                    end
                end
                ST_ABSORB: begin
                    if (absorb_valid) begin
                        keccak_state[1087:0] <= keccak_state[1087:0] ^ absorb_in;
                        if (absorb_cnt > 0) absorb_cnt <= absorb_cnt - 16'd1;
                    end
                end
                ST_PERMUTE: if (perm_done) keccak_state <= perm_out;
                ST_SQUEEZE: if (squeeze_ready && squeeze_cnt > 0) squeeze_cnt <= squeeze_cnt - 16'd1;
            endcase
        end
    end

    assign absorb_ready = (curr_state == ST_ABSORB);
    assign squeeze_valid = (curr_state == ST_SQUEEZE) && (squeeze_cnt > 0);
    assign squeeze_out = keccak_state[1087:0]; 
    assign done = (curr_state == ST_DONE);

endmodule