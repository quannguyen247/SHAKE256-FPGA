`timescale 1ns / 1ps

module tb_keccak_pad_block;

    localparam integer MAX_BUFFER = 600;
    localparam integer VECTOR_BITS = 4043;

    logic [1:0] mode;
    logic [7:0] msg_len_bytes;
    logic [1343:0] msg_block_in;
    logic [1343:0] pad_block0_out, pad_block1_out;
    logic need_block2;

    logic [VECTOR_BITS-1:0] vec_all [0:MAX_BUFFER-1];
    logic [1343:0] expected_block0, expected_block1;
    logic expected_need_block2;
    logic [639:0] line_buffer;

    int tv_count_actual, case_idx, error_count, spec_fd;

    keccak_pad_block u_dut (
        .mode(mode),
        .msg_block_in(msg_block_in),
        .msg_len_bytes(msg_len_bytes),
        .pad_block0_out(pad_block0_out),
        .pad_block1_out(pad_block1_out),
        .need_block2(need_block2)
    );

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
        mode = 0;
        msg_len_bytes = 0;
        msg_block_in = 0;

        spec_fd = $fopen({tv_dir, "/keccak_pad_tv_spec.txt"}, "r");
        if (spec_fd == 0) begin
            $display("ERROR: Cannot open %s/keccak_pad_tv_spec.txt", tv_dir);
            $finish;
        end

        void'($fgets(line_buffer, spec_fd));
        void'($sscanf(line_buffer, "tv_count=%d", tv_count_actual));
        $fclose(spec_fd);

        if (tv_count_actual > MAX_BUFFER) begin
            $display("ERROR: tv_count exceeds MAX_BUFFER");
            $finish;
        end

        $readmemh({tv_dir, "/keccak_pad_tv_all.mem"}, vec_all);

        for (case_idx = 0; case_idx < tv_count_actual; case_idx = case_idx + 1) begin
            mode = vec_all[case_idx][1:0];
            msg_len_bytes = vec_all[case_idx][9:2];
            expected_need_block2 = vec_all[case_idx][10];
            msg_block_in = vec_all[case_idx][1354:11];
            expected_block0 = vec_all[case_idx][2698:1355];
            expected_block1 = vec_all[case_idx][4042:2699];
            #1;

            if ((pad_block0_out !== expected_block0) ||
                (pad_block1_out !== expected_block1) ||
                (need_block2 !== expected_need_block2)) begin
                $display("FAIL: Case %0d mode=%0d len=%0d", case_idx, mode, msg_len_bytes);
                error_count = error_count + 1;
            end
        end

        $display(">>> KECCAK PAD PASSED: %0d/%0d CASES (%0d ERRORS)",
            (tv_count_actual - error_count), tv_count_actual, error_count);
        $finish;
    end

endmodule
