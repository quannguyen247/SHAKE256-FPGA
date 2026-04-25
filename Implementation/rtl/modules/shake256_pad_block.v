`timescale 1ns / 1ps
`include "keccak_defs.vh"

module shake256_pad_block(
    input wire [1087:0] msg_block_in,
    input wire [7:0] msg_len_bytes,
    output reg [1087:0] pad_block0_out,
    output reg [1087:0] pad_block1_out,
    output reg need_block2
);

    reg [7:0] valid_bytes;
    integer i;

    always @(*) begin
        pad_block0_out = {`SHAKE256_RATE_BITS{1'b0}};
        pad_block1_out = {`SHAKE256_RATE_BITS{1'b0}};
        need_block2 = 1'b0;

        // Clamp gia tri valid_bytes vao khoang [0,136]
        if (msg_len_bytes > `SHAKE256_RATE_BYTES) begin
            valid_bytes = `SHAKE256_RATE_BYTES;
        end else begin
            valid_bytes = msg_len_bytes;
        end

        // Sao chep valid_bytes tu msg_block_in sang pad_block0_out
        for (i = 0; i < `SHAKE256_RATE_BYTES; i = i + 1) begin
            if (i < valid_bytes) begin
                pad_block0_out[(8 * i) +: 8] = msg_block_in[(8 * i) +: 8];
            end
        end

        // Ap dung multi-rate padding 
        if (valid_bytes < `SHAKE256_RATE_BYTES) begin 
            pad_block0_out[(8 * valid_bytes) +: 8] = 8'h1F; 
            pad_block0_out[(8 * (`SHAKE256_RATE_BYTES - 1)) +: 8] = pad_block0_out[(8 * (`SHAKE256_RATE_BYTES - 1)) +: 8] | 8'h80;
        end else begin
            pad_block0_out = msg_block_in;
            pad_block1_out[7:0] = 8'h1F; 
            pad_block1_out[(8 * (`SHAKE256_RATE_BYTES - 1)) +: 8] = 8'h80; 
            need_block2 = 1'b1; 
        end   
    end
    
endmodule