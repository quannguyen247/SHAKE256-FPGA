`timescale 1ns / 1ps

`include "../rtl/utils/keccak_defs.vh"

module tb_shake256_pad_block;

    reg  [1087:0] msg_block_in;
    reg  [7:0]    msg_len_bytes;
    wire [1087:0] pad_block0_out;
    wire [1087:0] pad_block1_out;
    wire          needs_second_block;

    integer error_count;

    shake256_pad_block u_dut (
        .msg_block_in(msg_block_in),
        .msg_len_bytes(msg_len_bytes),
        .pad_block0_out(pad_block0_out),
        .pad_block1_out(pad_block1_out),
        .needs_second_block(needs_second_block)
    );

    initial begin
        error_count = 0;

        // Case 0: empty message tail.
        msg_block_in = 1088'd0;
        msg_len_bytes = 8'd0;
        #1;

        if (needs_second_block !== 1'b0) begin
            $display("ERROR case0: needs_second_block should be 0");
            error_count = error_count + 1;
        end
        if (pad_block0_out[7:0] !== 8'h1F) begin
            $display("ERROR case0: suffix byte should be 0x1F");
            error_count = error_count + 1;
        end
        if (pad_block0_out[1087:1080] !== 8'h80) begin
            $display("ERROR case0: last byte should contain 0x80");
            error_count = error_count + 1;
        end

        // Case 1: one-byte tail.
        msg_block_in = 1088'd0;
        msg_block_in[7:0] = 8'h61;
        msg_len_bytes = 8'd1;
        #1;

        if (pad_block0_out[7:0] !== 8'h61) begin
            $display("ERROR case1: first byte should keep message data");
            error_count = error_count + 1;
        end
        if (pad_block0_out[15:8] !== 8'h1F) begin
            $display("ERROR case1: suffix byte should be at index 1");
            error_count = error_count + 1;
        end

        // Case 2: exactly full rate block.
        msg_block_in = {136{8'hA5}};
        msg_len_bytes = 8'd136;
        #1;

        if (needs_second_block !== 1'b1) begin
            $display("ERROR case2: full block should request second block");
            error_count = error_count + 1;
        end
        if (pad_block0_out !== msg_block_in) begin
            $display("ERROR case2: block0 should equal original full block");
            error_count = error_count + 1;
        end
        if (pad_block1_out[7:0] !== 8'h1F) begin
            $display("ERROR case2: block1 suffix should be 0x1F");
            error_count = error_count + 1;
        end
        if (pad_block1_out[1087:1080] !== 8'h80) begin
            $display("ERROR case2: block1 last byte should be 0x80");
            error_count = error_count + 1;
        end

        if (error_count == 0) begin
            $display("tb_shake256_pad_block: PASS");
        end else begin
            $display("tb_shake256_pad_block: FAIL (%0d errors)", error_count);
        end

        $finish;
    end

endmodule
