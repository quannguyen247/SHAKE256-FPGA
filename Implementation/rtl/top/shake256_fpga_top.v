`timescale 1ns / 1ps

`include "../utils/keccak_defs.vh"

// FPGA-friendly top wrapper with low I/O count.
// It runs SHAKE256 for a 1-byte message and exposes one output byte.

module shake256_fpga_top (
    clk,
    rst_n,
    start_btn,
    msg_byte,
    done_led,
    hash_byte
);
    input clk;
    input rst_n;
    input start_btn;
    input [7:0] msg_byte;
    output done_led;
    output [7:0] hash_byte;

    reg start;
    reg absorb_block_valid;
    reg [1087:0] absorb_block_data;
    wire absorb_block_ready;

    wire squeeze_data_valid;
    wire [1087:0] squeeze_data;
    reg squeeze_data_ready;

    wire done;

    reg [1087:0] msg_block_in;
    reg [7:0] msg_len_bytes;
    wire [1087:0] pad_block0_out;
    wire [1087:0] pad_block1_out;
    wire needs_second_block;

    reg [15:0] num_input_blocks;
    reg [15:0] num_output_blocks;

    reg sent_block;
    (* IOB = "TRUE" *) reg [7:0] hash_byte_reg;
    (* IOB = "TRUE" *) reg done_led_reg;

    reg [1:0] state;
    localparam ST_IDLE = 2'd0;
    localparam ST_SEND = 2'd1;
    localparam ST_WAIT = 2'd2;

    shake256_pad_block u_pad (
        .msg_block_in(msg_block_in),
        .msg_len_bytes(msg_len_bytes),
        .pad_block0_out(pad_block0_out),
        .pad_block1_out(pad_block1_out),
        .needs_second_block(needs_second_block)
    );

    shake256_sponge u_sponge (
        .clk(clk),
        .rst_n(rst_n),
        .absorb_block_valid(absorb_block_valid),
        .absorb_block_data(absorb_block_data),
        .absorb_block_ready(absorb_block_ready),
        .squeeze_data_valid(squeeze_data_valid),
        .squeeze_data(squeeze_data),
        .squeeze_data_ready(squeeze_data_ready),
        .start(start),
        .done(done),
        .num_input_blocks(num_input_blocks),
        .num_output_blocks(num_output_blocks)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            start <= 1'b0;
            absorb_block_valid <= 1'b0;
            absorb_block_data <= 1088'd0;
            squeeze_data_ready <= 1'b1;
            msg_block_in <= 1088'd0;
            msg_len_bytes <= 8'd1;
            num_input_blocks <= 16'd1;
            num_output_blocks <= 16'd1;
            sent_block <= 1'b0;
            hash_byte_reg <= 8'h00;
            done_led_reg <= 1'b0;
        end else begin
            start <= 1'b0;
            absorb_block_valid <= 1'b0;
            squeeze_data_ready <= 1'b1;

            case (state)
                ST_IDLE: begin
                    done_led_reg <= 1'b0;
                    sent_block <= 1'b0;

                    if (start_btn) begin
                        // One-byte message to avoid constant-folding the full datapath.
                        msg_block_in <= 1088'd0;
                        msg_block_in[7:0] <= msg_byte;
                        msg_len_bytes <= 8'd1;
                        num_input_blocks <= 16'd1;
                        num_output_blocks <= 16'd1;

                        start <= 1'b1;
                        state <= ST_SEND;
                    end
                end

                ST_SEND: begin
                    if (absorb_block_ready && !sent_block) begin
                        absorb_block_data <= pad_block0_out;
                        absorb_block_valid <= 1'b1;
                        sent_block <= 1'b1;
                        state <= ST_WAIT;
                    end
                end

                ST_WAIT: begin
                    if (squeeze_data_valid) begin
                        hash_byte_reg <= squeeze_data[7:0];
                    end

                    if (done) begin
                        done_led_reg <= 1'b1;
                        // Start a new operation only after button is released.
                        if (!start_btn) begin
                            state <= ST_IDLE;
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    assign done_led = done_led_reg;
    assign hash_byte = hash_byte_reg;

endmodule
