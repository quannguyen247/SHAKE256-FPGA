`timescale 1ns / 1ps

`include "../utils/keccak_defs.vh"

// SHAKE256 final-block padding helper.
//
// Input convention:
// - msg_block_in carries up to 136 message bytes in its low bytes.
// - msg_len_bytes indicates how many bytes in msg_block_in are valid for the last chunk.
//
// Output convention:
// - pad_block0_out is always the first block to absorb.
// - if needs_second_block is 1, absorb pad_block1_out immediately after pad_block0_out.
//
// SHAKE256 suffix and pad10*1:
// - domain separation suffix byte = 0x1F
// - final bit of rate block (byte 135 bit 7) is set via XOR with 0x80.

module shake256_pad_block (
    msg_block_in,
    msg_len_bytes,
    pad_block0_out,
    pad_block1_out,
    needs_second_block
);
    input  [1087:0] msg_block_in;
    input  [7:0]    msg_len_bytes;

    output [1087:0] pad_block0_out;
    output [1087:0] pad_block1_out;
    output          needs_second_block;

    reg [1087:0] pad_block0_out;
    reg [1087:0] pad_block1_out;
    reg          needs_second_block;

    reg [7:0] valid_len;
    integer i;

    always @* begin
        pad_block0_out = 1088'd0;
        pad_block1_out = 1088'd0;
        needs_second_block = 1'b0;

        if (msg_len_bytes > `SHAKE256_RATE_BYTES) begin
            valid_len = `SHAKE256_RATE_BYTES;
        end else begin
            valid_len = msg_len_bytes;
        end

        // Copy valid message bytes into block 0.
        for (i = 0; i < `SHAKE256_RATE_BYTES; i = i + 1) begin
            if (i < valid_len) begin
                pad_block0_out[(8 * i) +: 8] = msg_block_in[(8 * i) +: 8];
            end
        end

        if (valid_len < `SHAKE256_RATE_BYTES) begin
            // Append suffix byte at first unused byte position.
            for (i = 0; i < `SHAKE256_RATE_BYTES; i = i + 1) begin
                if (i == valid_len) begin
                    pad_block0_out[(8 * i) +: 8] = pad_block0_out[(8 * i) +: 8] ^ 8'h1F;
                end
            end

            // Apply pad10*1 ending bit to last byte of rate block.
            pad_block0_out[(8 * (`SHAKE256_RATE_BYTES - 1)) +: 8] =
                pad_block0_out[(8 * (`SHAKE256_RATE_BYTES - 1)) +: 8] ^ 8'h80;
        end else begin
            // Full block case: absorb message block first, then absorb a second padding block.
            pad_block0_out = msg_block_in;
            pad_block1_out[7:0] = 8'h1F;
            pad_block1_out[(8 * (`SHAKE256_RATE_BYTES - 1)) +: 8] = 8'h80;
            needs_second_block = 1'b1;
        end
    end

endmodule
