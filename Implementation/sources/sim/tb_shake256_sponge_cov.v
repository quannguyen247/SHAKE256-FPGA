`timescale 1ns / 1ps

`include "../../rtl/utils/keccak_defs.vh"
`include "generated/tv_meta.vh"

// Full-coverage SHAKE256 verification testbench.
// It loads deterministic vectors generated from PQClean and compares
// full 136-byte squeeze blocks (1 or 2 blocks per case).

module tb_shake256_sponge_cov;

    localparam integer TV_COUNT = `TV_COUNT;

    reg clk;
    reg rst_n;

    reg absorb_block_valid;
    reg [1087:0] absorb_block_data;
    wire absorb_block_ready;

    wire squeeze_data_valid;
    wire [1087:0] squeeze_data;
    reg squeeze_data_ready;

    reg start;
    wire done;
    reg [15:0] num_input_blocks;
    reg [15:0] num_output_blocks;

    reg [1087:0] msg_block_in;
    reg [7:0] msg_len_bytes;
    wire [1087:0] pad_block0_out;
    wire [1087:0] pad_block1_out;
    wire needs_second_block;

    reg [7:0] vec_msg_len [0:TV_COUNT-1];
    reg [7:0] vec_num_out_blocks [0:TV_COUNT-1];
    reg [1087:0] vec_msg_block [0:TV_COUNT-1];
    reg [1087:0] vec_exp_out0 [0:TV_COUNT-1];
    reg [1087:0] vec_exp_out1 [0:TV_COUNT-1];

    integer case_idx;
    integer error_count;
    integer timeout_count;
    integer ok;

    shake256_sponge u_dut (
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

    shake256_pad_block u_pad (
        .msg_block_in(msg_block_in),
        .msg_len_bytes(msg_len_bytes),
        .pad_block0_out(pad_block0_out),
        .pad_block1_out(pad_block1_out),
        .needs_second_block(needs_second_block)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task send_absorb_block;
        input [1087:0] block_data;
        begin
            timeout_count = 0;
            while ((absorb_block_ready !== 1'b1) && (timeout_count < 3000)) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
            end

            if (absorb_block_ready !== 1'b1) begin
                $display("ERROR: absorb_block_ready timeout");
                error_count = error_count + 1;
            end else begin
                @(negedge clk);
                absorb_block_data = block_data;
                absorb_block_valid = 1'b1;
                @(negedge clk);
                absorb_block_valid = 1'b0;
                absorb_block_data = 1088'd0;
            end
        end
    endtask

    task wait_for_squeeze_valid;
        output integer found;
        begin
            timeout_count = 0;
            found = 0;

            while ((squeeze_data_valid !== 1'b1) && (timeout_count < 6000)) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
            end

            if (squeeze_data_valid === 1'b1) begin
                found = 1;
            end
        end
    endtask

    task wait_for_squeeze_drop;
        output integer dropped;
        begin
            timeout_count = 0;
            dropped = 0;

            while ((squeeze_data_valid === 1'b1) && (timeout_count < 6000)) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
            end

            if (squeeze_data_valid !== 1'b1) begin
                dropped = 1;
            end
        end
    endtask

    task run_one_case;
        input integer idx;
        begin
            msg_block_in = vec_msg_block[idx];
            msg_len_bytes = vec_msg_len[idx];
            #1;

            num_input_blocks = needs_second_block ? 16'd2 : 16'd1;
            num_output_blocks = {8'd0, vec_num_out_blocks[idx]};

            if ((vec_num_out_blocks[idx] != 8'd1) && (vec_num_out_blocks[idx] != 8'd2)) begin
                $display("ERROR: case %0d invalid num_out_blocks=%0d", idx, vec_num_out_blocks[idx]);
                error_count = error_count + 1;
            end

            if ((needs_second_block && (vec_msg_len[idx] != 8'd136)) ||
                ((!needs_second_block) && (vec_msg_len[idx] == 8'd136))) begin
                $display("ERROR: case %0d pad-block expectation mismatch (msg_len=%0d)", idx, vec_msg_len[idx]);
                error_count = error_count + 1;
            end

            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            send_absorb_block(pad_block0_out);
            if (needs_second_block) begin
                send_absorb_block(pad_block1_out);
            end

            wait_for_squeeze_valid(ok);
            if (!ok) begin
                $display("ERROR: case %0d first squeeze timeout", idx);
                error_count = error_count + 1;
            end else if (squeeze_data !== vec_exp_out0[idx]) begin
                $display("ERROR: case %0d block0 mismatch", idx);
                $display("  observed = 0x%0272x", squeeze_data);
                $display("  expect   = 0x%0272x", vec_exp_out0[idx]);
                error_count = error_count + 1;
            end

            if (vec_num_out_blocks[idx] == 8'd2) begin
                wait_for_squeeze_drop(ok);
                if (!ok) begin
                    $display("ERROR: case %0d squeeze_valid did not drop", idx);
                    error_count = error_count + 1;
                end

                wait_for_squeeze_valid(ok);
                if (!ok) begin
                    $display("ERROR: case %0d second squeeze timeout", idx);
                    error_count = error_count + 1;
                end else if (squeeze_data !== vec_exp_out1[idx]) begin
                    $display("ERROR: case %0d block1 mismatch", idx);
                    $display("  observed = 0x%0272x", squeeze_data);
                    $display("  expect   = 0x%0272x", vec_exp_out1[idx]);
                    error_count = error_count + 1;
                end
            end

            timeout_count = 0;
            while ((done !== 1'b1) && (timeout_count < 6000)) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
            end
            if (done !== 1'b1) begin
                $display("ERROR: case %0d done timeout", idx);
                error_count = error_count + 1;
            end

            repeat (2) @(negedge clk);
        end
    endtask

    initial begin
        error_count = 0;

        rst_n = 1'b0;
        absorb_block_valid = 1'b0;
        absorb_block_data = 1088'd0;
        squeeze_data_ready = 1'b1;
        start = 1'b0;
        num_input_blocks = 16'd0;
        num_output_blocks = 16'd0;
        msg_block_in = 1088'd0;
        msg_len_bytes = 8'd0;

        $readmemh("generated/tv_msg_len.mem", vec_msg_len);
        $readmemh("generated/tv_num_out_blocks.mem", vec_num_out_blocks);
        $readmemh("generated/tv_msg_block.mem", vec_msg_block);
        $readmemh("generated/tv_exp_out_block0.mem", vec_exp_out0);
        $readmemh("generated/tv_exp_out_block1.mem", vec_exp_out1);

        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        $display("=== SHAKE256 Full-Coverage Vector Test ===");
        $display("Vector count: %0d", TV_COUNT);

        for (case_idx = 0; case_idx < TV_COUNT; case_idx = case_idx + 1) begin
            run_one_case(case_idx);
        end

        if (error_count == 0) begin
            $display("=== SHAKE256 FULL-COVERAGE PASS (%0d cases) ===", TV_COUNT);
        end else begin
            $display("=== SHAKE256 FULL-COVERAGE FAIL: %0d error(s) over %0d cases ===", error_count, TV_COUNT);
        end

        $finish;
    end

endmodule
