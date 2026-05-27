`timescale 1ns / 1ps
`include "keccak_defs.vh"

module shake256_axi4_stream #(
    parameter integer C_OUTPUT_BLOCKS = 1
)(
    input wire aclk,
    input wire aresetn,

    input wire [7:0] s_axis_tdata,
    input wire s_axis_tvalid,
    output wire s_axis_tready,
    input wire s_axis_tlast,

    output wire [7:0] m_axis_tdata,
    output wire m_axis_tvalid,
    input wire m_axis_tready,
    output wire m_axis_tlast
);

    localparam [7:0] ST_IDLE    = 8'b00000001;
    localparam [7:0] ST_RECV    = 8'b00000010;
    localparam [7:0] ST_START   = 8'b00000100;
    localparam [7:0] ST_ABSORB  = 8'b00001000;
    localparam [7:0] ST_SQ_WAIT = 8'b00010000;
    localparam [7:0] ST_SEND    = 8'b00100000;
    localparam [7:0] ST_SQ_ACK  = 8'b01000000;
    localparam [7:0] ST_DONE    = 8'b10000000;

    reg [7:0] state, next_state;
    reg [1087:0] msg_buf;
    reg [7:0] byte_cnt;
    reg [7:0] msg_len;
    reg [7:0] send_cnt;
    reg [31:0] sq_blk_cnt;
    reg abs_idx;
    reg done_seen;

    wire [1087:0] pad_blk0, pad_blk1;
    wire need_blk2;

    reg sponge_start;
    wire sponge_done;
    reg abs_valid;
    wire [1087:0] abs_data;
    wire abs_ready;
    reg sq_ready;
    wire sq_valid;
    wire [1087:0] sq_out;

    wire s_axis_fire;
    wire m_axis_fire;
    wire abs_fire;
    wire send_last_byte;
    wire send_last_block;

    shake256_pad_block u_pad (
        .msg_block_in(msg_buf),
        .msg_len_bytes(msg_len),
        .pad_block0_out(pad_blk0),
        .pad_block1_out(pad_blk1),
        .need_block2(need_blk2)
    );

    shake256_sponge #(
        .BLOCK_WIDTH(32)
    ) u_sponge (
        .clk(aclk),
        .rst_n(aresetn),
        .absorb_valid(abs_valid),
        .absorb_in(abs_data),
        .absorb_ready(abs_ready),
        .squeeze_ready(sq_ready),
        .squeeze_valid(sq_valid),
        .squeeze_out(sq_out),
        .start(sponge_start),
        .done(sponge_done),
        .input_blocks(need_blk2 ? 32'd2 : 32'd1),
        .output_blocks(C_OUTPUT_BLOCKS)
    );

    assign s_axis_tready = (state == ST_IDLE) || ((state == ST_RECV) && (byte_cnt < 8'd136));
    assign s_axis_fire = s_axis_tvalid && s_axis_tready;
    assign m_axis_tvalid = (state == ST_SEND);
    assign m_axis_fire = m_axis_tvalid && m_axis_tready;
    assign abs_data = (abs_idx == 1'b0) ? pad_blk0 : pad_blk1;
    assign abs_fire = abs_valid && abs_ready;
    assign send_last_byte = (send_cnt == 8'd135);
    assign send_last_block = (sq_blk_cnt == 32'd1);
    assign m_axis_tdata = sq_out[(send_cnt*8) +: 8];
    assign m_axis_tlast = (state == ST_SEND) && send_last_block && send_last_byte;

    always @(*) begin
        next_state = state;
        case (state)
            ST_IDLE: begin
                if (s_axis_fire) begin
                    if (s_axis_tlast) next_state = ST_START;
                    else next_state = ST_RECV;
                end
            end
            ST_RECV: if (s_axis_fire && s_axis_tlast) next_state = ST_START;
            ST_START: next_state = ST_ABSORB;
            ST_ABSORB: begin
                if (abs_fire) 
                    if (!need_blk2 || abs_idx == 1'b1) next_state = ST_SQ_WAIT;
            end
            ST_SQ_WAIT: if (sq_valid) next_state = ST_SEND;
            ST_SEND: begin
                if (m_axis_fire && send_last_byte) begin
                    if (send_last_block) next_state = ST_DONE;
                    else next_state = ST_SQ_ACK;
                end
            end
            ST_SQ_ACK: next_state = ST_SQ_WAIT;
            ST_DONE: if (sponge_done || done_seen) next_state = ST_IDLE;
            default: next_state = ST_IDLE;
        endcase
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            state <= ST_IDLE;
            msg_buf <= 1088'h0;
            byte_cnt <= 8'd0;
            msg_len <= 8'd0;
            send_cnt <= 8'd0;
            sq_blk_cnt <= 32'd0;
            abs_idx <= 1'b0;
            done_seen <= 1'b0;
            abs_valid <= 1'b0;
            sq_ready <= 1'b0;
            sponge_start <= 1'b0;
        end else begin
            state <= next_state;
            sponge_start <= 1'b0;
            sq_ready <= 1'b0;

            if (sponge_done) done_seen <= 1'b1;

            case (state)
                ST_IDLE: begin
                    msg_buf <= 1088'h0;
                    byte_cnt <= 8'd0;
                    msg_len <= 8'd0;
                    send_cnt <= 8'd0;
                    sq_blk_cnt <= 32'd0;
                    abs_idx <= 1'b0;
                    done_seen <= 1'b0;
                    abs_valid <= 1'b0;
                    if (s_axis_fire) begin
                        msg_buf[7:0] <= s_axis_tdata;
                        if (s_axis_tlast) msg_len <= 8'd1;
                        else byte_cnt <= 8'd1;
                    end
                end
                ST_RECV: begin
                    if (s_axis_fire) begin
                        msg_buf[(byte_cnt*8) +: 8] <= s_axis_tdata;
                        if (s_axis_tlast) msg_len <= byte_cnt + 8'd1;
                        else byte_cnt <= byte_cnt + 8'd1;
                    end
                end
                ST_START: begin
                    sponge_start <= 1'b1;
                    sq_blk_cnt <= C_OUTPUT_BLOCKS;
                    abs_idx <= 1'b0;
                    abs_valid <= 1'b0;
                    done_seen <= 1'b0;
                end
                ST_ABSORB: begin
                    if (!abs_valid) abs_valid <= 1'b1;
                    else if (abs_fire) begin
                        if (need_blk2 && abs_idx == 1'b0) begin
                            abs_idx <= 1'b1;
                            abs_valid <= 1'b1;
                        end else begin
                            abs_valid <= 1'b0;
                        end
                    end
                end
                ST_SQ_WAIT: send_cnt <= 8'd0;
                ST_SEND: begin
                    if (m_axis_fire) begin
                        if (send_last_byte) sq_ready <= 1'b1;
                        else send_cnt <= send_cnt + 8'd1;
                    end
                end
                ST_SQ_ACK: begin
                    sq_blk_cnt <= sq_blk_cnt - 32'd1;
                    send_cnt <= 8'd0;
                end
                ST_DONE: abs_valid <= 1'b0;
            endcase
        end
    end

endmodule