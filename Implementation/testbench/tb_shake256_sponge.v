`timescale 1ns / 1ps

`include "../rtl/utils/keccak_defs.vh"

// End-to-end SHAKE256 sponge testbench using known-answer vectors.
// The first 32 bytes are compared against reference outputs from PQClean.

module tb_shake256_sponge;

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

    reg [255:0] observed_first32;

    integer i;
    integer error_count;

    localparam [255:0] EXP_EMPTY_LE = 256'h2f76d56e64270cb5821bb862ea52cd3f24eb3e74eb3f3b23138da80b2bddb946;
    localparam [255:0] EXP_A_LE     = 256'ha40b534280136c73ca26562550caafea9cfee8a5012559bddc045a4fb02c7e86;
    localparam [255:0] EXP_ABC_LE   = 256'h39578be737ea944feee1f1f83045b48d4d11c40c0863681c77a8601360663348;
    localparam [255:0] EXP_136_LE   = 256'h7ad6b963303a7ea4a681f79d8f05311a76f6a75c70176ebdeaa8f5b37340ffb7;

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

    task prepare_case;
        input integer case_id;
        begin
            msg_block_in = 1088'd0;
            msg_len_bytes = 8'd0;

            case (case_id)
                0: begin
                    // Empty message
                    msg_len_bytes = 8'd0;
                end
                1: begin
                    // "a"
                    msg_len_bytes = 8'd1;
                    msg_block_in[7:0] = 8'h61;
                end
                2: begin
                    // "abc"
                    msg_len_bytes = 8'd3;
                    msg_block_in[7:0] = 8'h61;
                    msg_block_in[15:8] = 8'h62;
                    msg_block_in[23:16] = 8'h63;
                end
                3: begin
                    // 136-byte pattern 0x00..0x87
                    msg_len_bytes = 8'd136;
                    for (i = 0; i < 136; i = i + 1) begin
                        msg_block_in[(8 * i) +: 8] = i[7:0];
                    end
                end
                default: begin
                    msg_len_bytes = 8'd0;
                end
            endcase

            #1;
        end
    endtask

    task send_absorb_block;
        input [1087:0] block_data;
        begin
            wait (absorb_block_ready == 1'b1);
            @(negedge clk);
            absorb_block_data = block_data;
            absorb_block_valid = 1'b1;
            @(negedge clk);
            absorb_block_valid = 1'b0;
            absorb_block_data = 1088'd0;
        end
    endtask

    task run_case;
        input integer case_id;
        input [255:0] expected_first32_le;
        begin
            prepare_case(case_id);

            num_input_blocks = needs_second_block ? 16'd2 : 16'd1;
            num_output_blocks = 16'd1;

            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            send_absorb_block(pad_block0_out);
            if (needs_second_block) begin
                send_absorb_block(pad_block1_out);
            end

            wait (squeeze_data_valid == 1'b1);
            observed_first32 = squeeze_data[255:0];

            if (observed_first32 !== expected_first32_le) begin
                $display("Case %0d FAIL", case_id);
                $display("  observed[31:0 bytes] = 0x%064x", observed_first32);
                $display("  expected[31:0 bytes] = 0x%064x", expected_first32_le);
                error_count = error_count + 1;
            end else begin
                $display("Case %0d PASS", case_id);
            end

            wait (done == 1'b1);
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
        observed_first32 = 256'd0;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        $display("=== SHAKE256 Sponge KAT Testbench ===");

        run_case(0, EXP_EMPTY_LE);
        run_case(1, EXP_A_LE);
        run_case(2, EXP_ABC_LE);
        run_case(3, EXP_136_LE);

        if (error_count == 0) begin
            $display("=== All sponge KAT cases PASSED ===");
        end else begin
            $display("=== FAILED: %0d sponge KAT case(s) failed ===", error_count);
        end

        $finish;
    end

endmodule
