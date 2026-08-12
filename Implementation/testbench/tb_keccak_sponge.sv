`timescale 1ns / 1ps

module tb_keccak_sponge;

    localparam integer BLK_WIDTH = 32;
    localparam integer TIMEOUT_CYCLES = 10000;
    localparam integer MAX_BUFFER = 128;
    localparam integer MAX_INPUT_BLOCKS = 16;
    localparam integer MAX_OUTPUT_BLOCKS = 4;
    localparam integer RATE_BITS = 1344;
    localparam integer META_BITS = 19;
    localparam integer OUTPUT_BASE = META_BITS + (MAX_INPUT_BLOCKS * RATE_BITS);
    localparam integer VECTOR_BITS = META_BITS +
                                     ((MAX_INPUT_BLOCKS + MAX_OUTPUT_BLOCKS) * RATE_BITS);

    logic clk, rst_n, start, absorb_block_valid, squeeze_data_ready, squeeze_data_last;
    logic [1:0] mode;
    logic [BLK_WIDTH-1:0] num_input_blocks, num_output_blocks, expected_output_blocks;
    logic [RATE_BITS-1:0] absorb_block_data;

    logic done, absorb_block_ready, squeeze_data_valid;
    logic [RATE_BITS-1:0] squeeze_data;
    logic [7:0] squeeze_bytes;

    logic [VECTOR_BITS-1:0] vec_all [0:MAX_BUFFER-1];
    logic [RATE_BITS-1:0] expected_block;
    logic [7:0] expected_squeeze_bytes;
    logic [639:0] line_buffer;

    int i, tv_count_actual, case_idx, error_count, spec_fd;
    logic timeout_flag, case_pass, stream_mode;

    keccak_sponge #(
        .BLOCK_WIDTH(BLK_WIDTH)
    ) u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .mode(mode),
        .absorb_valid(absorb_block_valid),
        .absorb_in(absorb_block_data),
        .absorb_ready(absorb_block_ready),
        .squeeze_ready(squeeze_data_ready),
        .squeeze_last(squeeze_data_last),
        .squeeze_valid(squeeze_data_valid),
        .squeeze_out(squeeze_data),
        .squeeze_bytes(squeeze_bytes),
        .start(start),
        .done(done),
        .input_blocks(num_input_blocks),
        .output_blocks(num_output_blocks)
    );

    initial begin
        clk = 1'b0;
        forever #2.5 clk = ~clk;
    end

    task safe_wait(input integer wait_mode);
    begin
        timeout_flag = 1'b0;
        fork : wait_block
            begin
                case (wait_mode)
                    0: wait(absorb_block_ready == 1'b1);
                    1: wait(squeeze_data_valid == 1'b1);
                    2: wait(squeeze_data_valid == 1'b0);
                    3: wait(done == 1'b1);
                endcase
                disable wait_block;
            end
            begin
                repeat(TIMEOUT_CYCLES) @(posedge clk);
                timeout_flag = 1'b1;
                disable wait_block;
            end
        join
    end
    endtask

    task run_one_case(input integer idx);
    begin : execute_case
        @(posedge clk); #0.5;
        rst_n = 1'b0;
        start = 1'b0;
        absorb_block_valid = 1'b0;
        repeat(5) @(posedge clk); #0.5;
        rst_n = 1'b1;
        repeat(2) @(posedge clk); #0.5;
        case_pass = 1'b1;

        mode = vec_all[idx][1:0];
        num_input_blocks = vec_all[idx][6:2];
        expected_output_blocks = vec_all[idx][9:7];
        stream_mode = vec_all[idx][10];
        num_output_blocks = stream_mode ? 0 : expected_output_blocks;
        expected_squeeze_bytes = vec_all[idx][18:11];

        @(posedge clk); #0.5; start = 1'b1;
        @(posedge clk); #0.5; start = 1'b0;

        for (i = 0; i < num_input_blocks; i = i + 1) begin
            safe_wait(0);
            if (timeout_flag) begin
                $display("FAIL: Case %0d - Absorb Timeout", idx);
                error_count = error_count + 1;
                disable execute_case;
            end

            absorb_block_data =
                vec_all[idx][META_BITS + (i * RATE_BITS) +: RATE_BITS];
            @(posedge clk); #0.5;
            absorb_block_valid = 1'b1;
            @(posedge clk); #0.5;
            absorb_block_valid = 1'b0;
        end

        for (i = 0; i < expected_output_blocks; i = i + 1) begin
            safe_wait(1);
            if (timeout_flag) begin
                $display("FAIL: Case %0d - Squeeze Timeout", idx);
                error_count = error_count + 1;
                disable execute_case;
            end

            expected_block =
                vec_all[idx][OUTPUT_BASE + (i * RATE_BITS) +: RATE_BITS];

            if ((squeeze_data !== expected_block) ||
                (squeeze_bytes !== expected_squeeze_bytes)) begin
                $display("FAIL: Case %0d mode=%0d block=%0d", idx, mode, i);
                if (case_pass) begin
                    error_count = error_count + 1;
                    case_pass = 1'b0;
                end
            end

            squeeze_data_last = stream_mode && (i == expected_output_blocks - 1);
            @(posedge clk); #0.5;
            squeeze_data_last = 1'b0;
            if (i < expected_output_blocks - 1)
                safe_wait(2);
        end

        safe_wait(3);
        if (timeout_flag) begin
            $display("FAIL: Case %0d - Done Timeout", idx);
            if (case_pass)
                error_count = error_count + 1;
            disable execute_case;
        end

        repeat(2) @(posedge clk);
    end
    endtask

    string tb_file, tb_dir, tv_dir;

    function automatic string dirname(input string path);
        int slash_pos = -1;

        for (int j = 0; j < path.len(); j++)
            if ((path[j] == 8'h2F) || (path[j] == 8'h5C)) slash_pos = j;

        if (slash_pos > 0)
            return path.substr(0, slash_pos - 1);
        else if (slash_pos == 0)
            return path.substr(0, 0);
        else
            return ".";
    endfunction

    initial begin
        tb_file = `__FILE__;
        tb_dir = dirname(tb_file);
        tv_dir = {tb_dir, "/../vector"};

        error_count = 0;
        rst_n = 0;
        start = 0;
        mode = 0;
        absorb_block_valid = 0;
        squeeze_data_ready = 1'b1;
        squeeze_data_last = 1'b0;

        spec_fd = $fopen({tv_dir, "/keccak_tv_spec.txt"}, "r");
        if (spec_fd == 0) begin
            $display("ERROR: Cannot open %s/keccak_tv_spec.txt", tv_dir);
            $finish;
        end

        void'($fgets(line_buffer, spec_fd));
        void'($sscanf(line_buffer, "tv_count=%d", tv_count_actual));
        $fclose(spec_fd);

        if (tv_count_actual > MAX_BUFFER) begin
            $display("ERROR: tv_count exceeds MAX_BUFFER");
            $finish;
        end

        $readmemh({tv_dir, "/keccak_tv_all.mem"}, vec_all);

        #100;
        @(posedge clk); #0.5;
        rst_n = 1'b1;
        repeat(5) @(posedge clk);

        for (case_idx = 0; case_idx < tv_count_actual; case_idx = case_idx + 1)
            run_one_case(case_idx);

        $display(">>> KECCAK SPONGE PASSED: %0d/%0d CASES (%0d ERRORS)",
            (tv_count_actual - error_count), tv_count_actual, error_count);
        $finish;
    end

endmodule
